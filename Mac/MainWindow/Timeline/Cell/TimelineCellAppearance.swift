//
//  TimelineCellAppearance.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import AppKit

struct LayoutConfig: Codable {
	var paddingTop: CGFloat = 7.0
	var paddingBottom: CGFloat = 30.0
	var paddingLeft: CGFloat = 16.0
	var paddingRight: CGFloat = 7.1
	
	var thumbnailWidth: CGFloat = 86.6
	var thumbnailHeight: CGFloat = 70.4
	
	var articleThumbnailMarginLeft: CGFloat = 12.2
	var titleBottomMargin: CGFloat = 4.0
	var dateMarginLeft: CGFloat = 8.0
	
	var cellPadding: NSEdgeInsets {
		get { NSEdgeInsets(top: paddingTop, left: paddingLeft, bottom: paddingBottom, right: paddingRight) }
		set {
			paddingTop = newValue.top
			paddingBottom = newValue.bottom
			paddingLeft = newValue.left
			paddingRight = newValue.right
		}
	}
	
	var articleThumbnailSize: NSSize {
		get { NSSize(width: thumbnailWidth, height: thumbnailHeight) }
		set {
			thumbnailWidth = newValue.width
			thumbnailHeight = newValue.height
		}
	}
	
	static var current = LayoutConfig()
}

struct TimelineCellAppearance: Equatable {

	let showIcon: Bool
	let cellPadding: NSEdgeInsets
	let feedNameFont: NSFont
	let dateFont: NSFont
	let dateMarginLeft: CGFloat
	let titleFont: NSFont
	let titleBottomMargin: CGFloat
	let titleNumberOfLines = 3
	let textFont: NSFont
	let textOnlyFont: NSFont
	let unreadCircleDimension: CGFloat = 8.0
	let unreadCircleMarginRight: CGFloat = 8.0
	let starDimension: CGFloat = 13.0
	let drawsGrid = false
	let iconSize = NSSize(width: 48, height: 48)
	let iconMarginLeft: CGFloat = 8.0
	let iconMarginRight: CGFloat = 8.0
	let iconAdjustmentTop: CGFloat = 4.0
	let iconCornerRadius: CGFloat = 4.0

	// Article thumbnail settings
	let articleThumbnailSize: NSSize
	let articleThumbnailMarginLeft: CGFloat
	let articleThumbnailCornerRadius: CGFloat = 6.0
	let boxLeftMargin: CGFloat

	init(showIcon: Bool, fontSize: FontSize) {

		let actualFontSize = AppDefaults.shared.actualFontSize(for: fontSize)
		let smallItemFontSize = floor(actualFontSize * 0.90)
		let largeItemFontSize = actualFontSize

		self.feedNameFont = NSFont.systemFont(ofSize: smallItemFontSize, weight: NSFont.Weight.bold)
		self.dateFont = NSFont.systemFont(ofSize: smallItemFontSize, weight: NSFont.Weight.bold)
		self.titleFont = NSFont.systemFont(ofSize: largeItemFontSize, weight: NSFont.Weight.semibold)
		self.textFont = NSFont.systemFont(ofSize: largeItemFontSize)
		self.textOnlyFont = NSFont.systemFont(ofSize: largeItemFontSize)

		self.showIcon = showIcon

		// Load from dynamic config
		self.cellPadding = LayoutConfig.current.cellPadding
		self.articleThumbnailSize = LayoutConfig.current.articleThumbnailSize
		self.articleThumbnailMarginLeft = LayoutConfig.current.articleThumbnailMarginLeft
		self.titleBottomMargin = LayoutConfig.current.titleBottomMargin
		self.dateMarginLeft = LayoutConfig.current.dateMarginLeft

		let margin = self.cellPadding.left + self.unreadCircleDimension + self.unreadCircleMarginRight
		self.boxLeftMargin = margin
	}
}

extension NSEdgeInsets: @retroactive Equatable {

	public static func ==(lhs: NSEdgeInsets, rhs: NSEdgeInsets) -> Bool {
		return lhs.left == rhs.left && lhs.top == rhs.top && lhs.right == rhs.right && lhs.bottom == rhs.bottom
	}
}
