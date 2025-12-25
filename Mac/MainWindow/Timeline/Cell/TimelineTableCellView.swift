//
//  TimelineTableCellView.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 8/31/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import AppKit
import ImageIO
import RSCore

final class TimelineTableCellView: NSTableCellView {

	private let titleView = TimelineTableCellView.multiLineTextField()
	private let summaryView = TimelineTableCellView.multiLineTextField()
	private let textView = TimelineTableCellView.multiLineTextField()
	private let unreadIndicatorView = UnreadIndicatorView(frame: NSZeroRect)
	private let dateView = TimelineTableCellView.singleLineTextField()
	private let feedNameView = TimelineTableCellView.singleLineTextField()

	private lazy var iconView = IconView()

	private var starView = TimelineTableCellView.imageView(with: Assets.Images.timelineStarUnselected, scaling: .scaleNone)

	private lazy var articleThumbnailView: NSImageView = {
		let imageView = NSImageView(frame: NSRect.zero)
		imageView.animates = false
		imageView.imageAlignment = .alignCenter
		imageView.imageScaling = .scaleProportionallyUpOrDown
		imageView.wantsLayer = true
		imageView.layer?.cornerRadius = 6.0
		imageView.layer?.masksToBounds = true
		return imageView
	}()

	private static let articleThumbnailCache: NSCache<NSString, NSImage> = {
		let cache = NSCache<NSString, NSImage>()
		cache.countLimit = 256
		return cache
	}()

	private var articleThumbnailTask: Task<Void, Never>?
	private var currentArticleThumbnailKey: NSString?

	private lazy var textFields = {
		return [self.dateView, self.feedNameView, self.titleView, self.summaryView, self.textView]
	}()

	var cellAppearance: TimelineCellAppearance! {
		didSet {
			if cellAppearance != oldValue {
				updateTextFieldFonts()
				iconView.layer?.cornerRadius = cellAppearance.iconCornerRadius
				needsLayout = true
			}
		}
	}

	var cellData: TimelineCellData! {
		didSet {
			updateSubviews()
		}
	}

	var isEmphasized: Bool = false {
		didSet {
			unreadIndicatorView.isEmphasized = isEmphasized
			updateStarView()
		}
	}

	var isSelected: Bool = false {
		didSet {
			unreadIndicatorView.isSelected = isSelected
			updateStarView()
		}
	}

	override var isFlipped: Bool {
		return true
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		commonInit()
	}

	required init?(coder: NSCoder) {		
		super.init(coder: coder)
		commonInit()
	}

	convenience init() {
		self.init(frame: NSRect.zero)
	}

	override func setFrameSize(_ newSize: NSSize) {

		if newSize == self.frame.size {
			return
		}

		super.setFrameSize(newSize)
		needsLayout = true
	}

	override func viewDidMoveToSuperview() {

		updateSubviews()
	}

	override func layout() {

		resizeSubviews(withOldSize: NSZeroSize)
	}

	override func resizeSubviews(withOldSize oldSize: NSSize) {

		let layoutRects = updatedLayoutRects()

		setFrame(for: titleView, rect: layoutRects.titleRect)
		setFrame(for: summaryView, rect: layoutRects.summaryRect)
		setFrame(for: textView, rect: layoutRects.textRect)

		dateView.setFrame(ifNotEqualTo: layoutRects.dateRect)
		unreadIndicatorView.setFrame(ifNotEqualTo: layoutRects.unreadIndicatorRect)
		feedNameView.setFrame(ifNotEqualTo: layoutRects.feedNameRect)
		iconView.setFrame(ifNotEqualTo: layoutRects.iconImageRect)
		starView.setFrame(ifNotEqualTo: layoutRects.starRect)
		articleThumbnailView.setFrame(ifNotEqualTo: layoutRects.articleThumbnailRect)
	}
}

// MARK: - Private

private extension TimelineTableCellView {

	static func singleLineTextField() -> NSTextField {

		let textField = NSTextField(labelWithString: "")
		textField.usesSingleLineMode = true
		textField.maximumNumberOfLines = 1
		textField.isEditable = false
		textField.lineBreakMode = .byTruncatingTail
		textField.allowsDefaultTighteningForTruncation = false
		return textField
	}

	static func multiLineTextField() -> NSTextField {

		let textField = NSTextField(wrappingLabelWithString: "")
		textField.usesSingleLineMode = false
		textField.maximumNumberOfLines = 0
		textField.isEditable = false
		textField.cell?.truncatesLastVisibleLine = true
		textField.allowsDefaultTighteningForTruncation = false
		return textField
	}

	static func imageView(with image: NSImage?, scaling: NSImageScaling) -> NSImageView {

		let imageView = image != nil ? NSImageView(image: image!) : NSImageView(frame: NSRect.zero)
		imageView.animates = false
		imageView.imageAlignment = .alignCenter
		imageView.imageScaling = scaling
		return imageView
	}

	func setFrame(for textField: NSTextField, rect: NSRect) {

		if Int(floor(rect.height)) == 0 || Int(floor(rect.width)) == 0 {
			hideView(textField)
		}
		else {
			showView(textField)
			textField.setFrame(ifNotEqualTo: rect)
		}
	}

	func makeTextFieldColorsNormal() {
		titleView.textColor = NSColor.labelColor
		feedNameView.textColor = NSColor.secondaryLabelColor
		dateView.textColor = NSColor.secondaryLabelColor
		summaryView.textColor = NSColor.secondaryLabelColor
		textView.textColor = NSColor.labelColor
	}

	func updateTextFieldFonts() {

		feedNameView.font = cellAppearance.feedNameFont
		dateView.font = cellAppearance.dateFont
		titleView.font = cellAppearance.titleFont
		summaryView.font = cellAppearance.textFont
		textView.font = cellAppearance.textOnlyFont
	}

	func addSubviewAtInit(_ view: NSView, hidden: Bool) {

		addSubview(view)
		view.translatesAutoresizingMaskIntoConstraints = false
		view.isHidden = hidden
	}

	func commonInit() {
		addSubviewAtInit(titleView, hidden: false)
		addSubviewAtInit(summaryView, hidden: true)
		addSubviewAtInit(textView, hidden: true)
		addSubviewAtInit(unreadIndicatorView, hidden: true)
		addSubviewAtInit(dateView, hidden: false)
		addSubviewAtInit(feedNameView, hidden: true)
		addSubviewAtInit(iconView, hidden: true)
		addSubviewAtInit(starView, hidden: true)
		addSubviewAtInit(articleThumbnailView, hidden: true)

		makeTextFieldColorsNormal()
	}

	func updatedLayoutRects() -> TimelineCellLayout {

		return TimelineCellLayout(width: bounds.width, height: bounds.height, cellData: cellData, appearance: cellAppearance, hasIcon: iconView.iconImage != nil)
	}

	func updateTitleView() {

		updateTextFieldText(titleView, cellData?.title)
		updateTextFieldAttributedText(titleView, cellData?.attributedTitle)
	}

	func updateSummaryView() {

		updateTextFieldText(summaryView, cellData?.text)
	}

	func updateTextView() {

		updateTextFieldText(textView, cellData?.text)
	}

	func updateDateView() {

		updateTextFieldText(dateView, cellData.dateString)
	}

	func updateTextFieldText(_ textField: NSTextField, _ text: String?) {
		let s = text ?? ""
		if textField.stringValue != s {
			textField.stringValue = s
			needsLayout = true
		}
	}

	func updateTextFieldAttributedText(_ textField: NSTextField, _ text: NSAttributedString?) {
		var s = text ?? NSAttributedString(string: "")

		if let fieldFont = textField.font {
			s = s.adding(font: fieldFont)
		}

		if textField.attributedStringValue != s {
			textField.attributedStringValue = s
			needsLayout = true
		}
	}

	func updateFeedNameView() {
		switch cellData.showFeedName {
		case .byline:
			showView(feedNameView)
			updateTextFieldText(feedNameView, cellData.byline)
		case .feed:
			showView(feedNameView)
			updateTextFieldText(feedNameView, cellData.feedName)
		case .none:
			hideView(feedNameView)
		}
	}

	func updateUnreadIndicator() {
		showOrHideView(unreadIndicatorView, cellData.read || cellData.starred)
	}

	func updateStarView() {
		if isSelected && isEmphasized {
			starView.image = Assets.Images.timelineStarSelected
		} else {
			starView.image = Assets.Images.timelineStarUnselected
		}
		showOrHideView(starView, !cellData.starred)
	}

	func updateIcon() {
		guard let iconImage = cellData.iconImage, cellData.showIcon else {
			makeIconEmpty()
			return
		}

		showView(iconView)
		if iconView.iconImage !== iconImage {
			iconView.iconImage = iconImage
			needsLayout = true
		}
	}

	func makeIconEmpty() {
		if iconView.iconImage != nil {
			iconView.iconImage = nil
			needsLayout = true
		}
		hideView(iconView)
	}

	func hideView(_ view: NSView) {
		if !view.isHidden {
			view.isHidden = true
		}
	}

	func showView(_ view: NSView) {
		if view.isHidden {
			view.isHidden = false
		}
	}

	func showOrHideView(_ view: NSView, _ shouldHide: Bool) {
		shouldHide ? hideView(view) : showView(view)
	}

	func updateArticleThumbnail() {
		guard AppDefaults.shared.timelineShowsArticleThumbnails,
			  let imageURL = cellData?.articleImageURL else {
			articleThumbnailTask?.cancel()
			articleThumbnailTask = nil
			currentArticleThumbnailKey = nil
			hideView(articleThumbnailView)
			articleThumbnailView.image = nil
			return
		}

		let targetSize = cellAppearance.articleThumbnailSize
		let screenScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
		let cacheKey = "\(imageURL)|\(Int(targetSize.width))x\(Int(targetSize.height))@\(Int(screenScale * 100))" as NSString

		if currentArticleThumbnailKey == cacheKey, articleThumbnailTask != nil {
			return
		}

		currentArticleThumbnailKey = cacheKey

		articleThumbnailTask?.cancel()
		articleThumbnailTask = nil

		if let cachedImage = Self.articleThumbnailCache.object(forKey: cacheKey) {
			showView(articleThumbnailView)
			articleThumbnailView.image = cachedImage
			needsLayout = true
			return
		}

		guard let imageData = ImageDownloader.shared.image(for: imageURL) else {
			hideView(articleThumbnailView)
			articleThumbnailView.image = nil
			return
		}

		hideView(articleThumbnailView)
		articleThumbnailView.image = nil

		articleThumbnailTask = Task(priority: .utility) { [weak self] in
			guard !Task.isCancelled else { return }
			guard let cgImage = Self.makeThumbnailCGImage(from: imageData, targetSize: targetSize, screenScale: screenScale) else {
				return
			}
			guard !Task.isCancelled else { return }

			let image = NSImage(cgImage: cgImage, size: targetSize)
			await MainActor.run {
				guard let self, self.currentArticleThumbnailKey == cacheKey else { return }
				Self.articleThumbnailCache.setObject(image, forKey: cacheKey)
				self.showView(self.articleThumbnailView)
				self.articleThumbnailView.image = image
				self.needsLayout = true
			}
		}
	}

	private static func makeThumbnailCGImage(from data: Data, targetSize: NSSize, screenScale: CGFloat) -> CGImage? {
		let targetPixelSize = CGSize(width: targetSize.width * screenScale, height: targetSize.height * screenScale)
		let width = Int(targetPixelSize.width.rounded(.up))
		let height = Int(targetPixelSize.height.rounded(.up))
		guard width > 0, height > 0 else {
			return nil
		}

		let maxPixelSize = max(width, height) * 2
		guard maxPixelSize > 0 else {
			return nil
		}

		guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
			return nil
		}

		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceShouldCacheImmediately: true,
			kCGImageSourceThumbnailMaxPixelSize: NSNumber(value: maxPixelSize)
		]

		guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
			return nil
		}

		guard let context = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			return nil
		}

		context.interpolationQuality = .high

		let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
		let scaleFactor = max(CGFloat(width) / imageSize.width, CGFloat(height) / imageSize.height)
		let drawSize = CGSize(width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
		let drawOrigin = CGPoint(x: (CGFloat(width) - drawSize.width) / 2, y: (CGFloat(height) - drawSize.height) / 2)
		context.draw(cgImage, in: CGRect(origin: drawOrigin, size: drawSize))

		return context.makeImage()
	}

	func updateSubviews() {
		updateTitleView()
		updateSummaryView()
		updateTextView()
		updateDateView()
		updateFeedNameView()
		updateUnreadIndicator()
		updateStarView()
		updateIcon()
		updateArticleThumbnail()
	}
}
