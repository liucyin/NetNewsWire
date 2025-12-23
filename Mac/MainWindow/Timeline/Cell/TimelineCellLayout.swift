//
//  TimelineCellLayout.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import AppKit
import RSCore

@MainActor struct TimelineCellLayout {

	let width: CGFloat
	let height: CGFloat
	let feedNameRect: NSRect
	let dateRect: NSRect
	let titleRect: NSRect
	let numberOfLinesForTitle: Int
	let summaryRect: NSRect
	let textRect: NSRect
	let unreadIndicatorRect: NSRect
	let starRect: NSRect
	let iconImageRect: NSRect
	let articleThumbnailRect: NSRect
	let separatorRect: NSRect
	let paddingBottom: CGFloat

	init(width: CGFloat, height: CGFloat, feedNameRect: NSRect, dateRect: NSRect, titleRect: NSRect, numberOfLinesForTitle: Int, summaryRect: NSRect, textRect: NSRect, unreadIndicatorRect: NSRect, starRect: NSRect, iconImageRect: NSRect, articleThumbnailRect: NSRect, separatorRect: NSRect, paddingBottom: CGFloat) {

		self.width = width
		self.feedNameRect = feedNameRect
		self.dateRect = dateRect
		self.titleRect = titleRect
		self.numberOfLinesForTitle = numberOfLinesForTitle
		self.summaryRect = summaryRect
		self.textRect = textRect
		self.unreadIndicatorRect = unreadIndicatorRect
		self.starRect = starRect
		self.iconImageRect = iconImageRect
		self.articleThumbnailRect = articleThumbnailRect
		self.separatorRect = separatorRect
		self.paddingBottom = paddingBottom

		if height > 0.1 {
			self.height = height
		}
		else {
			self.height = [feedNameRect, dateRect, titleRect, summaryRect, textRect, unreadIndicatorRect, iconImageRect, articleThumbnailRect].maxY() + paddingBottom
		}
	}

	init(width: CGFloat, height: CGFloat, cellData: TimelineCellData, appearance: TimelineCellAppearance, hasIcon: Bool) {

		// If height == 0.0, then height is calculated.

		let showIcon = cellData.showIcon
		let showArticleThumbnail = AppDefaults.shared.timelineShowsArticleThumbnails && cellData.articleImageURL != nil
		
		// 1. Calculate Date Rect (Top Right) irrespective of thumbnail
		let dateRect = TimelineCellLayout.rectForDate(width, appearance, cellData)
		
		// 2. Calculate Thumbnail Rect (Below Date)
		let articleThumbnailRect = TimelineCellLayout.rectForArticleThumbnail(appearance, showArticleThumbnail, width, dateRect)

		// 3. Calculate Text Box Rect (Left of Thumbnail/Date)
		var textBoxRect = TimelineCellLayout.rectForTextBox(appearance, cellData, showIcon, showArticleThumbnail, width, dateRect, articleThumbnailRect)
		
		// 4. Feed Name (Top Left, aligned with Date vertically)
		let feedNameRect = TimelineCellLayout.rectForFeedName(textBoxRect, dateRect, appearance, cellData)
		
		let headerBottomY = max(dateRect.maxY, feedNameRect.maxY)

		let (titleRect, numberOfLinesForTitle) = TimelineCellLayout.rectForTitle(textBoxRect, headerBottomY, appearance, cellData)
		let summaryRect = numberOfLinesForTitle > 0 ? TimelineCellLayout.rectForSummary(textBoxRect, titleRect, numberOfLinesForTitle, appearance, cellData) : NSRect.zero
		let textRect = numberOfLinesForTitle > 0 ? NSRect.zero : TimelineCellLayout.rectForText(textBoxRect, headerBottomY, appearance, cellData)

		// Calculate total height based on all elements including thumbnail vertical extent
		textBoxRect.size.height = ceil([titleRect, summaryRect, textRect, dateRect, feedNameRect, articleThumbnailRect].maxY() - textBoxRect.origin.y)
		
		let iconImageRect = TimelineCellLayout.rectForIcon(cellData, appearance, showIcon, textBoxRect, width, height)
		let unreadIndicatorRect = TimelineCellLayout.rectForUnreadIndicator(appearance, textBoxRect)
		let starRect = TimelineCellLayout.rectForStar(appearance, unreadIndicatorRect)
		let separatorRect = TimelineCellLayout.rectForSeparator(cellData, appearance, showIcon ? iconImageRect : titleRect, width, height)

		let paddingBottom = appearance.cellPadding.bottom

		self.init(width: width, height: height, feedNameRect: feedNameRect, dateRect: dateRect, titleRect: titleRect, numberOfLinesForTitle: numberOfLinesForTitle, summaryRect: summaryRect, textRect: textRect, unreadIndicatorRect: unreadIndicatorRect, starRect: starRect, iconImageRect: iconImageRect, articleThumbnailRect: articleThumbnailRect, separatorRect: separatorRect, paddingBottom: paddingBottom)
	}

	static func height(for width: CGFloat, cellData: TimelineCellData, appearance: TimelineCellAppearance) -> CGFloat {

		let layout = TimelineCellLayout(width: width, height: 0.0, cellData: cellData, appearance: appearance, hasIcon: true)
		return layout.height
	}
}

// MARK: - Calculate Rects

@MainActor private extension TimelineCellLayout {

	static func rectForTextBox(_ appearance: TimelineCellAppearance, _ cellData: TimelineCellData, _ showIcon: Bool, _ showArticleThumbnail: Bool, _ width: CGFloat, _ dateRect: NSRect, _ thumbnailRect: NSRect) -> NSRect {

		// Returned height is a placeholder. Not needed when this is calculated.

		let iconSpace = showIcon ? appearance.iconSize.width + appearance.iconMarginRight : 0.0
		
		let rightObstructionMinX: CGFloat
		let rightMargin: CGFloat

		if showArticleThumbnail {
			// The right obstruction is the maximum of Date X or Thumbnail X (since both are right-aligned, we care about minX)
			// Usually Thumbnail is wider (minX is smaller).
			rightObstructionMinX = min(dateRect.minX, thumbnailRect.minX)
			rightMargin = appearance.articleThumbnailMarginLeft
		} else {
			// If no thumbnail, the title/summary/text are below the date, so they can extend to the full width
			rightObstructionMinX = width - appearance.cellPadding.right
			// No extra margin needed as we are using the cell padding right
			rightMargin = 0
		}
		
		let textBoxOriginX = appearance.cellPadding.left + appearance.unreadCircleDimension + appearance.unreadCircleMarginRight + iconSpace
		
		// Text box extends to the right obstruction minus margin
		let textBoxMaxX = floor(rightObstructionMinX - rightMargin)
		
		let textBoxWidth = floor(textBoxMaxX - textBoxOriginX)
		let textBoxRect = NSRect(x: textBoxOriginX, y: appearance.cellPadding.top, width: textBoxWidth, height: 1000000)

		return textBoxRect
	}

	static func rectForDate(_ width: CGFloat, _ appearance: TimelineCellAppearance, _ cellData: TimelineCellData) -> NSRect {
		let textFieldSize = SingleLineTextFieldSizer.size(for: cellData.dateString, font: appearance.dateFont)

		var r = NSZeroRect
		r.size = textFieldSize
		r.origin.y = appearance.cellPadding.top
		r.size.width = textFieldSize.width
		
		// Right-aligned to cell width
		r.origin.x = width - appearance.cellPadding.right - textFieldSize.width

		return r
	}

	static func rectForFeedName(_ textBoxRect: NSRect, _ dateRect: NSRect, _ appearance: TimelineCellAppearance, _ cellData: TimelineCellData) -> NSRect {
		if cellData.showFeedName == .none {
			return NSZeroRect
		}

		let textFieldSize = SingleLineTextFieldSizer.size(for: cellData.feedName, font: appearance.feedNameFont)
		var r = NSZeroRect
		r.size = textFieldSize
		r.origin.y = textBoxRect.origin.y // Align top with text box (and date)
		r.origin.x = textBoxRect.origin.x
		
		// Feed Name takes width up to the Date column
		let feedNameMaxX = dateRect.minX - appearance.dateMarginLeft
		let availableWidth = feedNameMaxX - r.origin.x
		
		// Ensure positive width, but don't force it to be smaller than textFieldSize if it fits?
		// No, feed name truncates. We define the rect size here.
		// Layout logic elsewhere (drawing) handles truncation if rect is small.
		// Note: textFieldSize is the *ideal* size. We should clamp it.
		
		r.size.width = min(textFieldSize.width, availableWidth)
		if r.size.width < 0 { r.size.width = 0 }

		return r
	}

	static func rectForTitle(_ textBoxRect: NSRect, _ startY: CGFloat, _ appearance: TimelineCellAppearance, _ cellData: TimelineCellData) -> (NSRect, Int) {

		var r = textBoxRect
		r.origin.y = startY + 2.0 // Add a little padding below date/feedname

		if cellData.title.isEmpty {
			r.size.height = 0
			return (r, 0)
		}

		let attributedTitle = cellData.attributedTitle.adding(font: appearance.titleFont)
		let sizeInfo = MultilineTextFieldSizer.size(for: attributedTitle, numberOfLines: appearance.titleNumberOfLines, width: Int(textBoxRect.width))
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return (r, sizeInfo.numberOfLinesUsed)
	}

	static func rectForSummary(_ textBoxRect: NSRect, _ titleRect: NSRect, _ titleNumberOfLines: Int,  _ appearance: TimelineCellAppearance, _ cellData: TimelineCellData) -> NSRect {
		if titleNumberOfLines >= appearance.titleNumberOfLines || cellData.text.isEmpty {
			return NSRect.zero
		}

		var r = textBoxRect
		r.origin.y = NSMaxY(titleRect)
		let summaryNumberOfLines = appearance.titleNumberOfLines - titleNumberOfLines

		let sizeInfo = MultilineTextFieldSizer.size(for: cellData.text, font: appearance.textOnlyFont, numberOfLines: summaryNumberOfLines, width: Int(textBoxRect.width))
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return r

	}

	static func rectForText(_ textBoxRect: NSRect, _ startY: CGFloat, _ appearance: TimelineCellAppearance, _ cellData: TimelineCellData) -> NSRect {
		var r = textBoxRect
		r.origin.y = startY + 2.0

		if cellData.text.isEmpty {
			r.size.height = 0
			return r
		}

		let sizeInfo = MultilineTextFieldSizer.size(for: cellData.text, font: appearance.textOnlyFont, numberOfLines: appearance.titleNumberOfLines, width: Int(textBoxRect.width))
		r.size.height = sizeInfo.size.height
		if sizeInfo.numberOfLinesUsed < 1 {
			r.size.height = 0
		}
		return r
	}

	static func rectForUnreadIndicator(_ appearance: TimelineCellAppearance, _ textBoxRect: NSRect) -> NSRect {

		var r = NSZeroRect
		r.size = NSSize(width: appearance.unreadCircleDimension, height: appearance.unreadCircleDimension)
		r.origin.x = appearance.cellPadding.left
		r.origin.y = textBoxRect.origin.y + 5 // Approximate centering on single line text
		return r
	}

	static func rectForStar(_ appearance: TimelineCellAppearance, _ unreadIndicatorRect: NSRect) -> NSRect {

		var r = NSRect.zero
		r.size.width = appearance.starDimension
		r.size.height = appearance.starDimension
		r.origin.x = floor(unreadIndicatorRect.origin.x - ((appearance.starDimension - appearance.unreadCircleDimension) / 2.0))
		r.origin.y = unreadIndicatorRect.origin.y - 4.0
		return r
	}

	static func rectForIcon(_ cellData: TimelineCellData, _ appearance: TimelineCellAppearance, _ showIcon: Bool, _ textBoxRect: NSRect, _ width: CGFloat, _ height: CGFloat) -> NSRect {

		var r = NSRect.zero
		if !showIcon {
			return r
		}
		r.size = appearance.iconSize
		r.origin.x = appearance.cellPadding.left + appearance.unreadCircleDimension + appearance.unreadCircleMarginRight
		r.origin.y = textBoxRect.origin.y + appearance.iconAdjustmentTop

		return r
	}

	static func rectForSeparator(_ cellData: TimelineCellData, _ appearance: TimelineCellAppearance, _ alignmentRect: NSRect, _ width: CGFloat, _ height: CGFloat) -> NSRect {
		return NSRect(x: alignmentRect.minX, y: height - 1, width: width - alignmentRect.minX, height: 1)
	}

	static func rectForArticleThumbnail(_ appearance: TimelineCellAppearance, _ showArticleThumbnail: Bool, _ width: CGFloat, _ dateRect: NSRect) -> NSRect {
		var r = NSRect.zero
		if !showArticleThumbnail {
			return r
		}
		r.size = appearance.articleThumbnailSize
		
		// Right-aligned to cell width
		r.origin.x = floor(width - appearance.cellPadding.right - appearance.articleThumbnailSize.width)
		
		// Position below the Date
		r.origin.y = dateRect.maxY + 2.0 
		return r
	}
}

private extension Array where Element == NSRect {

	func maxY() -> CGFloat {

		var y: CGFloat = 0.0
		self.forEach { y = Swift.max(y, $0.maxY) }
		return y
	}
}

