//
//  MainWindowKeyboardHandler.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 12/19/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import AppKit
import RSCore

@MainActor final class MainWindowKeyboardHandler: KeyboardDelegate {
	static let shared = MainWindowKeyboardHandler()
	private let defaultShortcuts: Set<KeyboardShortcut>
	private var aiOverrideShortcuts = Set<KeyboardShortcut>()
	private var userDefaultsObserver: NSObjectProtocol?

	init() {
		let f = Bundle.main.path(forResource: "GlobalKeyboardShortcuts", ofType: "plist")!
		let rawShortcuts = NSArray(contentsOfFile: f)! as! [[String: Any]]

		self.defaultShortcuts = Set(rawShortcuts.compactMap { KeyboardShortcut(dictionary: $0) })

		reloadUserShortcuts()

		self.userDefaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
			self?.reloadUserShortcuts()
		}
	}

	deinit {
		if let userDefaultsObserver {
			NotificationCenter.default.removeObserver(userDefaultsObserver)
		}
	}

	func reloadUserShortcuts() {
		aiOverrideShortcuts = Self.makeAIOverrideShortcuts()
	}

	func keydown(_ event: NSEvent, in view: NSView) -> Bool {
		let key = KeyboardKey(with: event)

		if let matchingShortcut = KeyboardShortcut.findMatchingShortcut(in: aiOverrideShortcuts, key: key) {
			matchingShortcut.perform(with: view)
			return true
		}

		guard let matchingShortcut = KeyboardShortcut.findMatchingShortcut(in: defaultShortcuts, key: key) else {
			return false
		}

		matchingShortcut.perform(with: view)
		return true
	}
}

private extension MainWindowKeyboardHandler {

	static func makeAIOverrideShortcuts() -> Set<KeyboardShortcut> {
		var shortcuts = Set<KeyboardShortcut>()
		var seenKeys = Set<KeyboardKey>()

		let candidates: [(actionString: String, keyDictionary: [String: Any]?)] = [
			("aiSummary:", AppDefaults.shared.aiSummaryKeyboardShortcut),
			("aiTranslate:", AppDefaults.shared.aiTranslateKeyboardShortcut),
		]

		for (actionString, keyDictionary) in candidates {
			guard let keyDictionary else {
				continue
			}
			guard isAllowedAIShortcutKeyDictionary(keyDictionary) else {
				continue
			}

			var shortcutDictionary = keyDictionary
			shortcutDictionary["action"] = actionString

			guard let shortcut = KeyboardShortcut(dictionary: shortcutDictionary) else {
				continue
			}
			guard seenKeys.insert(shortcut.key).inserted else {
				continue
			}

			shortcuts.insert(shortcut)
		}

		return shortcuts
	}

	static func isAllowedAIShortcutKeyDictionary(_ keyDictionary: [String: Any]) -> Bool {
		guard let keyString = keyDictionary["key"] as? String else {
			return false
		}

		let command = boolValue(keyDictionary["commandModifier"])
		let option = boolValue(keyDictionary["optionModifier"])
		let control = boolValue(keyDictionary["controlModifier"])

		guard command || option || control else {
			return false
		}

		// Avoid system-reserved shortcuts and input-source switching defaults.
		if keyString == "[space]" && (command || control) {
			return false
		}
		if keyString == "[tab]" && command {
			return false
		}

		return true
	}

	static func boolValue(_ value: Any?) -> Bool {
		if let value = value as? Bool {
			return value
		}
		if let value = value as? NSNumber {
			return value.boolValue
		}
		return false
	}
}
