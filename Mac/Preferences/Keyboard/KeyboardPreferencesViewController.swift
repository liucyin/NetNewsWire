//
//  KeyboardPreferencesViewController.swift
//  NetNewsWire
//
//  Created by NetNewsWire Team
//  Copyright © 2025 Ranchero Software, LLC. All rights reserved.
//

import AppKit
import RSCore

final class KeyboardPreferencesViewController: NSViewController {

    private lazy var aiSummaryShortcutRecorder: KeyboardShortcutRecorderView = {
        let recorder = KeyboardShortcutRecorderView()
        recorder.shortcutDictionary = AppDefaults.shared.aiSummaryKeyboardShortcut
        recorder.validator = { [weak self] dictionary in
            guard let self else { return "Unable to validate shortcut." }
            return self.validateShortcutDictionary(
                dictionary,
                otherShortcutDictionaries: [
                    AppDefaults.shared.aiTranslateKeyboardShortcut,
                    AppDefaults.shared.searchKeyboardShortcut
                ]
            )
        }
        recorder.onChange = { dictionary in
            AppDefaults.shared.aiSummaryKeyboardShortcut = dictionary
            MainWindowKeyboardHandler.shared.reloadUserShortcuts()
        }
        return recorder
    }()

    private lazy var aiTranslateShortcutRecorder: KeyboardShortcutRecorderView = {
        let recorder = KeyboardShortcutRecorderView()
        recorder.shortcutDictionary = AppDefaults.shared.aiTranslateKeyboardShortcut
        recorder.validator = { [weak self] dictionary in
            guard let self else { return "Unable to validate shortcut." }
            return self.validateShortcutDictionary(
                dictionary,
                otherShortcutDictionaries: [
                    AppDefaults.shared.aiSummaryKeyboardShortcut,
                    AppDefaults.shared.searchKeyboardShortcut
                ]
            )
        }
        recorder.onChange = { dictionary in
            AppDefaults.shared.aiTranslateKeyboardShortcut = dictionary
            MainWindowKeyboardHandler.shared.reloadUserShortcuts()
        }
        return recorder
    }()

    private lazy var searchShortcutRecorder: KeyboardShortcutRecorderView = {
        let recorder = KeyboardShortcutRecorderView()
        recorder.shortcutDictionary = AppDefaults.shared.searchKeyboardShortcut
        recorder.validator = { [weak self] dictionary in
            guard let self else { return "Unable to validate shortcut." }
            return self.validateShortcutDictionary(
                dictionary,
                otherShortcutDictionaries: [
                    AppDefaults.shared.aiSummaryKeyboardShortcut,
                    AppDefaults.shared.aiTranslateKeyboardShortcut
                ]
            )
        }
        recorder.onChange = { dictionary in
            AppDefaults.shared.searchKeyboardShortcut = dictionary
            MainWindowKeyboardHandler.shared.reloadUserShortcuts()
        }
        return recorder
    }()
    
    
    private lazy var imageViewerFullWindowCheckbox: NSButton = {
        let btn = NSButton(checkboxWithTitle: "Image viewer uses full window", target: self, action: #selector(toggleImageViewerFullWindow(_:)))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.state = AppDefaults.shared.imageViewerFullWindow ? .on : .off
        return btn
    }()

    private lazy var defaultKeyboardShortcutKeys = Self.loadDefaultKeyboardShortcutKeys()

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 450)
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI(in: view)
    }

    private func setupUI(in view: NSView) {
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "AI Summary:"), aiSummaryShortcutRecorder],
            [NSTextField(labelWithString: "AI Translate:"), aiTranslateShortcutRecorder],
            [NSTextField(labelWithString: "Search:"), searchShortcutRecorder]
        ])
        grid.rowSpacing = 16
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        
        grid.rowSpacing = 16
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        
        let shortcutsLabel = NSTextField(labelWithString: "Custom Toolbar Shortcuts")
        shortcutsLabel.font = NSFont.boldSystemFont(ofSize: 14)

        let interfaceLabel = NSTextField(labelWithString: "Interface")
        interfaceLabel.font = NSFont.boldSystemFont(ofSize: 14)
        
        let stack = NSStackView(views: [
            interfaceLabel,
            imageViewerFullWindowCheckbox,
            NSBox(), // Separator
            shortcutsLabel, 
            grid
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(24, after: imageViewerFullWindowCheckbox)
        
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    @objc func toggleImageViewerFullWindow(_ sender: NSButton) {
        AppDefaults.shared.imageViewerFullWindow = (sender.state == .on)
    }
}

private extension KeyboardPreferencesViewController {

	static func loadDefaultKeyboardShortcutKeys() -> Set<KeyboardKey> {
		let resourceNames = [
			"GlobalKeyboardShortcuts",
			"TimelineKeyboardShortcuts",
			"SidebarKeyboardShortcuts",
			"DetailKeyboardShortcuts",
		]

		var keys = Set<KeyboardKey>()
		for resourceName in resourceNames {
			guard let path = Bundle.main.path(forResource: resourceName, ofType: "plist") else {
				continue
			}
			guard let rawShortcuts = NSArray(contentsOfFile: path) as? [[String: Any]] else {
				continue
			}
			for shortcutDictionary in rawShortcuts {
				guard let shortcut = KeyboardShortcut(dictionary: shortcutDictionary) else { continue }
				keys.insert(shortcut.key)
			}
		}

		return keys
	}

	func validateShortcutDictionary(_ dictionary: [String: Any], otherShortcutDictionaries: [[String: Any]?]) -> String? {
		guard let keyString = dictionary["key"] as? String else {
			return "Unsupported key."
		}

		let command = Self.boolValue(dictionary["commandModifier"])
		let option = Self.boolValue(dictionary["optionModifier"])
		let control = Self.boolValue(dictionary["controlModifier"])

		guard command || option || control else {
			return "Include Command, Option, or Control."
		}

		if keyString == "[space]" && (command || control) {
			return "Reserved by the system."
		}
		if keyString == "[tab]" && command {
			return "Reserved by the system."
		}

		guard let candidateKey = KeyboardKey(dictionary: dictionary) else {
			return "Unsupported key."
		}

		if defaultKeyboardShortcutKeys.contains(candidateKey) {
            // Allow overriding defaults? NNW usually allows it via GlobalKeyboardShortcuts?
            // "Conflicts with an existing shortcut" is safer.
			return "Conflicts with an existing shortcut."
		}

        for otherDict in otherShortcutDictionaries {
            if let otherDict, let otherKey = KeyboardKey(dictionary: otherDict), candidateKey == otherKey {
                 return "Already used by another shortcut."
            }
        }

		return nil
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
