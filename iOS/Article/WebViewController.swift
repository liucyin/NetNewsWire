//
//  WebViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 12/28/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
@preconcurrency import WebKit
import RSCore
import RSWeb
import RSMarkdown
import Account
import Articles
import SafariServices
import MessageUI
import NaturalLanguage

@MainActor protocol WebViewControllerDelegate: AnyObject {
	func webViewController(_: WebViewController, articleExtractorButtonStateDidUpdate: ArticleExtractorButtonState)
}

final class WebViewController: UIViewController {

	private struct MessageName {
		static let imageWasClicked = "imageWasClicked"
		static let imageWasShown = "imageWasShown"
		static let showFeedInspector = "showFeedInspector"
	}

	private var topShowBarsView: UIView!
	private var bottomShowBarsView: UIView!
	private var topShowBarsViewConstraint: NSLayoutConstraint!
	private var bottomShowBarsViewConstraint: NSLayoutConstraint!

	private var webView: PreloadedWebView? {
		return view.subviews[0] as? PreloadedWebView
	}

	private lazy var contextMenuInteraction = UIContextMenuInteraction(delegate: self)
	private var isFullScreenAvailable: Bool {
		return AppDefaults.shared.articleFullscreenAvailable && traitCollection.userInterfaceIdiom == .phone && coordinator.isRootSplitCollapsed
	}
	private lazy var articleIconSchemeHandler = ArticleIconSchemeHandler(coordinator: coordinator);
	private lazy var transition = ImageTransition(controller: self)
	private var clickedImageCompletion: (() -> Void)?

	private var articleExtractor: ArticleExtractor? = nil
	var extractedArticle: ExtractedArticle? {
		didSet {
			windowScrollY = 0
		}
	}
	var isShowingExtractedArticle = false {
		didSet {
			if AppDefaults.shared.isShowingExtractedArticle != isShowingExtractedArticle {
				AppDefaults.shared.isShowingExtractedArticle = isShowingExtractedArticle
			}
		}
	}

	var articleExtractorButtonState: ArticleExtractorButtonState = .off {
		didSet {
			delegate?.webViewController(self, articleExtractorButtonStateDidUpdate: articleExtractorButtonState)
		}
	}

	weak var coordinator: SceneCoordinator!
	weak var delegate: WebViewControllerDelegate?

	private(set) var article: Article?

	let scrollPositionQueue = CoalescingQueue(name: "Article Scroll Position", interval: 0.3, maxInterval: 0.3)
	var windowScrollY = 0 {
		didSet {
			if windowScrollY != AppDefaults.shared.articleWindowScrollY {
				AppDefaults.shared.articleWindowScrollY = windowScrollY
			}
		}
	}
	private var restoreWindowScrollY: Int?

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .feedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(faviconDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(currentArticleThemeDidChangeNotification(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)

		// Configure the tap zones
		configureTopShowBarsView()
		configureBottomShowBarsView()

		loadWebView()
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

	@objc func currentArticleThemeDidChangeNotification(_ note: Notification) {
		loadWebView()
	}

	// MARK: Actions

	@objc func showBars(_ sender: Any) {
		showBars()
	}

	// MARK: API

	func setArticle(_ article: Article?, updateView: Bool = true) {
		stopArticleExtractor()

		if article != self.article {
			self.article = article
			if updateView {
				if article?.feed?.isArticleExtractorAlwaysOn ?? false {
					startArticleExtractor()
				}
				windowScrollY = 0
				loadWebView()
			}
		}
	}

	func setScrollPosition(isShowingExtractedArticle: Bool, articleWindowScrollY: Int) {
		if isShowingExtractedArticle {
			switch articleExtractor?.state {
			case .ready:
				restoreWindowScrollY = articleWindowScrollY
				startArticleExtractor()
			case .complete:
				windowScrollY = articleWindowScrollY
				loadWebView()
			case .processing:
				restoreWindowScrollY = articleWindowScrollY
			default:
				restoreWindowScrollY = articleWindowScrollY
				startArticleExtractor()
			}
		} else {
			windowScrollY = articleWindowScrollY
			loadWebView()
		}
	}

	func focus() {
		webView?.becomeFirstResponder()
	}

	func canScrollDown() -> Bool {
		guard let webView = webView else { return false }
		return webView.scrollView.contentOffset.y < finalScrollPosition(scrollingUp: false)
	}

	func canScrollUp() -> Bool {
		guard let webView = webView else { return false }
		return webView.scrollView.contentOffset.y > finalScrollPosition(scrollingUp: true)
	}

	private func scrollPage(up scrollingUp: Bool) {
		guard let webView, let windowScene = webView.window?.windowScene else {
			return
		}

		let overlap = 2 * UIFont.systemFont(ofSize: UIFont.systemFontSize).lineHeight * windowScene.screen.scale
		let scrollToY: CGFloat = {
			let scrollDistance = webView.scrollView.layoutMarginsGuide.layoutFrame.height - overlap;
			let fullScroll = webView.scrollView.contentOffset.y + (scrollingUp ? -scrollDistance : scrollDistance)
			let final = finalScrollPosition(scrollingUp: scrollingUp)
			return (scrollingUp ? fullScroll > final : fullScroll < final) ? fullScroll : final
		}()

		let convertedPoint = self.view.convert(CGPoint(x: 0, y: 0), to: webView.scrollView)
		let scrollToPoint = CGPoint(x: convertedPoint.x, y: scrollToY)
		webView.scrollView.setContentOffset(scrollToPoint, animated: true)
	}

	func scrollPageDown() {
		scrollPage(up: false)
	}

	func scrollPageUp() {
		scrollPage(up: true)
	}

	func hideClickedImage() {
		webView?.evaluateJavaScript("hideClickedImage();")
	}

	func showClickedImage(completion: @escaping () -> Void) {
		clickedImageCompletion = completion
		webView?.evaluateJavaScript("showClickedImage();")
	}

	func fullReload() {
		loadWebView(replaceExistingWebView: true)
	}

	func showBars() {
		AppDefaults.shared.articleFullscreenEnabled = false
		coordinator.showStatusBar()
		topShowBarsViewConstraint?.constant = 0
		bottomShowBarsViewConstraint?.constant = 0
		navigationController?.setNavigationBarHidden(false, animated: true)
		navigationController?.setToolbarHidden(false, animated: true)
		configureContextMenuInteraction()
	}

	func hideBars() {
		if isFullScreenAvailable {
			AppDefaults.shared.articleFullscreenEnabled = true
			coordinator.hideStatusBar()
			topShowBarsViewConstraint?.constant = -44.0
			bottomShowBarsViewConstraint?.constant = 44.0
			navigationController?.setNavigationBarHidden(true, animated: true)
			navigationController?.setToolbarHidden(true, animated: true)
			configureContextMenuInteraction()
		}
	}

	func toggleArticleExtractor() {

		guard let article = article else {
			return
		}

		guard articleExtractor?.state != .processing else {
			stopArticleExtractor()
			loadWebView()
			return
		}

		guard !isShowingExtractedArticle else {
			isShowingExtractedArticle = false
			loadWebView()
			articleExtractorButtonState = .off
			return
		}

		if let articleExtractor = articleExtractor {
			if article.preferredLink == articleExtractor.articleLink {
				isShowingExtractedArticle = true
				loadWebView()
				articleExtractorButtonState = .on
			}
		} else {
			startArticleExtractor()
		}

	}

	func stopArticleExtractorIfProcessing() {
		if articleExtractor?.state == .processing {
			stopArticleExtractor()
		}
	}

	func stopWebViewActivity() {
		if let webView = webView {
			stopMediaPlayback(webView)
			cancelImageLoad(webView)
		}
	}

	func showActivityDialog(popOverBarButtonItem: UIBarButtonItem? = nil) {
		guard let url = article?.preferredURL else { return }
		let activityViewController = UIActivityViewController(url: url, title: article?.title, applicationActivities: [FindInArticleActivity(), OpenInBrowserActivity()])
		activityViewController.popoverPresentationController?.barButtonItem = popOverBarButtonItem
		present(activityViewController, animated: true)
	}

	func openInAppBrowser() {
		guard let url = article?.preferredURL else { return }
		if AppDefaults.shared.useSystemBrowser {
			UIApplication.shared.open(url, options: [:])
		} else {
			openURLInSafariViewController(url)
		}
	}
}

// MARK: ArticleExtractorDelegate

extension WebViewController: ArticleExtractorDelegate {

	func articleExtractionDidFail(with: Error) {
		stopArticleExtractor()
		articleExtractorButtonState = .error
		loadWebView()
	}

	func articleExtractionDidComplete(extractedArticle: ExtractedArticle) {
		if articleExtractor?.state != .cancelled {
			self.extractedArticle = extractedArticle
			if let restoreWindowScrollY = restoreWindowScrollY {
				windowScrollY = restoreWindowScrollY
			}
			isShowingExtractedArticle = true
			loadWebView()
			articleExtractorButtonState = .on
		}
	}

}

// MARK: UIContextMenuInteractionDelegate

extension WebViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {

		return UIContextMenuConfiguration(identifier: nil, previewProvider: contextMenuPreviewProvider) { [weak self] suggestedActions in
			guard let self = self else { return nil }

			var menus = [UIMenu]()

			var navActions = [UIAction]()
			if let action = self.prevArticleAction() {
				navActions.append(action)
			}
			if let action = self.nextArticleAction() {
				navActions.append(action)
			}
			if !navActions.isEmpty {
				menus.append(UIMenu(title: "", options: .displayInline, children: navActions))
			}

			var toggleActions = [UIAction]()
			if let action = self.toggleReadAction() {
				toggleActions.append(action)
			}
			toggleActions.append(self.toggleStarredAction())
			menus.append(UIMenu(title: "", options: .displayInline, children: toggleActions))

			if let action = self.nextUnreadArticleAction() {
				menus.append(UIMenu(title: "", options: .displayInline, children: [action]))
			}

			menus.append(UIMenu(title: "", options: .displayInline, children: [self.toggleArticleExtractorAction()]))
			menus.append(UIMenu(title: "", options: .displayInline, children: [self.shareAction()]))

			return UIMenu(title: "", children: menus)
        }
    }

	func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
		coordinator.showBrowserForCurrentArticle()
	}

}

// MARK: WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		for (index, view) in view.subviews.enumerated() {
			if index != 0, let oldWebView = view as? PreloadedWebView {
				oldWebView.removeFromSuperview()
			}
		}

		Task { @MainActor [weak self] in
			guard let self else { return }
			await self.restoreAIStateIfNeeded(loadedWebView: webView)
		}
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {

		if navigationAction.navigationType == .linkActivated {
			guard let url = navigationAction.request.url else {
				decisionHandler(.allow)
				return
			}

			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			if components?.scheme == "http" || components?.scheme == "https" {
				decisionHandler(.cancel)
				if AppDefaults.shared.useSystemBrowser {
					UIApplication.shared.open(url, options: [:])
				} else {
					UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
						guard didOpen == false else {
							return
						}
						self.openURLInSafariViewController(url)
					}
				}

			} else if components?.scheme == "mailto" {
				decisionHandler(.cancel)

				guard let emailAddress = url.percentEncodedEmailAddress else {
					return
				}

				if UIApplication.shared.canOpenURL(emailAddress) {
					UIApplication.shared.open(emailAddress, options: [.universalLinksOnly : false], completionHandler: nil)
				} else {
					let alert = UIAlertController(title: NSLocalizedString("Error", comment: "Error"), message: NSLocalizedString("This device cannot send emails.", comment: "This device cannot send emails."), preferredStyle: .alert)
					alert.addAction(.init(title: NSLocalizedString("Dismiss", comment: "Dismiss"), style: .cancel, handler: nil))
					self.present(alert, animated: true, completion: nil)
				}
			} else if components?.scheme == "tel" {
				decisionHandler(.cancel)

				if UIApplication.shared.canOpenURL(url) {
					UIApplication.shared.open(url, options: [.universalLinksOnly : false], completionHandler: nil)
				}

			} else {
				decisionHandler(.allow)
			}
		} else {
			decisionHandler(.allow)
		}
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		fullReload()
	}

}

// MARK: WKUIDelegate

extension WebViewController: WKUIDelegate {

	func webView(_ webView: WKWebView, contextMenuForElement elementInfo: WKContextMenuElementInfo, willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating) {
		// We need to have at least an unimplemented WKUIDelegate assigned to the WKWebView.  This makes the
		// link preview launch Safari when the link preview is tapped.  In theory, you should be able to get
		// the link from the elementInfo above and transition to SFSafariViewController instead of launching
		// Safari.  As the time of this writing, the link in elementInfo is always nil.  ¯\_(ツ)_/¯
	}

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		guard let url = navigationAction.request.url else {
			return nil
		}

		openURL(url)
		return nil
	}

}

// MARK: WKScriptMessageHandler

extension WebViewController: WKScriptMessageHandler {

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		switch message.name {
		case MessageName.imageWasShown:
			clickedImageCompletion?()
		case MessageName.imageWasClicked:
			imageWasClicked(body: message.body as? String)
		case MessageName.showFeedInspector:
			if let feed = article?.feed {
				coordinator.showFeedInspector(for: feed)
			}
		default:
			return
		}
	}

}

// MARK: UIViewControllerTransitioningDelegate

extension WebViewController: UIViewControllerTransitioningDelegate {

	func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		transition.presenting = true
		return transition
	}

	func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		transition.presenting = false
		return transition
	}
}

// MARK:

extension WebViewController: UIScrollViewDelegate {

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		scrollPositionQueue.add(self, #selector(scrollPositionDidChange))
	}

	@objc func scrollPositionDidChange() {
		webView?.evaluateJavaScript("window.scrollY") { (scrollY, error) in
			guard error == nil else { return }
			let javascriptScrollY = scrollY as? Int ?? 0
			// I don't know why this value gets returned sometimes, but it is in error
			guard javascriptScrollY != 33554432 else { return }
			self.windowScrollY = javascriptScrollY
		}
	}

}



// MARK: JSON

private struct ImageClickMessage: Codable {
	let x: Float
	let y: Float
	let width: Float
	let height: Float
	let imageTitle: String?
	let imageURL: String
}

// MARK: Private

private extension WebViewController {

	func loadWebView(replaceExistingWebView: Bool = false) {
		guard isViewLoaded else { return }

		if !replaceExistingWebView, let webView = webView {
			self.renderPage(webView)
			return
		}

		coordinator.webViewProvider.dequeueWebView() { webView in

			webView.ready {

				// Add the webview
				webView.translatesAutoresizingMaskIntoConstraints = false
				self.view.insertSubview(webView, at: 0)
				NSLayoutConstraint.activate([
					self.view.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
					self.view.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
					self.view.topAnchor.constraint(equalTo: webView.topAnchor),
					self.view.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
				])

				// UISplitViewController reports the wrong size to WKWebView which can cause horizontal
				// rubberbanding on the iPad.  This interferes with our UIPageViewController preventing
				// us from easily swiping between WKWebViews.  This hack fixes that.
				webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 0)

				webView.scrollView.setZoomScale(1.0, animated: false)

				self.view.setNeedsLayout()
				self.view.layoutIfNeeded()

				// Configure the webview
				webView.navigationDelegate = self
				webView.uiDelegate = self
				webView.scrollView.delegate = self
				self.configureContextMenuInteraction()

				// Remove possible existing message handlers
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasClicked)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.imageWasShown)
				webView.configuration.userContentController.removeScriptMessageHandler(forName: MessageName.showFeedInspector)

				// Add handlers
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasClicked)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.imageWasShown)
				webView.configuration.userContentController.add(WrapperScriptMessageHandler(self), name: MessageName.showFeedInspector)

				self.renderPage(webView)
			}
		}
	}

	func renderPage(_ webView: PreloadedWebView?) {
		guard let webView = webView else { return }

		let theme = ArticleThemesManager.shared.currentTheme
		let rendering: ArticleRenderer.Rendering

		if let articleExtractor = articleExtractor, articleExtractor.state == .processing {
			rendering = ArticleRenderer.loadingHTML(theme: theme)
		} else if let articleExtractor = articleExtractor, articleExtractor.state == .failedToParse, let article = article {
			rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
		} else if let article = article, let extractedArticle = extractedArticle {
			if isShowingExtractedArticle {
				rendering = ArticleRenderer.articleHTML(article: article, extractedArticle: extractedArticle, theme: theme)
			} else {
				rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
			}
		} else if let article = article {
			rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
		} else {
			rendering = ArticleRenderer.noSelectionHTML(theme: theme)
		}

		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": rendering.html,
			"windowScrollY": String(windowScrollY)
		]

		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)
		webView.loadHTMLString(html, baseURL: ArticleRenderer.page.baseURL)
	}

	func finalScrollPosition(scrollingUp: Bool) -> CGFloat {
		guard let webView = webView else { return 0 }

		if scrollingUp {
			return -webView.scrollView.safeAreaInsets.top
		} else {
			return webView.scrollView.contentSize.height - webView.scrollView.bounds.height + webView.scrollView.safeAreaInsets.bottom
		}
	}

	func startArticleExtractor() {
		guard articleExtractor == nil else { return }
		if let link = article?.preferredLink, let extractor = ArticleExtractor(link, delegate: self) {
			extractor.process()
			articleExtractor = extractor
			articleExtractorButtonState = .animated
		}
	}

	func stopArticleExtractor() {
		articleExtractor?.cancel()
		articleExtractor = nil
		isShowingExtractedArticle = false
		articleExtractorButtonState = .off
	}

	func reloadArticleImage() {
		guard let article = article else { return }

		var components = URLComponents()
		components.scheme = ArticleRenderer.imageIconScheme
		components.path = article.articleID

		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
	}

	func imageWasClicked(body: String?) {
		guard let webView, let body else { return }

		let data = Data(body.utf8)
		guard let clickMessage = try? JSONDecoder().decode(ImageClickMessage.self, from: data) else {
			return
		}

		guard let imageURL = URL(string: clickMessage.imageURL) else { return }

		Downloader.shared.download(imageURL) { [weak self] data, response, error in
			guard let self, let data, error == nil, !data.isEmpty,
				  let image = UIImage(data: data) else {
				return
			}
			self.showFullScreenImage(image: image, clickMessage: clickMessage, webView: webView)
		}
	}

	private func showFullScreenImage(image: UIImage, clickMessage: ImageClickMessage, webView: WKWebView) {

		let y = CGFloat(clickMessage.y) + webView.safeAreaInsets.top
		let rect = CGRect(x: CGFloat(clickMessage.x), y: y, width: CGFloat(clickMessage.width), height: CGFloat(clickMessage.height))
		transition.originFrame = webView.convert(rect, to: nil)

		if navigationController?.navigationBar.isHidden ?? false {
			transition.maskFrame = webView.convert(webView.frame, to: nil)
		} else {
			transition.maskFrame = webView.convert(webView.safeAreaLayoutGuide.layoutFrame, to: nil)
		}

		transition.originImage = image

		coordinator.showFullScreenImage(image: image, imageTitle: clickMessage.imageTitle, transitioningDelegate: self)
	}

	func stopMediaPlayback(_ webView: WKWebView) {
		webView.evaluateJavaScript("stopMediaPlayback();")
	}

	func cancelImageLoad(_ webView: WKWebView) {
		webView.evaluateJavaScript("cancelImageLoad();")
	}

	func configureTopShowBarsView() {
		topShowBarsView = UIView()
		topShowBarsView.backgroundColor = .clear
		topShowBarsView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(topShowBarsView)

		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			topShowBarsViewConstraint = view.topAnchor.constraint(equalTo: topShowBarsView.bottomAnchor, constant: -44.0)
		} else {
			topShowBarsViewConstraint = view.topAnchor.constraint(equalTo: topShowBarsView.bottomAnchor, constant: 0.0)
		}

		NSLayoutConstraint.activate([
			topShowBarsViewConstraint,
			view.leadingAnchor.constraint(equalTo: topShowBarsView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: topShowBarsView.trailingAnchor),
			topShowBarsView.heightAnchor.constraint(equalToConstant: 44.0)
		])
		topShowBarsView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))
	}

	func configureBottomShowBarsView() {
		bottomShowBarsView = UIView()
		topShowBarsView.backgroundColor = .clear
		bottomShowBarsView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(bottomShowBarsView)
		if AppDefaults.shared.logicalArticleFullscreenEnabled {
			bottomShowBarsViewConstraint = view.bottomAnchor.constraint(equalTo: bottomShowBarsView.topAnchor, constant: 44.0)
		} else {
			bottomShowBarsViewConstraint = view.bottomAnchor.constraint(equalTo: bottomShowBarsView.topAnchor, constant: 0.0)
		}
		NSLayoutConstraint.activate([
			bottomShowBarsViewConstraint,
			view.leadingAnchor.constraint(equalTo: bottomShowBarsView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: bottomShowBarsView.trailingAnchor),
			bottomShowBarsView.heightAnchor.constraint(equalToConstant: 44.0)
		])
		bottomShowBarsView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showBars(_:))))
	}

	func configureContextMenuInteraction() {
		if isFullScreenAvailable {
			if navigationController?.isNavigationBarHidden ?? false {
				webView?.addInteraction(contextMenuInteraction)
			} else {
				webView?.removeInteraction(contextMenuInteraction)
			}
		}
	}

	func contextMenuPreviewProvider() -> UIViewController {
		let previewProvider = UIStoryboard.main.instantiateController(ofType: ContextMenuPreviewViewController.self)
		previewProvider.article = article
		return previewProvider
	}

	func prevArticleAction() -> UIAction? {
		guard coordinator.isPrevArticleAvailable else { return nil }
		let title = NSLocalizedString("Previous Article", comment: "Previous Article")
		return UIAction(title: title, image: Assets.Images.prevArticle) { [weak self] action in
			self?.coordinator.selectPrevArticle()
		}
	}

	func nextArticleAction() -> UIAction? {
		guard coordinator.isNextArticleAvailable else { return nil }
		let title = NSLocalizedString("Next Article", comment: "Next Article")
		return UIAction(title: title, image: Assets.Images.nextArticle) { [weak self] action in
			self?.coordinator.selectNextArticle()
		}
	}

	func toggleReadAction() -> UIAction? {
		guard let article = article, !article.status.read || article.isAvailableToMarkUnread else { return nil }

		let title = article.status.read ? NSLocalizedString("Mark as Unread", comment: "Mark as Unread") : NSLocalizedString("Mark as Read", comment: "Mark as Read")
		let readImage = article.status.read ? Assets.Images.circleClosed : Assets.Images.circleOpen
		return UIAction(title: title, image: readImage) { [weak self] action in
			self?.coordinator.toggleReadForCurrentArticle()
		}
	}

	func toggleStarredAction() -> UIAction {
		let starred = article?.status.starred ?? false
		let title = starred ? NSLocalizedString("Mark as Unstarred", comment: "Mark as Unstarred") : NSLocalizedString("Mark as Starred", comment: "Mark as Starred")
		let starredImage = starred ? Assets.Images.starOpen : Assets.Images.starClosed
		return UIAction(title: title, image: starredImage) { [weak self] action in
			self?.coordinator.toggleStarredForCurrentArticle()
		}
	}

	func nextUnreadArticleAction() -> UIAction? {
		guard coordinator.isAnyUnreadAvailable else { return nil }
		let title = NSLocalizedString("Next Unread Article", comment: "Next Unread Article")
		return UIAction(title: title, image: Assets.Images.nextUnread) { [weak self] action in
			self?.coordinator.selectNextUnread()
		}
	}

	func toggleArticleExtractorAction() -> UIAction {
		let extracted = articleExtractorButtonState == .on
		let title = extracted ? NSLocalizedString("Show Feed Article", comment: "Show Feed Article") : NSLocalizedString("Show Reader View", comment: "Show Reader View")
		let extractorImage = extracted ? Assets.Images.articleExtractorOffSF : Assets.Images.articleExtractorOnSF
		return UIAction(title: title, image: extractorImage) { [weak self] action in
			self?.toggleArticleExtractor()
		}
	}

	func shareAction() -> UIAction {
		let title = NSLocalizedString("Share", comment: "Share")
		return UIAction(title: title, image: Assets.Images.share) { [weak self] action in
			self?.showActivityDialog()
		}
	}

	// If the resource cannot be opened with an installed app, present the web view.
	func openURL(_ url: URL) {
		UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpen in
			assert(Thread.isMainThread)
			guard didOpen == false else {
				return
			}
			self.openURLInSafariViewController(url)
		}
	}

	func openURLInSafariViewController(_ url: URL) {
		guard let viewController = SFSafariViewController.safeSafariViewController(url) else {
			return
		}
		present(viewController, animated: true)
	}
}

// MARK: Find in Article

private struct FindInArticleOptions: Codable {
	var text: String
	var caseSensitive = false
	var regex = false
}

internal struct FindInArticleState: Codable {
	struct WebViewClientRect: Codable {
		let x: Double
		let y: Double
		let width: Double
		let height: Double
	}

	struct FindInArticleResult: Codable {
		let rects: [WebViewClientRect]
		let bounds: WebViewClientRect
		let index: UInt
		let matchGroups: [String]
	}

	let index: UInt?
	let results: [FindInArticleResult]
	let count: UInt
}

extension WebViewController {

	func searchText(_ searchText: String, completionHandler: @escaping (FindInArticleState) -> Void) {
		guard let json = try? JSONEncoder().encode(FindInArticleOptions(text: searchText)) else {
			return
		}
		let encoded = json.base64EncodedString()

		webView?.evaluateJavaScript("updateFind(\"\(encoded)\")") {
			(result, error) in
			guard error == nil,
				let b64 = result as? String,
				let rawData = Data(base64Encoded: b64),
				let findState = try? JSONDecoder().decode(FindInArticleState.self, from: rawData) else {
					return
			}

			completionHandler(findState)
		}
	}

	func endSearch() {
		webView?.evaluateJavaScript("endFind()")
	}

	func selectNextSearchResult() {
		webView?.evaluateJavaScript("selectNextResult()")
	}

	func selectPreviousSearchResult() {
		webView?.evaluateJavaScript("selectPreviousResult()")
	}

}

// MARK: - AI

extension WebViewController {

	@MainActor func showAISummaryLoading() {
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
		webView?.evaluateJavaScript(js)
	}

	@MainActor func injectAISummary(_ text: String) {
		let html = RSMarkdown.markdownToHTML(text)
		let jsonString = jsonEncodedString(html)

		let js = """
		(function() {
			var summaryDiv = document.getElementById('aiSummary');
			if (summaryDiv) {
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
		webView?.evaluateJavaScript(js)
	}

	@MainActor func injectTitleTranslation(_ text: String) {
		let html = RSMarkdown.markdownToHTML(text)
		let jsonHtml = jsonEncodedString(html)

		let js = """
		(function() {
			var titleNode = document.querySelector('h1.article-title') || document.querySelector('h1');
			if (titleNode) {
				var htmlContent = \(jsonHtml);

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
		webView?.evaluateJavaScript(js)
	}

	@MainActor func injectTranslation(id: String, text: String) {
		let html = RSMarkdown.markdownToHTML(text)
		let jsonHtml = jsonEncodedString(html)
		let jsonId = jsonEncodedString(id)

		let js = """
		(function() {
			var node = document.getElementById(\(jsonId));
			if (node) {
				var htmlContent = \(jsonHtml);

				var existing = node.nextElementSibling;
				if (existing && existing.className == 'ai-translation') {
					existing.style.display = 'block';
					existing.innerHTML = htmlContent;
					existing.setAttribute('data-ai-translation-state', 'success');
				} else {
					var div = document.createElement('div');
					div.className = 'ai-translation';
					div.setAttribute('data-ai-translation-state', 'success');
					div.style.color = 'var(--secondary-label-color)';
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
		webView?.evaluateJavaScript(js)
	}

	@MainActor func showTranslationLoading(for id: String) {
		let jsonId = jsonEncodedString(id)
		let js = """
		(function() {
			var node = document.getElementById(\(jsonId));
			if (node) {
				var loadingHTML = `
					<div style="display: flex; align-items: center; gap: 8px; opacity: 0.9;">
						<span style="font-size: 13px; animation: pulse 1.5s infinite; color: var(--secondary-label-color);">Translating...</span>
					</div>
				`;
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
		webView?.evaluateJavaScript(js)
	}

	@MainActor func showTranslationError(for id: String, message: String) {
		let jsonId = jsonEncodedString(id)
		let jsonMsg = jsonEncodedString(message)

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
		webView?.evaluateJavaScript(js)
	}

	@MainActor func ensureStableIDs(force: Bool = false) async {
		guard let webView else { return }

		let js = """
		(function() {
			var summaryContainer = document.getElementById('aiSummary');
			if (summaryContainer) {
				var sNodes = summaryContainer.querySelectorAll('p, li, blockquote, h1, h2, h3, h4, h5, h6');
				for (var i = 0; i < sNodes.length; i++) {
					var shouldAssign = \(force) || !sNodes[i].id || !sNodes[i].id.startsWith('ai-summary-node-');
					if (shouldAssign) {
						sNodes[i].id = 'ai-summary-node-' + i;
					}
				}
			}

			var allNodes = document.querySelectorAll('p, li, blockquote, h1, h2, h3, h4, h5, h6');
			var bodyIndex = 0;
			for (var i = 0; i < allNodes.length; i++) {
				var node = allNodes[i];
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

		_ = try? await webView.evaluateJavaScript(js)
	}

	@MainActor func prepareForTranslation() async -> [String: String] {
		await ensureStableIDs(force: true)
		guard let webView else { return [:] }

		let js = """
		(function() {
			var nodes = document.querySelectorAll('p, li, blockquote, h1, h2, h3, h4, h5, h6');
			var result = [];
			var urlRegex = /^(https?:\\/\\/[^\\s]+)$/i;

			for (var i = 0; i < nodes.length; i++) {
				var node = nodes[i];
				var text = node.innerText.trim();
				if (text.length <= 5) continue;
				if (urlRegex.test(text)) continue;

				if (node.id && (node.id.startsWith('ai-node-') || node.id.startsWith('ai-summary-node-') || node.id.startsWith('ai-body-node-'))) {
					result.push({id: node.id, text: text});
				}
			}
			return result;
		})();
		"""

		do {
			guard let result = try await webView.evaluateJavaScript(js) as? [[String: Any]] else {
				return [:]
			}

			var map = [String: String]()
			for item in result {
				if let id = item["id"] as? String, let text = item["text"] as? String {
					map[id] = text
				}
			}
			return map
		} catch {
			print("AI Translation Prep Error: \(error)")
			return [:]
		}
	}

	@MainActor func performTitleTranslation() async {
		guard AISettings.shared.isEnabled else { return }
		guard let article else { return }

		let articleID = article.articleID
		let title = article.title ?? ""
		guard !title.isEmpty else { return }

		let targetLang = AISettings.shared.outputLanguage
		var shouldTranslate = AISettings.shared.translationIsRewriteMode

		if !shouldTranslate {
			let recognizer = NLLanguageRecognizer()
			recognizer.processString(title)

			guard let dominant = recognizer.dominantLanguage else { return }

			let targetIso = isoCode(for: targetLang)
			shouldTranslate = !dominant.rawValue.lowercased().hasPrefix(targetIso.lowercased())
		}

		guard shouldTranslate else { return }

		do {
			let translated = try await AICacheManager.shared.fetchOrTranslateTitle(articleID: articleID, title: title, targetLang: targetLang)
			guard self.article?.articleID == articleID else { return }
			injectTitleTranslation(translated)
		} catch {
			print("Title Translation Error: \(error)")
		}
	}

	@MainActor func performTranslation() async {
		guard AISettings.shared.isEnabled else { return }
		guard let article else { return }
		let articleID = article.articleID

		if AISettings.shared.autoTranslateTitles {
			Task { await self.performTitleTranslation() }
		}

		let map = await prepareForTranslation()
		let cached = AICacheManager.shared.getTranslation(for: articleID) ?? [:]
		let itemsToTranslate = map.filter { cached[$0.key] == nil }

		for id in itemsToTranslate.keys {
			showTranslationLoading(for: id)
		}

		var translatedMap: [String: String] = [:]

		await withTaskGroup(of: (String, String, Error?)?.self) { group in
			for (id, text) in itemsToTranslate {
				group.addTask {
					do {
						let target = await AISettings.shared.outputLanguage
						let translation = try await AIService.shared.translate(text: text, targetLanguage: target)
						return (id, translation, nil)
					} catch {
						return (id, "", error)
					}
				}
			}

			for await result in group {
				guard let (id, translation, error) = result else { continue }
				guard self.article?.articleID == articleID else { continue }

				if let error {
					showTranslationError(for: id, message: error.localizedDescription)
				} else {
					injectTranslation(id: id, text: translation)
					translatedMap[id] = translation
				}
			}
		}

		if !translatedMap.isEmpty {
			var finalMap = cached
			finalMap.merge(translatedMap) { _, new in new }
			AICacheManager.shared.saveTranslation(finalMap, for: articleID)
		}
	}

	@MainActor fileprivate func restoreAIStateIfNeeded(loadedWebView: WKWebView) async {
		guard let current = webView, current === loadedWebView else { return }
		guard AISettings.shared.isEnabled, let article else { return }
		let articleID = article.articleID

		if let cachedSummary = AICacheManager.shared.getSummary(for: articleID) {
			injectAISummary(cachedSummary)
		}

		await ensureStableIDs(force: true)

		if let cachedTranslations = AICacheManager.shared.getTranslation(for: articleID), !cachedTranslations.isEmpty {
			for (id, text) in cachedTranslations {
				injectTranslation(id: id, text: text)
			}
		}

		let cachedTitle = AICacheManager.shared.getTitleTranslation(for: articleID)
		if let cachedTitle {
			injectTitleTranslation(cachedTitle)
		}

		if (AICacheManager.shared.getTranslation(for: articleID) != nil) && (cachedTitle != nil || !AISettings.shared.autoTranslateTitles) {
			return
		}

		let autoTranslateBody = AISettings.shared.autoTranslate
		let autoTranslateTitles = AISettings.shared.autoTranslateTitles
		guard autoTranslateBody || autoTranslateTitles else { return }

		var didTriggerFullTranslation = false

		if autoTranslateBody && AICacheManager.shared.getTranslation(for: articleID) == nil {
			if AISettings.shared.translationIsRewriteMode {
				await performTranslation()
				didTriggerFullTranslation = true
			} else {
				let textSample = article.contentText ?? article.summary ?? article.contentHTML ?? ""
				if !textSample.isEmpty {
					let sample = String(textSample.prefix(500))
					let recognizer = NLLanguageRecognizer()
					recognizer.processString(sample)

					if let dominantLang = recognizer.dominantLanguage {
						let targetLang = AISettings.shared.outputLanguage
						let targetIso = isoCode(for: targetLang)
						let detectedIso = dominantLang.rawValue

						if !detectedIso.lowercased().hasPrefix(targetIso.lowercased()) {
							await performTranslation()
							didTriggerFullTranslation = true
						}
					}
				}
			}
		}

		if !didTriggerFullTranslation && autoTranslateTitles && cachedTitle == nil {
			await performTitleTranslation()
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

	private func jsonEncodedString(_ value: String) -> String {
		(try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "\"\""
	}
}
