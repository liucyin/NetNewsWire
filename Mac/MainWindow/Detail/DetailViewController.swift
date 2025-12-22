//
//  DetailViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/26/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import WebKit
import RSCore
import Articles
import RSWeb

enum DetailState: Equatable {
	case noSelection
	case multipleSelection
	case loading
	case article(Article, CGFloat?)
	case extracted(Article, ExtractedArticle, CGFloat?)
}

final class DetailViewController: NSViewController, WKUIDelegate {

	@IBOutlet var containerView: DetailContainerView!
	@IBOutlet var statusBarView: DetailStatusBarView!

	private lazy var regularWebViewController = createWebViewController()
	private var searchWebViewController: DetailWebViewController?

	var windowState: DetailWindowState {
		currentWebViewController.windowState
	}

	private var currentWebViewController: DetailWebViewController! {
		didSet {
			let webview = currentWebViewController.view
			if containerView.contentView === webview {
				return
			}
			statusBarView.mouseoverLink = nil
			containerView.contentView = webview
		}
	}

	private var currentSourceMode: TimelineSourceMode = .regular {
		didSet {
			currentWebViewController = webViewController(for: currentSourceMode)
		}
	}

	private var detailStateForRegular: DetailState = .noSelection {
		didSet {
			webViewController(for: .regular).state = detailStateForRegular
		}
	}

	private var detailStateForSearch: DetailState = .noSelection {
		didSet {
			webViewController(for: .search).state = detailStateForSearch
		}
	}

	private var isArticleContentJavascriptEnabled = AppDefaults.shared.isArticleContentJavascriptEnabled

	override func viewDidLoad() {
		currentWebViewController = regularWebViewController
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}
	}

	// MARK: - API

	func setState(_ state: DetailState, mode: TimelineSourceMode) {
		switch mode {
		case .regular:
			detailStateForRegular = state
		case .search:
			detailStateForSearch = state
		}
	}

	func showDetail(for mode: TimelineSourceMode) {
		currentSourceMode = mode
	}

	func stopMediaPlayback() {
		currentWebViewController.stopMediaPlayback()
	}

	func canScrollDown() async -> Bool {
		await currentWebViewController.canScrollDown()
	}

	func canScrollUp() async -> Bool {
		await currentWebViewController.canScrollUp()
	}

	override func scrollPageDown(_ sender: Any?) {
		currentWebViewController.scrollPageDown(sender)
	}

	override func scrollPageUp(_ sender: Any?) {
		currentWebViewController.scrollPageUp(sender)
	}

	// MARK: - Navigation

	func focus() {
		guard let window = currentWebViewController.webView.window else {
			return
		}
		window.makeFirstResponderUnlessDescendantIsFirstResponder(currentWebViewController.webView)
	}

    // MARK: - AI
    func injectAISummary(_ text: String) {
        currentWebViewController.injectAISummary(text)
    }
    
    func showAISummaryLoading() {
        currentWebViewController.showAISummaryLoading()
    }

    func performTranslation() async {
        guard let webVC = currentWebViewController, let article = webVC.article else { return }
        
        // If cache exists (and not cleared by caller), use it?
        // Caller (MainWindowController) clears it if it's a "Regenerate" action.
        // If this is called from Auto-translate, we should check cache first?
        // Auto-translate logic in DidFinishLoad checks cache. If missing, it calls this.
        // So here we assume we need to translate.
        
        let map = await webVC.prepareForTranslation()
        // let total = map.count
        
        var translatedMap: [String: String] = [:]
        
        // Translate in parallel or batches
        await withTaskGroup(of: (String, String)?.self) { group in
            for (id, text) in map {
                group.addTask {
                    do {
                        let target = AISettings.shared.outputLanguage
                        let translation = try await AIService.shared.translate(text: text, targetLanguage: target)
                        return (id, translation)
                    } catch {
                        print("Translation failed for \(id): \(error)")
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let (id, translation) = result {
                    await MainActor.run {
                        webVC.injectTranslation(id: id, text: translation)
                    }
                    translatedMap[id] = translation
                }
            }
        }
        
        // Save results to cache
        if !translatedMap.isEmpty {
            AICacheManager.shared.saveTranslation(translatedMap, for: article.articleID)
        }
    }
}

// MARK: - DetailWebViewControllerDelegate
import NaturalLanguage

extension DetailViewController: DetailWebViewControllerDelegate {
    
    func detailWebViewControllerDidFinishLoad(_ detailWebViewController: DetailWebViewController) {
        guard AISettings.shared.isEnabled, let article = detailWebViewController.article else { return }
        
        let articleID = article.articleID
        
        Task { @MainActor in
            // Ensure IDs are stable (deterministic) so cache matching works
            await detailWebViewController.ensureStableIDs()
            
            // 1. Restore Summary Cache
            if let cachedSummary = AICacheManager.shared.getSummary(for: articleID) {
                detailWebViewController.injectAISummary(cachedSummary)
            }
            
            // 2. Restore Translation Cache
            if let cachedTranslations = AICacheManager.shared.getTranslation(for: articleID), !cachedTranslations.isEmpty {
                for (id, text) in cachedTranslations {
                    detailWebViewController.injectTranslation(id: id, text: text)
                }
                // If we have translations, we stop here (don't auto-translate again)
                return
            }
            
            // Auto-translate logic (only if no cache)
            guard AISettings.shared.autoTranslate,
                  detailWebViewController === currentWebViewController else { return }
            
            // Use article content (summary or text) for language detection
            let textSample = article.contentText ?? article.summary ?? article.contentHTML ?? ""
            guard !textSample.isEmpty else { return }
            
            // Simple heuristic: Take first 500 chars for detection
            let sample = String(textSample.prefix(500))
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(sample)
            
            guard let dominantLang = recognizer.dominantLanguage else { return }
            
            let targetLang = AISettings.shared.outputLanguage
            let targetIso = isoCode(for: targetLang)
            
            // Note: dominantLang.rawValue returns "en", "zh-Hans", etc.
            let detectedIso = dominantLang.rawValue
            
            // Check if detected starts with target (e.g. en-US starts with en)
            if !detectedIso.lowercased().hasPrefix(targetIso.lowercased()) {
                await performTranslation()
            }
        }
    }
    
    private func isoCode(for languageName: String) -> String {
        switch languageName {
        case "English": return "en"
        case "Chinese": return "zh"
        case "Japanese": return "ja"
        case "French": return "fr"
        case "German": return "de"
        case "Spanish": return "es"
        case "Korean": return "ko"
        case "Russian": return "ru"
        default: return "en"
        }
    }

	func mouseDidEnter(_ detailWebViewController: DetailWebViewController, link: String) {
		guard !link.isEmpty, detailWebViewController === currentWebViewController else {
			return
		}
		statusBarView.mouseoverLink = link
	}

	func mouseDidExit(_ detailWebViewController: DetailWebViewController) {
		guard detailWebViewController === currentWebViewController else {
			return
		}
		statusBarView.mouseoverLink = nil
	}
}

// MARK: - Private

private extension DetailViewController {

	func createWebViewController() -> DetailWebViewController {
		let controller = DetailWebViewController()
		controller.delegate = self
		controller.state = .noSelection
		return controller
	}

	func webViewController(for mode: TimelineSourceMode) -> DetailWebViewController {
		switch mode {
		case .regular:
			return regularWebViewController
		case .search:
			if searchWebViewController == nil {
				searchWebViewController = createWebViewController()
			}
			return searchWebViewController!
		}
	}

	func userDefaultsDidChange() {
		if AppDefaults.shared.isArticleContentJavascriptEnabled != isArticleContentJavascriptEnabled {
			isArticleContentJavascriptEnabled = AppDefaults.shared.isArticleContentJavascriptEnabled
			createNewWebViewsAndRestoreState()
		}
	}

	func createNewWebViewsAndRestoreState() {

		regularWebViewController = createWebViewController()
		currentWebViewController = regularWebViewController
		regularWebViewController.state = detailStateForRegular

		searchWebViewController = nil

		if currentSourceMode == .search {
			searchWebViewController = createWebViewController()
			currentWebViewController = searchWebViewController
			searchWebViewController!.state = detailStateForSearch
		}
	}
}
