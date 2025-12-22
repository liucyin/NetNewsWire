
import AppKit

import AppKit

class TimelineLayoutTunerWindowController: NSWindowController {
    
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 450, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Timeline Layout Tuner"
        window.center()
        self.init(window: window)
        self.contentViewController = TimelineLayoutTunerViewController()
    }
}

class TimelineLayoutTunerViewController: NSViewController {
    
    private let stackView = NSStackView()
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 600))
    }

	private var presets: [String: LayoutConfig] = [:]
	private var currentPresetName: String?
	
	private let presetsPopup = NSPopUpButton()
	private let addButton = NSButton(title: "New", target: nil, action: nil)
	private let saveButton = NSButton(title: "Save", target: nil, action: nil)
	private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		stackView.orientation = .vertical
		stackView.alignment = .leading
		stackView.spacing = 12
		stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
		stackView.translatesAutoresizingMaskIntoConstraints = false
		
		view.addSubview(stackView)
		
		NSLayoutConstraint.activate([
			stackView.topAnchor.constraint(equalTo: view.topAnchor),
			stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
		])
		
		setupPresetUI()
		loadPresets()
		
		// Add Sliders
		addSlider(key: "paddingTop", label: "Padding Top", min: 0, max: 30) { $0.paddingTop = $1 }
		addSlider(key: "paddingBottom", label: "Padding Bottom", min: 0, max: 30) { $0.paddingBottom = $1 }
		addSlider(key: "paddingLeft", label: "Padding Left", min: 0, max: 30) { $0.paddingLeft = $1 }
		addSlider(key: "paddingRight", label: "Padding Right", min: 0, max: 50) { $0.paddingRight = $1 }
		addSlider(key: "thumbnailWidth", label: "Thumbnail Width", min: 50, max: 200) { $0.thumbnailWidth = $1 }
		addSlider(key: "thumbnailHeight", label: "Thumbnail Height", min: 50, max: 150) { $0.thumbnailHeight = $1 }
		addSlider(key: "articleThumbnailMarginLeft", label: "Thumbnail Margin", min: 0, max: 50) { $0.articleThumbnailMarginLeft = $1 }
		addSlider(key: "titleBottomMargin", label: "Title Bottom Margin", min: 0, max: 20) { $0.titleBottomMargin = $1 }
		addSlider(key: "dateMarginLeft", label: "Date Margin Left", min: 0, max: 30) { $0.dateMarginLeft = $1 }
	}
	
	private func setupPresetUI() {
		let row = NSStackView()
		row.orientation = .horizontal
		row.spacing = 10
		
		presetsPopup.target = self
		presetsPopup.action = #selector(presetChanged(_:))
		
		addButton.target = self
		addButton.action = #selector(addPreset(_:))
		
		saveButton.target = self
		saveButton.action = #selector(saveCurrentPreset(_:))
		
		deleteButton.target = self
		deleteButton.action = #selector(deletePreset(_:))
		
		row.addArrangedSubview(NSTextField(labelWithString: "Preset:"))
		row.addArrangedSubview(presetsPopup)
		row.addArrangedSubview(addButton)
		row.addArrangedSubview(saveButton)
		row.addArrangedSubview(deleteButton)
		
		stackView.addArrangedSubview(row)
	}
	
	private func loadPresets() {
		if let data = UserDefaults.standard.data(forKey: "TimelineLayoutPresets"),
		   let saved = try? JSONDecoder().decode([String: LayoutConfig].self, from: data) {
			presets = saved
		}
		
		updatePresetsMenu()
	}
	
	private func updatePresetsMenu() {
		presetsPopup.removeAllItems()
		
		if presets.isEmpty {
			presetsPopup.addItem(withTitle: "Default")
			currentPresetName = "Default"
		} else {
			let sortedKeys = presets.keys.sorted()
			presetsPopup.addItems(withTitles: sortedKeys)
			
			// If we removed the last Item or the current one is gone
			if let current = currentPresetName, presets.keys.contains(current) {
				presetsPopup.selectItem(withTitle: current)
			} else if let first = sortedKeys.first {
				presetsPopup.selectItem(withTitle: first)
				currentPresetName = first
				// If we fell back to a default/first preset, make sure we load its config
				if let config = presets[first] {
					LayoutConfig.current = config
					refreshSliders()
				}
			}
		}
		
		updateButtonsState()
	}
	
	private func updateButtonsState() {
		// Disable delete if it's the only one or "Default" placeholder if logical
		// Disable save if we are on a "Default" pseudo-preset that we haven't created?
		// For simplicity, always enable. User can delete what they want.
	}
	
	@objc func presetChanged(_ sender: NSPopUpButton) {
		guard let name = sender.titleOfSelectedItem else { return }
		
		if let config = presets[name] {
			// update the model
			LayoutConfig.current = config
			currentPresetName = name
			
			// update the UI to match the model
			refreshSliders()
			
			// notify the timeline to redraw
			notifyChange()
		}
	}
	
	@objc func addPreset(_ sender: Any) {
		let alert = NSAlert()
		alert.messageText = "New Preset"
		alert.informativeText = "Enter a name for the new layout preset:"
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")
		
		let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
		alert.accessoryView = input
		alert.window.initialFirstResponder = input
		
		if alert.runModal() == .alertFirstButtonReturn {
			let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			if !name.isEmpty {
				presets[name] = LayoutConfig.current
				savePresetsToDisk()
				currentPresetName = name
				updatePresetsMenu()
			}
		}
	}
	
	@objc func saveCurrentPreset(_ sender: Any) {
		guard let name = currentPresetName else { return }
		
		// If current name is "Default" and it's not in the map (initial blank state), add it
		presets[name] = LayoutConfig.current
		savePresetsToDisk()
		
		// Visual feedback?
		let flash = CAAnimation()
		saveButton.layer?.add(flash, forKey: "flash")
	}
	
	@objc func deletePreset(_ sender: Any) {
		guard let name = currentPresetName, presets[name] != nil else { return }
		
		presets.removeValue(forKey: name)
		savePresetsToDisk()
		currentPresetName = nil // Will be reset by updatePresetsMenu
		updatePresetsMenu()
	}
	
	private func savePresetsToDisk() {
		if let data = try? JSONEncoder().encode(presets) {
			UserDefaults.standard.set(data, forKey: "TimelineLayoutPresets")
		}
	}

	private func addSlider(key: String, label: String, min: Double, max: Double, update: @escaping (inout LayoutConfig, CGFloat) -> Void) {
		let container = NSStackView()
		container.orientation = .horizontal
		container.spacing = 8
		container.translatesAutoresizingMaskIntoConstraints = false
		
		let labelField = NSTextField(labelWithString: label)
		labelField.translatesAutoresizingMaskIntoConstraints = false
		labelField.alignment = .right
		
		let value = getValue(for: key)
		
		let slider = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
		slider.translatesAutoresizingMaskIntoConstraints = false
		slider.identifier = NSUserInterfaceItemIdentifier(key)
		
		let valueLabel = NSTextField(labelWithString: String(format: "%.1f", value))
		valueLabel.translatesAutoresizingMaskIntoConstraints = false

		let sliderAction = TargetAction({ [weak self] val in
			update(&LayoutConfig.current, CGFloat(val))
			// We DO NOT switch to Custom anymore. We stay on the current preset (modified state).
			// User must hit 'Save' to persist.
			self?.notifyChange()
		}, updateLabel: { val in
			valueLabel.stringValue = String(format: "%.1f", val)
		})
		
		slider.target = sliderAction
		slider.action = #selector(TargetAction.performAction(_:))
		objc_setAssociatedObject(slider, "target", sliderAction, .OBJC_ASSOCIATION_RETAIN)

		container.addArrangedSubview(labelField)
		container.addArrangedSubview(slider)
		container.addArrangedSubview(valueLabel)
		stackView.addArrangedSubview(container)
		
		NSLayoutConstraint.activate([
			labelField.widthAnchor.constraint(equalToConstant: 120),
			slider.widthAnchor.constraint(equalToConstant: 200),
			valueLabel.widthAnchor.constraint(equalToConstant: 40),
			container.heightAnchor.constraint(equalToConstant: 24)
		])
	}
	
	private func getValue(for key: String) -> Double {
		switch key {
		case "paddingTop": return Double(LayoutConfig.current.paddingTop)
		case "paddingBottom": return Double(LayoutConfig.current.paddingBottom)
		case "paddingLeft": return Double(LayoutConfig.current.paddingLeft)
		case "paddingRight": return Double(LayoutConfig.current.paddingRight)
		case "thumbnailWidth": return Double(LayoutConfig.current.thumbnailWidth)
		case "thumbnailHeight": return Double(LayoutConfig.current.thumbnailHeight)
		case "articleThumbnailMarginLeft": return Double(LayoutConfig.current.articleThumbnailMarginLeft)
		case "titleBottomMargin": return Double(LayoutConfig.current.titleBottomMargin)
		case "dateMarginLeft": return Double(LayoutConfig.current.dateMarginLeft)
		default: return 0
		}
	}
	
	private func refreshSliders() {
		for view in stackView.arrangedSubviews {
			guard let container = view as? NSStackView else { continue }
			for subview in container.arrangedSubviews {
				if let slider = subview as? NSSlider, let key = slider.identifier?.rawValue {
					// Get the new value from the updated LayoutConfig.current
					let newValue = getValue(for: key)
					
					// Update the slider position
					slider.doubleValue = newValue
					
					// Update the text label
					// We need to find the label in the same container. It's the 3rd item usually [Label, Slider, ValueLabel]
					if let label = container.arrangedSubviews.last as? NSTextField {
						label.stringValue = String(format: "%.1f", newValue)
					}
				}
			}
		}
	}
	
	private func notifyChange() {
		NotificationCenter.default.post(name: .TimelineLayoutDidChange, object: nil)
	}
}

class TargetAction: NSObject {
	let action: (Double) -> Void
    let updateLabel: (Double) -> Void
    
	init(_ action: @escaping (Double) -> Void, updateLabel: @escaping (Double) -> Void) {
		self.action = action
        self.updateLabel = updateLabel
	}

	@objc func performAction(_ sender: NSSlider) {
		action(sender.doubleValue)
        updateLabel(sender.doubleValue)
	}
}

extension Notification.Name {
	static let TimelineLayoutDidChange = Notification.Name("TimelineLayoutDidChange")
}
