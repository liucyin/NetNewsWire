import AppKit
import RSCore

final class KeyboardShortcutRecorderView: NSView {

	var shortcutDictionary: [String: Any]? {
		didSet {
			updateShortcutLabel()
			restoreDefaultButton.isEnabled = shortcutDictionary != nil
		}
	}

	var validator: (([String: Any]) -> String?)?
	var onChange: (([String: Any]?) -> Void)?

	private let shortcutLabel = NSTextField(labelWithString: "")
	private let messageLabel = NSTextField(labelWithString: "")
	private lazy var recordButton = NSButton(title: "Record", target: self, action: #selector(toggleRecording))
	private lazy var restoreDefaultButton = NSButton(title: "Restore Default", target: self, action: #selector(restoreDefault))

	private var isRecording = false
	private var eventMonitor: Any?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setUp()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setUp()
	}

	deinit {
		stopRecording()
	}
}

private extension KeyboardShortcutRecorderView {

	func setUp() {
		translatesAutoresizingMaskIntoConstraints = false

		shortcutLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
		shortcutLabel.textColor = .labelColor

		messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		messageLabel.textColor = .secondaryLabelColor

		recordButton.bezelStyle = .rounded
		restoreDefaultButton.bezelStyle = .rounded

		let rowStack = NSStackView(views: [shortcutLabel, recordButton, restoreDefaultButton])
		rowStack.orientation = .horizontal
		rowStack.alignment = .centerY
		rowStack.spacing = 8

		let outerStack = NSStackView(views: [rowStack, messageLabel])
		outerStack.orientation = .vertical
		outerStack.alignment = .leading
		outerStack.spacing = 4
		outerStack.translatesAutoresizingMaskIntoConstraints = false

		addSubview(outerStack)
		NSLayoutConstraint.activate([
			outerStack.topAnchor.constraint(equalTo: topAnchor),
			outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
			outerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
			outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
			shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
		])

		updateShortcutLabel()
		restoreDefaultButton.isEnabled = shortcutDictionary != nil
	}

	@objc func toggleRecording() {
		if isRecording {
			stopRecording()
		} else {
			startRecording()
		}
	}

	func startRecording() {
		guard !isRecording else { return }

		isRecording = true
		recordButton.title = "Stop"
		messageLabel.stringValue = "Type a new shortcut…"
		shortcutLabel.stringValue = "Recording…"

		eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
			guard let self else { return event }
			return self.handleRecordingKeyDown(event)
		}
	}

	func stopRecording() {
		guard isRecording else { return }

		isRecording = false
		recordButton.title = "Record"
		messageLabel.stringValue = ""
		updateShortcutLabel()

		if let eventMonitor {
			NSEvent.removeMonitor(eventMonitor)
			self.eventMonitor = nil
		}
	}

	@objc func restoreDefault() {
		shortcutDictionary = nil
		onChange?(nil)
	}

	func handleRecordingKeyDown(_ event: NSEvent) -> NSEvent? {
		let key = KeyboardKey(with: event)

		if key.integerValue == 27 { // Escape
			stopRecording()
			return nil
		}

		guard let keyString = plistKeyString(for: key.integerValue) else {
			NSSound.beep()
			return nil
		}

		let shortcutDictionary: [String: Any] = [
			"key": keyString,
			"shiftModifier": key.shiftKeyDown,
			"optionModifier": key.optionKeyDown,
			"commandModifier": key.commandKeyDown,
			"controlModifier": key.controlKeyDown,
		]

		if key.integerValue == 127 { // Backspace/Delete clears
			restoreDefault()
			stopRecording()
			return nil
		}

		if let validator, let message = validator(shortcutDictionary) {
			messageLabel.stringValue = message
			NSSound.beep()
			return nil
		}

		self.shortcutDictionary = shortcutDictionary
		onChange?(shortcutDictionary)
		stopRecording()
		return nil
	}

	func updateShortcutLabel() {
		shortcutLabel.stringValue = shortcutDisplayString(for: shortcutDictionary) ?? "Not Set"
	}

	func shortcutDisplayString(for dictionary: [String: Any]?) -> String? {
		guard let dictionary else { return nil }
		guard let keyString = dictionary["key"] as? String else { return nil }

		var prefix = ""
		if boolValue(dictionary["controlModifier"]) { prefix += "⌃" }
		if boolValue(dictionary["optionModifier"]) { prefix += "⌥" }
		if boolValue(dictionary["shiftModifier"]) { prefix += "⇧" }
		if boolValue(dictionary["commandModifier"]) { prefix += "⌘" }

		return prefix + displayKeyString(for: keyString)
	}

	func displayKeyString(for plistKeyString: String) -> String {
		switch plistKeyString {
		case "[space]":
			return "Space"
		case "[uparrow]":
			return "↑"
		case "[downarrow]":
			return "↓"
		case "[leftarrow]":
			return "←"
		case "[rightarrow]":
			return "→"
		case "[return]":
			return "↩︎"
		case "[enter]":
			return "⌅"
		case "[delete]":
			return "⌫"
		case "[deletefunction]":
			return "⌦"
		case "[tab]":
			return "⇥"
		default:
			return plistKeyString.uppercased()
		}
	}

	func plistKeyString(for integerValue: Int) -> String? {
		switch integerValue {
		case 127:
			return "[delete]"
		case Int(NSDeleteFunctionKey):
			return "[deletefunction]"
		case Int(NSTabCharacter):
			return "[tab]"
		case Int(NSCarriageReturnCharacter):
			return "[return]"
		case Int(NSEnterCharacter):
			return "[enter]"
		case Int(NSUpArrowFunctionKey):
			return "[uparrow]"
		case Int(NSDownArrowFunctionKey):
			return "[downarrow]"
		case Int(NSLeftArrowFunctionKey):
			return "[leftarrow]"
		case Int(NSRightArrowFunctionKey):
			return "[rightarrow]"
		case 32:
			return "[space]"
		default:
			guard let scalar = UnicodeScalar(integerValue) else { return nil }
			return String(scalar)
		}
	}

	func boolValue(_ value: Any?) -> Bool {
		if let value = value as? Bool {
			return value
		}
		if let value = value as? NSNumber {
			return value.boolValue
		}
		return false
	}
}
