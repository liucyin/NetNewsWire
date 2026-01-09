//
//  MainFeedRowIdentifier.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 10/20/21.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Foundation

final class MainFeedRowIdentifier: NSObject, NSCopying {

	let indexPath: IndexPath

	init(indexPath: IndexPath) {
		self.indexPath = indexPath
	}

	func copy(with zone: NSZone? = nil) -> Any {
		self
	}

	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? MainFeedRowIdentifier else { return false }
		return indexPath == other.indexPath
	}

	override var hash: Int {
		indexPath.hashValue
	}
}
