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
    private var localEventMonitor: Any?

	override func viewDidLoad() {
		currentWebViewController = regularWebViewController
		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.userDefaultsDidChange()
			}
		}
	        
	        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
	            Task { @MainActor in
	                guard let self = self else { return }
	                if !AISettings.shared.hoverTranslationEnabled { return }
                
                let modifier = AISettings.shared.hoverModifier
                let flags = event.modifierFlags
                
                var matches = false
                switch modifier {
                case .control: matches = flags.contains(.control)
                case .option: matches = flags.contains(.option)
                case .command: matches = flags.contains(.command)
                }
	                
	                if matches {
	                    guard let eventWindow = event.window,
	                          let webViewWindow = self.currentWebViewController.webView.window,
	                          eventWindow === webViewWindow else {
	                        return
	                    }
	                    self.currentWebViewController.triggerHoverAction(at: event.locationInWindow)
	                }
	            }
	            return event
	        }
	}
    
    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
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

    func performTitleTranslation() async {
         guard let webVC = currentWebViewController, let article = webVC.article else { return }
         let articleID = article.articleID
         let title = article.title ?? ""
         print("DEBUG: performTitleTranslation start for \(articleID.prefix(8))")
         guard !title.isEmpty else { return }
         
         let recognizer = NLLanguageRecognizer()
         recognizer.processString(title)
         
         if let dominant = recognizer.dominantLanguage {
             let targetLang = AISettings.shared.outputLanguage
             let targetIso = isoCode(for: targetLang)
             
             if !dominant.rawValue.lowercased().hasPrefix(targetIso) {
                 do {
                     print("DEBUG: Calling fetchOrTranslateTitle for \(articleID.prefix(8))")
                     // Use centralised fetch/task manager
                     let translated = try await AICacheManager.shared.fetchOrTranslateTitle(articleID: articleID, title: title, targetLang: targetLang)
                     print("DEBUG: fetchOrTranslateTitle returned for \(articleID.prefix(8))")
                     
                     // Verify context matches the original request
                     guard webVC.article?.articleID == articleID else {
                         print("DEBUG: Context mismatch for \(articleID.prefix(8)), aborting injection")
                         return 
                     }
                     
                     print("DEBUG: Injecting translated title for \(articleID.prefix(8))")
                     webVC.injectTitleTranslation(translated)
                 } catch {
                     print("Title Translation Error: \(error)")
                 }
             }
         }
    }

    func performTranslation() async {
        guard let webVC = currentWebViewController, let article = webVC.article else { return }
        
        // Translate Title if enabled (Parallel Task)
        if AISettings.shared.autoTranslateTitles {
             Task { await performTitleTranslation() }
        }
        
        let map = await webVC.prepareForTranslation()
        
        // Determine which items need translation (not in cache)
        let cached = AICacheManager.shared.getTranslation(for: article.articleID) ?? [:]
        let itemsToTranslate = map.filter { cached[$0.key] == nil }
        
        // Show Loading for all items to be translated
        for id in itemsToTranslate.keys {
             webVC.showTranslationLoading(for: id)
        }
        
        var translatedMap: [String: String] = [:]
        
        // Translate in parallel or batches
        await withTaskGroup(of: (String, String, Error?)?.self) { group in
            for (id, text) in itemsToTranslate {
                group.addTask {
                    do {
                        let target = await AISettings.shared.outputLanguage
                        let translation = try await AIService.shared.translate(text: text, targetLanguage: target)
                        return (id, translation, nil)
                    } catch {
                        print("Translation failed for \(id): \(error)")
                        return (id, "", error)
                    }
                }
            }
            
            for await result in group {
                if let (id, translation, error) = result {
                    await MainActor.run {
                        if let error = error {
                            webVC.showTranslationError(for: id, message: error.localizedDescription)
                        } else {
                            webVC.injectTranslation(id: id, text: translation)
                            translatedMap[id] = translation
                        }
                    }
                }
            }
        }
        
        // Save results to cache (merge with existing)
        if !translatedMap.isEmpty {
            var finalMap = cached
            finalMap.merge(translatedMap) { (_, new) in new }
            AICacheManager.shared.saveTranslation(finalMap, for: article.articleID)
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
            // Inject Hover Listener
            detailWebViewController.injectHoverListener(keyProperty: AISettings.shared.hoverModifier.jsProperty)

            // 1. Restore Summary Cache first (because it adds content to DOM)
            if let cachedSummary = AICacheManager.shared.getSummary(for: articleID) {
                detailWebViewController.injectAISummary(cachedSummary)
            }
            
            // 2. Force re-indexing of IDs. 
            // This ensures that if Summary was added, it gets IDs 0..N, and body gets N+1..M.
            // This order is deterministic based on DOM order.
            await detailWebViewController.ensureStableIDs(force: true)
            
            // 3. Restore Translation Cache
            let cachedTranslations = AICacheManager.shared.getTranslation(for: articleID)
            if let params = cachedTranslations, !params.isEmpty {
                for (id, text) in params {
                    detailWebViewController.injectTranslation(id: id, text: text)
                }
            }
            
            let cachedTitle = AICacheManager.shared.getTitleTranslation(for: articleID)
            if let titleText = cachedTitle {
                print("DEBUG: Restoring Title Cache for \(articleID.prefix(8))")
                detailWebViewController.injectTitleTranslation(titleText)
            } else {
                print("DEBUG: No Title Cache for \(articleID.prefix(8))")
            }
            
            // If fully cached, return
            if cachedTranslations != nil && (cachedTitle != nil || !AISettings.shared.autoTranslateTitles) {
                return
            }
            
            // Auto-translate logic (only if no cache)
            let autoTranslateBody = AISettings.shared.autoTranslate
            let autoTranslateTitles = AISettings.shared.autoTranslateTitles
            
            guard (autoTranslateBody || autoTranslateTitles),
                  detailWebViewController === currentWebViewController else { return }
            
            var didTriggerFullTranslation = false

            if autoTranslateBody && cachedTranslations == nil {
                // Use article content (summary or text) for language detection
                let textSample = article.contentText ?? article.summary ?? article.contentHTML ?? ""
                if !textSample.isEmpty {
                    // Simple heuristic: Take first 500 chars for detection
                    let sample = String(textSample.prefix(500))
                    let recognizer = NLLanguageRecognizer()
                    recognizer.processString(sample)
                    
                    if let dominantLang = recognizer.dominantLanguage {
                        let targetLang = AISettings.shared.outputLanguage
                        let targetIso = isoCode(for: targetLang)
                        let detectedIso = dominantLang.rawValue
                        
                        print("AI Auto-Translate: Detected \(detectedIso), Target \(targetIso) (\(targetLang))")
                        
                        // Check if detected starts with target (e.g. en-US starts with en)
                        if !detectedIso.lowercased().hasPrefix(targetIso.lowercased()) {
                            print("AI Auto-Translate: Triggering translation...")
                            await performTranslation()
                            didTriggerFullTranslation = true
                        }
                    }
                }
            }
            
            // If body translation was not triggered (either disabled or language matched),
            // check if we need to translate just the title.
            if !didTriggerFullTranslation && autoTranslateTitles && cachedTitle == nil {
                 await performTitleTranslation()
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

    func requestTranslation(id: String, text: String) {
        guard let webVC = currentWebViewController, let article = webVC.article else { return }
        let articleID = article.articleID
        
        Task { @MainActor in
            // Check cache
            var existingMap = AICacheManager.shared.getTranslation(for: articleID) ?? [:]
            
            if let cached = existingMap[id] {
                webVC.injectTranslation(id: id, text: cached)
                return
            }
            
            // Show Loading State immediately
            webVC.showTranslationLoading(for: id)
            
            // Translate
            do {
                print("DEBUG: Hover Translation requested for \(id)")
                let target = AISettings.shared.outputLanguage
                let translated = try await AIService.shared.translate(text: text, targetLanguage: target)
                
                // Inject
                webVC.injectTranslation(id: id, text: translated)
                
                // Save
                existingMap[id] = translated
                AICacheManager.shared.saveTranslation(existingMap, for: articleID)
            } catch {
                print("Hover Translation Failed: \(error)")
                webVC.showTranslationError(for: id, message: error.localizedDescription)
            }
        }
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
