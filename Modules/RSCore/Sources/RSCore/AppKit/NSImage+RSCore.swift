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

	func imageByScalingToFill(targetSize: NSSize) -> NSImage {
		let widthRatio = targetSize.width / self.size.width
		let heightRatio = targetSize.height / self.size.height
		let scaleFactor = max(widthRatio, heightRatio)

		let newSize = NSSize(width: self.size.width * scaleFactor, height: self.size.height * scaleFactor)
		let image = NSImage(size: targetSize)

		image.lockFocus()
		let x = (targetSize.width - newSize.width) / 2
		let y = (targetSize.height - newSize.height) / 2
		self.draw(in: NSRect(x: x, y: y, width: newSize.width, height: newSize.height), from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
		image.unlockFocus()

		return image
	}
}
#endif
