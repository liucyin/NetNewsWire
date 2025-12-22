//
//  DetailWebViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/11/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import AppKit
@preconcurrency import WebKit
import RSCore
import RSWeb
import Articles

@MainActor protocol DetailWebViewControllerDelegate: AnyObject {
	func mouseDidEnter(_: DetailWebViewController, link: String)
	func mouseDidExit(_: DetailWebViewController)
    func detailWebViewControllerDidFinishLoad(_: DetailWebViewController)
}

struct AIPhrase: Decodable {
    let id: String
    let text: String
}

final class DetailWebViewController: NSViewController {

	weak var delegate: DetailWebViewControllerDelegate?
	var webView: DetailWebView!
	var state: DetailState = .noSelection {
		didSet {
			if state != oldValue {
				switch state {
				case .article(_, let scrollY), .extracted(_, _, let scrollY):
					windowScrollY = scrollY
				default:
					break
				}
				reloadHTML()
			}
		}
	}

	var windowState: DetailWindowState {
		DetailWindowState(isShowingExtractedArticle: isShowingExtractedArticle, windowScrollY: windowScrollY ?? 0)
	}

	var article: Article? {
		switch state {
		case .article(let article, _):
			return article
		case .extracted(let article, _, _):
			return article
		default:
			return nil
		}
	}

	private var articleTextSize = AppDefaults.shared.articleTextSize

	private var webInspectorEnabled: Bool {
		get {
			return webView.configuration.preferences._developerExtrasEnabled
		}
		set {
			webView.configuration.preferences._developerExtrasEnabled = newValue
		}
	}

	private let detailIconSchemeHandler = DetailIconSchemeHandler()
	private var waitingForFirstReload = false
	private let keyboardDelegate = DetailKeyboardDelegate()
	private var windowScrollY: CGFloat?

	private var isShowingExtractedArticle: Bool {
		switch state {
		case .extracted(_, _, _):
			return true
		default:
			return false
		}
	}

	private struct MessageName {
		static let mouseDidEnter = "mouseDidEnter"
		static let mouseDidExit = "mouseDidExit"
		static let windowDidScroll = "windowDidScroll"
	}

	override func loadView() {

		let configuration = WebViewConfiguration.configuration(with: detailIconSchemeHandler)

		configuration.userContentController.add(self, name: MessageName.windowDidScroll)
		configuration.userContentController.add(self, name: MessageName.mouseDidEnter)
		configuration.userContentController.add(self, name: MessageName.mouseDidExit)

		webView = DetailWebView(frame: NSRect.zero, configuration: configuration)
		webView.uiDelegate = self
		webView.navigationDelegate = self
		webView.keyboardDelegate = keyboardDelegate
		webView.translatesAutoresizingMaskIntoConstraints = false
		if let userAgent = UserAgent.fromInfoPlist() {
			webView.customUserAgent = userAgent
		}

		view = webView

		// Hide the web view until the first reload (navigation) is committed (plus some delay) to avoid the white flash that happens on initial display in dark mode.
		// See bug #901.
		webView.isHidden = true
		waitingForFirstReload = true

		webInspectorEnabled = AppDefaults.shared.webInspectorEnabled
		NotificationCenter.default.addObserver(self, selector: #selector(webInspectorEnabledDidChange(_:)), name: .WebInspectorEnabledDidChange, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}
		NotificationCenter.default.addObserver(self, selector: #selector(currentArticleThemeDidChangeNotification(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)

		webView.loadFileURL(ArticleRenderer.blank.url, allowingReadAccessTo: ArticleRenderer.blank.baseURL)
	}

	// MARK: Notifications

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func avatarDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	@objc func faviconDidBecomeAvailable(_ note: Notification) {
		reloadArticleImage()
	}

	func userDefaultsDidChange() {
		if articleTextSize != AppDefaults.shared.articleTextSize {
			articleTextSize = AppDefaults.shared.articleTextSize
			reloadHTMLMaintainingScrollPosition()
		}
	}

	@objc func currentArticleThemeDidChangeNotification(_ note: Notification) {
		reloadHTMLMaintainingScrollPosition()
	}

	// MARK: Media Functions

	func stopMediaPlayback() {
		webView.evaluateJavaScript("stopMediaPlayback();")
	}

	// MARK: Scrolling

	func canScrollDown() async -> Bool {
		let scrollInfo = await fetchScrollInfo()
		return scrollInfo?.canScrollDown ?? false
	}

	func canScrollUp() async -> Bool {
		let scrollInfo = await fetchScrollInfo()
		return scrollInfo?.canScrollUp ?? false
	}

	override func scrollPageDown(_ sender: Any?) {
		webView.scrollPageDown(sender)
	}

	override func scrollPageUp(_ sender: Any?) {
		webView.scrollPageUp(sender)
	}
}

// MARK: - WKScriptMessageHandler

extension DetailWebViewController: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if message.name == MessageName.windowDidScroll {
			windowScrollY = message.body as? CGFloat
		} else if message.name == MessageName.mouseDidEnter, let link = message.body as? String {
			delegate?.mouseDidEnter(self, link: link)
		} else if message.name == MessageName.mouseDidExit {
			delegate?.mouseDidExit(self)
		}
	}
}

// MARK: - WKNavigationDelegate & WKUIDelegate

extension DetailWebViewController: WKNavigationDelegate, WKUIDelegate {

	// Bottleneck through which WebView-based URL opens go
	func openInBrowser(_ url: URL, flags: NSEvent.ModifierFlags) {
		let invert = flags.contains(.shift) || flags.contains(.command)
		Browser.open(url.absoluteString, invertPreference: invert)
	}

	// WKNavigationDelegate

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
		if navigationAction.navigationType == .linkActivated {
			if let url = navigationAction.request.url {
				self.openInBrowser(url, flags: navigationAction.modifierFlags)
			}
			decisionHandler(.cancel)
			return
		}
		
		decisionHandler(.allow)
	}

	public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
		// See note in loadView()
		guard waitingForFirstReload else {
			return
		}

		assert(webView.isHidden)
		waitingForFirstReload = false
		reloadHTML()

		// Waiting for the first navigation to commit isn't enough to avoid the flash of white.
		// Delaying an additional half a second seems to be enough.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			webView.isHidden = false
		}
	}

	public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard let windowScrollY else {
			return
		}
		webView.evaluateJavaScript("window.scrollTo(0, \(windowScrollY));")
		self.windowScrollY = nil
	}

	// WKUIDelegate

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		// This method is reached when WebKit handles a JavaScript based window.open() invocation, for example. One
		// example where this is used is in YouTube's embedded video player when a user clicks on the video's title
		// or on the "Watch in YouTube" button. For our purposes we'll handle such window.open calls the same way we
		// handle clicks on a URL.
		if let url = navigationAction.request.url {
			self.openInBrowser(url, flags: navigationAction.modifierFlags)
		}

		return nil
	}
}

// MARK: - Private

private extension DetailWebViewController {

	func reloadArticleImage() {
		guard let article = article else { return }

		var components = URLComponents()
		components.scheme = ArticleRenderer.imageIconScheme
		components.path = article.articleID

		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
	}

	func reloadHTMLMaintainingScrollPosition() {
		fetchScrollInfo() { scrollInfo in
			self.windowScrollY = scrollInfo?.offsetY
			self.reloadHTML()
		}
	}

	func reloadHTML() {
		delegate?.mouseDidExit(self)

		let theme = ArticleThemesManager.shared.currentTheme
		let rendering: ArticleRenderer.Rendering

		switch state {
		case .noSelection:
			rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		case .multipleSelection:
			rendering = ArticleRenderer.multipleSelectionHTML(theme: theme)
		case .loading:
			rendering = ArticleRenderer.loadingHTML(theme: theme)
		case .article(let article, _):
			detailIconSchemeHandler.currentArticle = article
			rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
		case .extracted(let article, let extractedArticle, _):
			detailIconSchemeHandler.currentArticle = article
			rendering = ArticleRenderer.articleHTML(article: article, extractedArticle: extractedArticle, theme: theme)
		}

		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": rendering.html
		]

		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}

	func fetchScrollInfo() async -> ScrollInfo? {
		await withCheckedContinuation { continuation in
			self.fetchScrollInfo { scrollInfo in
				continuation.resume(returning: scrollInfo)
			}
		}
	}

	private func fetchScrollInfo(_ completion: @escaping (ScrollInfo?) -> Void) {
		let javascriptString = "var x = {contentHeight: document.body.scrollHeight, offsetY: document.body.scrollTop}; x"

		webView.evaluateJavaScript(javascriptString) { (info, error) in
			guard let info = info as? [String: Any] else {
				completion(nil)
				return
			}
			guard let contentHeight = info["contentHeight"] as? CGFloat, let offsetY = info["offsetY"] as? CGFloat else {
				completion(nil)
				return
			}

			let scrollInfo = ScrollInfo(contentHeight: contentHeight, viewHeight: self.webView.frame.height, offsetY: offsetY)
			completion(scrollInfo)
		}
	}

	@objc func webInspectorEnabledDidChange(_ notification: Notification) {
		self.webInspectorEnabled = notification.object! as! Bool
	}
}

// MARK: - ScrollInfo

private struct ScrollInfo {

	let contentHeight: CGFloat
	let viewHeight: CGFloat
	let offsetY: CGFloat
	let canScrollDown: Bool
	let canScrollUp: Bool

	init(contentHeight: CGFloat, viewHeight: CGFloat, offsetY: CGFloat) {
		self.contentHeight = contentHeight
		self.viewHeight = viewHeight
		self.offsetY = offsetY

		self.canScrollDown = viewHeight + offsetY < contentHeight
		self.canScrollUp = offsetY > 0.1
	}
}

// MARK: - AI Injection
extension DetailWebViewController {
    
    func showAISummaryLoading() {
        let js = """
        (function() {
            var summaryDiv = document.getElementById('aiSummary');
            if (summaryDiv) {
                summaryDiv.style.display = 'block';
                summaryDiv.style.padding = '15px';
                summaryDiv.style.marginBottom = '20px';
                summaryDiv.style.backgroundColor = 'var(--secondary-group-background-color, #f5f5f5)';
                summaryDiv.style.borderRadius = '8px';
                summaryDiv.style.border = '1px solid var(--separator-color, #e0e0e0)';
                summaryDiv.style.color = 'var(--label-color, #333)';
                
                // Loading Animation
                summaryDiv.innerHTML = `
                    <div style="display: flex; align-items: center; gap: 8px;">
                        <span style="font-weight: 600;">Generating AI Summary</span>
                        <div class="ai-spinner" style="width: 16px; height: 16px; border: 2px solid var(--accent-color); border-top-color: transparent; border-radius: 50%; animation: spin 0.8s linear infinite;"></div>
                    </div>
                    <style>
                        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
                    </style>
                `;
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }

    func injectAISummary(_ text: String) {
        let html = markdownToHTML(text)
        let escaped = html.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: "") 

        let js = """
        (function() {
            var summaryDiv = document.getElementById('aiSummary');
            if (summaryDiv) {
                // Styling
                summaryDiv.style.padding = '16px';
                summaryDiv.style.marginBottom = '24px';
                summaryDiv.style.backgroundColor = 'var(--secondary-group-background-color, #f9f9f9)'; // Adaptive color if possible
                summaryDiv.style.borderRadius = '10px';
                summaryDiv.style.border = '1px solid var(--separator-color, #eaeaea)';
                summaryDiv.style.fontFamily = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif';
                summaryDiv.style.fontSize = '15px';
                summaryDiv.style.lineHeight = '1.6';
                summaryDiv.style.color = 'var(--label-color)';
                
                // Header style
                var content = `
                <div style="display: flex; align-items: center; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid var(--separator-color);">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 8px; color: var(--accent-color);">
                      <path d="M12 2a10 10 0 1 0 10 10A10 10 0 0 0 12 2zm0 18a8 8 0 1 1 8-8 8 8 0 0 1-8 8z"></path>
                      <path d="M12 8v8"></path>
                      <path d="M8 12h8"></path>
                    </svg>
                    <span style="font-weight: 700; font-size: 14px; text-transform: uppercase; color: var(--secondary-label-color);">AI Summary</span>
                </div>
                <div class="ai-content">\(escaped)</div>
                <style>
                    .ai-content h1, .ai-content h2, .ai-content h3 { margin-top: 1em; margin-bottom: 0.5em; color: var(--header-text-color); }
                    .ai-content h3 { font-size: 1.1em; }
                    .ai-content p { margin-bottom: 0.8em; }
                    .ai-content ul, .ai-content ol { margin-bottom: 0.8em; padding-left: 20px; }
                    .ai-content li { margin-bottom: 0.4em; }
                </style>
                `;
                
                summaryDiv.innerHTML = content;
                summaryDiv.style.display = 'block';
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }
    
    // ... (prepareForTranslation stays same) ...
    
    func injectTranslation(id: String, text: String) {
        let html = markdownToHTML(text)
        let escaped = html.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: "")
        
        let js = """
        (function() {
            var node = document.getElementById('\(id)');
            if (node) {
                // Check if already has translation
                var existing = node.nextElementSibling;
                if (existing && existing.className == 'ai-translation') {
                    existing.innerHTML = "\(escaped)";
                } else {
                    var div = document.createElement('div');
                    div.className = 'ai-translation';
                    div.style.color = '#666'; 
                    div.style.fontStyle = 'italic';
                    div.style.marginTop = '4px';
                    div.style.marginBottom = '12px';
                    div.style.paddingLeft = '10px';
                    div.style.borderLeft = '2px solid var(--accent-color)';
                    div.innerHTML = "\(escaped)";
                    node.parentNode.insertBefore(div, node.nextSibling);
                }
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }
    
    private func markdownToHTML(_ text: String) -> String {
        // Simple regex-based markdown parser
        var html = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        
        // Headers (### Heading) - Order matters (match longest first)
        html = html.replacingOccurrences(of: #"(?m)^######\s+(.+)$"#, with: "<h6>$1</h6>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^#####\s+(.+)$"#, with: "<h5>$1</h5>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^####\s+(.+)$"#, with: "<h4>$1</h4>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^###\s+(.+)$"#, with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^##\s+(.+)$"#, with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^#\s+(.+)$"#, with: "<h1>$1</h1>", options: .regularExpression)
        
        // Blockquotes (> text)
        html = html.replacingOccurrences(of: #"(?m)^>\s+(.+)$"#, with: "<blockquote>$1</blockquote>", options: .regularExpression)
        
        // Bold (**text**)
        html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"\_\_(.+?)\_\_"#, with: "<strong>$1</strong>", options: .regularExpression)
        
        // Italic (*text*)
        html = html.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"\b_([^_]+)_\b"#, with: "<em>$1</em>", options: .regularExpression)
        
        // Lists (- item or * item) - handle optional indentation
        html = html.replacingOccurrences(of: #"(?m)^\s*[-*]\s+(.+)$"#, with: "<li>$1</li>", options: .regularExpression)
        
        // Code blocks (```code```) - simplified (inline or multiline)
        // Note: Real multiline code block handling with regex is tricky without state, but strict replacement of ```...``` might work for simple cases.
        // Let's rely on basic `code` tag.
        html = html.replacingOccurrences(of: #"```([^`]+)```"#, with: "<pre><code>$1</code></pre>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)

        // Newlines cleanup
        
        // 1. Remove newlines after block elements to prevent double spacing
        // Matches </h1>, </h2>, </blockquote>, </li>, </pre>, then optional whitespace and newlines
        html = html.replacingOccurrences(of: #"(?i)(</(h[1-6]|blockquote|li|pre)>)\s*\n+"#, with: "$1", options: .regularExpression)
        
        // 2. Convert remaining newlines to <br>
        // Collapse multiple empty lines if desired, but standard md is \n\n = new p.
        // Here we just turn each \n to <br>.
        // To avoid excessive spacing for normal text "Text\n\nText" -> "Text<br><br>Text", this is fine.
        // It's mainly headers causing issues.
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        
        return html
    }

    // Returns a dictionary of [ID: Text]
    func prepareForTranslation() async -> [String: String] {
        let js = """
        (function() {
            var nodes = document.querySelectorAll('p, li, blockquote, h1, h2, h3, h4, h5, h6');
            var result = [];
            
            // Regex for checking if text is just a URL
            var urlRegex = /^(https?:\\/\\/[^\\s]+)$/i;

            for (var i = 0; i < nodes.length; i++) {
                var node = nodes[i];
                if (!node.id) {
                    node.id = 'ai-p-' + i + '-' + Date.now();
                }
                var text = node.innerText.trim();
                
                // Skip if empty or too short
                if (text.length <= 10) continue;
                
                // Skip if it looks like a raw URL
                if (urlRegex.test(text)) continue;

                // Skip if it looks like code (often inside pre/code blocks, but selector excludes pre, so maybe okay)
                // But p tags might contain code.
                
                result.push({id: node.id, text: text});
            }
            return result;
        })();
        """
        
        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [[String: String]] else {
                return [:]
            } // Cast to Array of Dicts
            
            var map = [String: String]()
            for item in result {
                if let id = item["id"], let text = item["text"] {
                    map[id] = text
                }
            }
            return map
            
        } catch {
            print("AI Translation Prep Error: \(error)")
            return [:]
        }
    }
    
    // (removed duplicate injectTranslation)
}
