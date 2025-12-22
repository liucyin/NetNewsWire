//
//  NSImage+RSCore.swift
//  RSCore
//
//  Created by Brent Simmons on 12/16/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

#if os(macOS)
import AppKit

public extension NSImage {

	func tinted(with color: NSColor) -> NSImage {
		let image = self.copy() as! NSImage

		image.lockFocus()

		color.set()
		let rect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
		rect.fill(using: .sourceAtop)

		image.unlockFocus()

		image.isTemplate = false
		return image
	}

	func imageByCroppingToSquare() -> NSImage {
		let originalSize = self.size
		if originalSize.width == originalSize.height {
			return self
		}

		let size = min(originalSize.width, originalSize.height)
		let x = (originalSize.width - size) / 2
		let y = (originalSize.height - size) / 2
		let rect = NSRect(x: x, y: y, width: size, height: size)
		
		let newImage = NSImage(size: NSSize(width: size, height: size))
		newImage.lockFocus()
		self.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: rect, operation: .copy, fraction: 1.0)
		newImage.unlockFocus()
		
		return newImage
	}
}
#endif
