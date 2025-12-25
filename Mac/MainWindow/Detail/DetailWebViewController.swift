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
    func requestTranslation(id: String, text: String)
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

    @MainActor func triggerHoverAction() {
        webView.evaluateJavaScript("if (window.triggerHoverAction) { window.triggerHoverAction(); }")
    }

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
	private var imageViewerOverlay: ImageViewerOverlayView?
	private var imageViewerKeyMonitor: Any?
	private var imageViewerTask: Task<Void, Never>?

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
        static let requestTranslation = "requestTranslation"
		static let openImageViewer = "openImageViewer"
	}

	override func loadView() {

		let configuration = WebViewConfiguration.configuration(with: detailIconSchemeHandler)

		configuration.userContentController.add(self, name: MessageName.windowDidScroll)
		configuration.userContentController.add(self, name: MessageName.mouseDidEnter)
		configuration.userContentController.add(self, name: MessageName.mouseDidExit)
        configuration.userContentController.add(self, name: MessageName.requestTranslation)
		configuration.userContentController.add(self, name: MessageName.openImageViewer)

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
        } else if message.name == MessageName.requestTranslation {
            if let body = message.body as? [String: String], let id = body["id"], let text = body["text"] {
                delegate?.requestTranslation(id: id, text: text)
            }
		} else if message.name == MessageName.openImageViewer {
			if let body = message.body as? [String: Any], let src = body["src"] as? String {
				openImageViewer(src: src)
			}
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
        delegate?.detailWebViewControllerDidFinishLoad(self)
        
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
		closeImageViewer(animated: false)
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

	func openImageViewer(src: String) {
		guard let url = URL(string: src), url.isHTTPOrHTTPSURL() else {
			return
		}

		let overlay = ensureImageViewerOverlay()
		overlay.showLoading()

		overlay.alphaValue = 0
		overlay.isHidden = false
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.15
			overlay.animator().alphaValue = 1
		}

		installImageViewerKeyMonitor()

		imageViewerTask?.cancel()
		imageViewerTask = Task { @MainActor in
			do {
				let (data, response) = try await Downloader.shared.download(url)
				guard let data, !data.isEmpty, let response, response.statusIsOK else {
					throw ImageViewerError.downloadFailed
				}

				let image = await Task.detached(priority: .userInitiated) {
					NSImage(data: data)
				}.value

				guard !Task.isCancelled, let image else {
					throw ImageViewerError.decodeFailed
				}

				overlay.showImage(image)
			} catch {
				guard !Task.isCancelled else { return }
				closeImageViewer(animated: true)
				openInBrowser(url, flags: [])
			}
		}
	}

	func closeImageViewer(animated: Bool) {
		imageViewerTask?.cancel()
		imageViewerTask = nil

		removeImageViewerKeyMonitor()

		guard let overlay = imageViewerOverlay, !overlay.isHidden else {
			return
		}

		let finish: @MainActor () -> Void = {
			overlay.reset()
			overlay.isHidden = true
			overlay.alphaValue = 1
		}

		if animated {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.15
				overlay.animator().alphaValue = 0
			} completionHandler: {
				Task { @MainActor in
					finish()
				}
			}
		} else {
			finish()
		}
	}

	private func ensureImageViewerOverlay() -> ImageViewerOverlayView {
		if let overlay = imageViewerOverlay {
			return overlay
		}

		let overlay = ImageViewerOverlayView()
		overlay.isHidden = true
		overlay.onClose = { [weak self] in
			self?.closeImageViewer(animated: true)
		}

		view.addSubview(overlay)
		overlay.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			overlay.topAnchor.constraint(equalTo: view.topAnchor),
			overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])

		imageViewerOverlay = overlay
		return overlay
	}

	private func installImageViewerKeyMonitor() {
		guard imageViewerKeyMonitor == nil else { return }
		imageViewerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self else { return event }
			if event.keyCode == 53 { // Esc
				self.closeImageViewer(animated: true)
				return nil
			}
			return event
		}
	}

	private func removeImageViewerKeyMonitor() {
		if let monitor = imageViewerKeyMonitor {
			NSEvent.removeMonitor(monitor)
			imageViewerKeyMonitor = nil
		}
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
                summaryDiv.style.padding = '20px 24px';
                summaryDiv.style.marginBottom = '20px';
                summaryDiv.style.borderBottom = '1px solid var(--separator-color)';
                summaryDiv.style.color = 'var(--secondary-label-color)';
                summaryDiv.style.fontFamily = 'system-ui, -apple-system, sans-serif';
                summaryDiv.style.boxSizing = 'border-box';
                
                // Loading Animation
                summaryDiv.innerHTML = `
                    <div style="display: flex; align-items: center; gap: 10px; opacity: 0.9;">
                        <span style="font-weight: 500; font-size: 13px; animation: pulse 1.5s infinite; color: var(--secondary-label-color);">Generating AI Summary...</span>
                    </div>
                    <style>
                        @keyframes pulse { 0% { opacity: 0.5; } 50% { opacity: 1; } 100% { opacity: 0.5; } }
                    </style>
                `;
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }

    func injectAISummary(_ text: String) {
        let html = markdownToHTML(text)
        
        // Safely encode HTML string for JS injection
        let jsonString = (try? String(data: JSONEncoder().encode(html), encoding: .utf8)) ?? "\"\""

        let js = """
        (function() {
            var summaryDiv = document.getElementById('aiSummary');
            if (summaryDiv) {
                // Minimalist Styling
                summaryDiv.style.padding = '20px 24px';
                summaryDiv.style.marginBottom = '24px';
                summaryDiv.style.borderBottom = '1px solid var(--separator-color)';
                summaryDiv.style.fontFamily = 'system-ui, -apple-system, sans-serif';
                summaryDiv.style.fontSize = '1em'; 
                summaryDiv.style.lineHeight = '1.6';
                summaryDiv.style.color = 'var(--body-text-color)';
                summaryDiv.style.boxSizing = 'border-box';
                
                var htmlContent = \(jsonString);
                
                var content = `
                <div class="ai-header" style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; cursor: pointer; user-select: none;" onclick="toggleAISummary(this)">
                    <div style="font-size: 0.85em; font-weight: 700; text-transform: uppercase; color: var(--secondary-label-color); letter-spacing: 0.05em;">AI Summary</div>
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--secondary-label-color); transition: transform 0.2s;">
                        <polyline points="6 9 12 15 18 9"></polyline>
                    </svg>
                </div>
                <div class="ai-content" style="display: block;">${htmlContent}</div>
                <style>
                    .ai-content h1, .ai-content h2, .ai-content h3 { margin-top: 1.2em; margin-bottom: 0.6em; color: var(--header-text-color); font-weight: 600; }
                    .ai-content h3 { font-size: 1.1em; }
                    .ai-content p { margin-bottom: 1em; }
                    .ai-content ul, .ai-content ol { margin-bottom: 1em; padding-left: 1.5em; }
                    .ai-content li { margin-bottom: 0.5em; }
                    .ai-content blockquote { border-left: 3px solid var(--accent-color); padding-left: 1em; color: var(--secondary-label-color); margin-left: 0; }
                </style>
                `;
                
                summaryDiv.innerHTML = content;
                summaryDiv.style.display = 'block';

                if (!window.toggleAISummary) {
                    window.toggleAISummary = function(header) {
                        var content = header.nextElementSibling;
                        var icon = header.querySelector('svg');
                        if (content.style.display === 'none') {
                            content.style.display = 'block';
                            icon.style.transform = 'rotate(0deg)';
                        } else {
                            content.style.display = 'none';
                            icon.style.transform = 'rotate(-90deg)';
                        }
                    };
                }
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }
    
    func injectTitleTranslation(_ text: String) {
        let html = markdownToHTML(text)
        
        // Safely encode for JS injection
        let jsonHtml = (try? String(data: JSONEncoder().encode(html), encoding: .utf8)) ?? "\"\""
        
        let js = """
        (function() {
            // Try to find the title element. NetNewsWire templates usually use .article-title class on h1
            var titleNode = document.querySelector('h1.article-title') || document.querySelector('h1');
            
            if (titleNode) {
                 var htmlContent = \(jsonHtml);
                 
                 // Check if existing translation
                 var existing = titleNode.querySelector('.ai-title-translation');
                 if (existing) {
                    existing.innerHTML = htmlContent;
                 } else {
                    var div = document.createElement('div');
                    div.className = 'ai-title-translation';
                    div.style.color = 'var(--secondary-label-color)';
                    div.style.fontStyle = 'italic';
                    div.style.fontSize = '0.8em';
                    div.style.marginTop = '4px';
                    div.style.marginBottom = '8px';
                    div.innerHTML = htmlContent;
                    titleNode.appendChild(div);
                 }
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }

	func injectTranslation(id: String, text: String) {
		let html = markdownToHTML(text)
        
		// Safely encode for JS injection
		let jsonHtml = (try? String(data: JSONEncoder().encode(html), encoding: .utf8)) ?? "\"\""
		let jsonId = (try? String(data: JSONEncoder().encode(id), encoding: .utf8)) ?? "\"\""
		
		let js = """
        (function() {
            var node = document.getElementById(\(jsonId));
            if (node) {
                var htmlContent = \(jsonHtml);
                
                // Check if already has translation
                var existing = node.nextElementSibling;
                if (existing && existing.className == 'ai-translation') {
                    existing.style.display = 'block';
                    existing.innerHTML = htmlContent;
                    existing.setAttribute('data-ai-translation-state', 'success');
                } else {
                    var div = document.createElement('div');
                    div.className = 'ai-translation';
                    div.setAttribute('data-ai-translation-state', 'success');
                    div.style.color = 'var(--secondary-label-color)'; // Adaptive color
                    div.style.fontStyle = 'italic';
                    div.style.marginTop = '6px';
                    div.style.marginBottom = '16px';
                    div.style.paddingLeft = '12px';
                    div.style.borderLeft = '3px solid var(--accent-color)';
                    div.style.lineHeight = '1.6';
                    div.innerHTML = htmlContent;
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

    // Ensure all target nodes have stable IDs for translation injection
    // force: if true, overwrites existing IDs (useful when DOM structure changes significantly, e.g. summary added at top)
    func ensureStableIDs(force: Bool = false) async {
        let js = """
        (function() {
            // Namespace 1: Summary Nodes
            var summaryContainer = document.getElementById('aiSummary');
            if (summaryContainer) {
                var sNodes = summaryContainer.querySelectorAll('p, li, blockquote, h1, h2, h3, h4, h5, h6');
                for (var i = 0; i < sNodes.length; i++) {
                    // Startswith check handles old 'ai-node' IDs by overwriting them if we want strict Namespaces
                    // But if force=true, we overwrite anyway.
                    // If force=false, we check if it HAS an ID. If it has 'ai-node-X' (old style), we might want to update it to new style?
                    // Let's assume force=true is used when refreshing structure.
                    
                    var shouldAssign = \(force) || !sNodes[i].id || !sNodes[i].id.startsWith('ai-summary-node-');
                    if (shouldAssign) {
                        sNodes[i].id = 'ai-summary-node-' + i;
                    }
                }
            }

            // Namespace 2: Body Nodes (Excluding Summary)
            var allNodes = document.querySelectorAll('p, li, blockquote, h1, h2, h3, h4, h5, h6');
            var bodyIndex = 0;
            
            for (var i = 0; i < allNodes.length; i++) {
                var node = allNodes[i];
                // Check if inside summary
                if (summaryContainer && summaryContainer.contains(node)) {
                    continue; 
                }
                
                var shouldAssign = \(force) || !node.id || !node.id.startsWith('ai-body-node-');
                if (shouldAssign) {
                    node.id = 'ai-body-node-' + bodyIndex;
                }
                bodyIndex++;
            }
        })();
        """
        try? await webView.evaluateJavaScript(js)
    }

    func injectHoverListener(keyProperty: String) {
        let js = """
        (function() {
            var lastHoveredNode = null;
            
            function triggerAction(node) {
                if (!node.id) {
                    node.id = 'ai-hover-' + Math.random().toString(36).substr(2, 9);
                }
                var next = node.nextElementSibling;
                if (next && next.classList.contains('ai-translation')) {
                    var state = (next.getAttribute('data-ai-translation-state') || '').toLowerCase();
                    if (state === 'loading') {
                        return;
                    }
                    if (state === 'error') {
                        var last = parseInt(node.getAttribute('data-ai-translation-last-request-at') || '0', 10);
                        var now = Date.now();
                        if (now - last < 500) {
                            return;
                        }
                        node.setAttribute('data-ai-translation-last-request-at', String(now));
                        var text = node.innerText.trim();
                        if (text.length > 0) {
                            window.webkit.messageHandlers.requestTranslation.postMessage({id: node.id, text: text});
                        }
                        return;
                    }

                    if (next.style.display === 'none') {
                        next.style.display = 'block';
                    } else {
                        next.style.display = 'none';
                    }
                } else {
                    var text = node.innerText.trim();
                    if (text.length > 0) {
                         var last = parseInt(node.getAttribute('data-ai-translation-last-request-at') || '0', 10);
                         var now = Date.now();
                         if (now - last < 500) {
                             return;
                         }
                         node.setAttribute('data-ai-translation-last-request-at', String(now));
                         window.webkit.messageHandlers.requestTranslation.postMessage({id: node.id, text: text});
                    }
                }
            }
            
            document.addEventListener('mouseover', function(e) {
                var target = e.target;
                while (target && target !== document.body) {
                    var tag = target.tagName.toLowerCase();
                    if (['p', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote'].includes(tag)) {
                        lastHoveredNode = target;
                        return;
                    }
                    target = target.parentElement;
                }
                lastHoveredNode = null;
            });

            document.addEventListener('mouseleave', function() {
                lastHoveredNode = null;
            });

            document.addEventListener('keydown', function(e) {
                if (e.\(keyProperty) && lastHoveredNode) {
                    triggerAction(lastHoveredNode);
                }
            });
            
            window.triggerHoverAction = function() {
                if (lastHoveredNode) {
                    triggerAction(lastHoveredNode);
                }
            };
        })();
        """
        webView.evaluateJavaScript(js)
    }
    func showTranslationLoading(for id: String) {
        let jsonId = (try? String(data: JSONEncoder().encode(id), encoding: .utf8)) ?? "\"\""
        let js = """
        (function() {
            var node = document.getElementById(\(jsonId));
            if (node) {
                var loadingHTML = `
                    <div style="display: flex; align-items: center; gap: 8px; opacity: 0.9;">
                        <span style="font-size: 13px; animation: pulse 1.5s infinite; color: var(--secondary-label-color);">Translating...</span>
                    </div>
                `;
                // Pulse styling is likely already injected by summary, but we can re-inject or assume it exists if summary is used. 
                // To be safe and self-contained:
                loadingHTML += `<style>@keyframes pulse { 0% { opacity: 0.5; } 50% { opacity: 1; } 100% { opacity: 0.5; } }</style>`;
                
                var existing = node.nextElementSibling;
                if (existing && existing.className == 'ai-translation') {
                    existing.style.display = 'block';
                    existing.innerHTML = loadingHTML;
                    existing.style.borderLeft = '3px solid var(--accent-color)';
                    existing.setAttribute('data-ai-translation-state', 'loading');
                } else {
                    var div = document.createElement('div');
                    div.className = 'ai-translation';
                    div.setAttribute('data-ai-translation-state', 'loading');
                    div.style.color = 'var(--secondary-label-color)';
                    div.style.marginTop = '6px';
                    div.style.marginBottom = '16px';
                    div.style.paddingLeft = '12px';
                    div.style.borderLeft = '3px solid var(--accent-color)';
                    div.innerHTML = loadingHTML;
                    node.parentNode.insertBefore(div, node.nextSibling);
                }
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }

    func showTranslationError(for id: String, message: String) {
        let jsonId = (try? String(data: JSONEncoder().encode(id), encoding: .utf8)) ?? "\"\""
        let jsonMsg = (try? String(data: JSONEncoder().encode(message), encoding: .utf8)) ?? "\"Error\""
        
        let js = """
        (function() {
            var node = document.getElementById(\(jsonId));
            if (node) {
                var errorHTML = `<div style="color: red; font-size: 0.9em;">⚠️ Translation Error: ` + \(jsonMsg) + `</div>`;
                
                var existing = node.nextElementSibling;
                if (existing && existing.className == 'ai-translation') {
                    existing.style.display = 'block';
                    existing.innerHTML = errorHTML;
                    existing.style.borderLeft = '3px solid red';
                    existing.setAttribute('data-ai-translation-state', 'error');
                } else {
                    var div = document.createElement('div');
                    div.className = 'ai-translation';
                    div.setAttribute('data-ai-translation-state', 'error');
                    div.style.marginTop = '6px';
                    div.style.marginBottom = '16px';
                    div.style.paddingLeft = '12px';
                    div.style.borderLeft = '3px solid red';
                    div.innerHTML = errorHTML;
                    node.parentNode.insertBefore(div, node.nextSibling);
                }
            }
        })();
        """
        webView.evaluateJavaScript(js)
    }

    func prepareForTranslation() async -> [String: String] {
        // Force re-indexing before translation to ensure current DOM order is captured accurately
        await ensureStableIDs(force: true)
        
        let js = """
        (function() {
            var nodes = document.querySelectorAll('p, li, blockquote, h1, h2, h3, h4, h5, h6');
            var result = [];
            
            // Regex for checking if text is just a URL
            var urlRegex = /^(https?:\\/\\/[^\\s]+)$/i;

            for (var i = 0; i < nodes.length; i++) {
                var node = nodes[i];
                var text = node.innerText.trim();
                
                // Skip if empty or too short
                if (text.length <= 5) continue;
                
                // Skip if it looks like a raw URL
                if (urlRegex.test(text)) continue;

                // We assume ensureStableIDs has run, so node.id is set.
                // We accept legacy 'ai-node-', or new 'ai-summary-node-' / 'ai-body-node-'
                if (node.id && (node.id.startsWith('ai-node-') || node.id.startsWith('ai-summary-node-') || node.id.startsWith('ai-body-node-'))) {
                    result.push({id: node.id, text: text});
                }
            }
            return result;
        })();
        """
        
        do {
            guard let result = try await webView.evaluateJavaScript(js) as? [[String: String]] else {
                return [:]
            } 
            
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

private enum ImageViewerError: Error {
	case downloadFailed
	case decodeFailed
}

@MainActor private final class ImageViewerOverlayView: NSView {
	var onClose: (() -> Void)?

	private let imageView = NSImageView()
	private let closeButton = NSButton()
	private let progressIndicator = NSProgressIndicator()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor

		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.imageAlignment = .alignCenter
		addSubview(imageView)

		progressIndicator.translatesAutoresizingMaskIntoConstraints = false
		progressIndicator.style = .spinning
		progressIndicator.isDisplayedWhenStopped = false
		addSubview(progressIndicator)

		closeButton.translatesAutoresizingMaskIntoConstraints = false
		closeButton.title = "×"
		closeButton.bezelStyle = .inline
		closeButton.font = NSFont.systemFont(ofSize: 20, weight: .regular)
		closeButton.target = self
		closeButton.action = #selector(closeButtonPressed(_:))
		addSubview(closeButton)

		NSLayoutConstraint.activate([
			closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
			closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

			imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
			imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
			imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
			imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
			imageView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
			imageView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),

			progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
			progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
		])

		reset()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func showLoading() {
		imageView.image = nil
		progressIndicator.startAnimation(nil)
	}

	func showImage(_ image: NSImage) {
		progressIndicator.stopAnimation(nil)
		imageView.image = image
	}

	func reset() {
		progressIndicator.stopAnimation(nil)
		imageView.image = nil
	}

	@objc private func closeButtonPressed(_ sender: Any?) {
		onClose?()
	}
}
