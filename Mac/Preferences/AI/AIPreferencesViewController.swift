
import AppKit

final class AIPreferencesViewController: NSViewController {

    private let settings = AISettings.shared

    private lazy var enableCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Enable AI Features", target: self, action: #selector(toggleEnable(_:)))
        button.state = settings.isEnabled ? .on : .off
        return button
    }()

    private lazy var providerPopup: NSPopUpButton = {
        let popup = NSPopUpButton(title: "OpenAI", target: self, action: #selector(providerChanged(_:)))
        popup.addItems(withTitles: ["OpenAI"]) // Can add more later
        popup.selectItem(withTitle: settings.provider)
        return popup
    }()

    private lazy var baseURLField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "https://api.openai.com/v1"
        field.stringValue = settings.baseURL
        field.target = self
        field.action = #selector(baseURLChanged(_:))
        return field
    }()
    
    private lazy var defaultURLButton: NSButton = {
        let btn = NSButton(title: "Use Default", target: self, action: #selector(useDefaultURL(_:)))
        btn.bezelStyle = .rounded
        return btn
    }()

    private lazy var modelField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "gpt-4o-mini"
        field.stringValue = settings.model
        field.target = self
        field.action = #selector(modelChanged(_:))
        return field
    }()

    private lazy var apiKeyField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.placeholderString = "sk-..."
        field.stringValue = settings.apiKey
        field.target = self
        field.action = #selector(apiKeyChanged(_:))
        return field
    }()

    private lazy var outputLanguagePopup: NSPopUpButton = {
        let popup = NSPopUpButton(title: "English", target: self, action: #selector(languageChanged(_:)))
        let start = ["English", "Chinese", "Japanese", "French", "German", "Spanish", "Korean", "Russian"]
        popup.addItems(withTitles: start)
        if start.contains(settings.outputLanguage) {
            popup.selectItem(withTitle: settings.outputLanguage)
        } else {
            popup.addItem(withTitle: settings.outputLanguage)
            popup.selectItem(withTitle: settings.outputLanguage)
        }
        return popup
    }()

    private lazy var autoTranslateCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Auto translate non-target language articles", target: self, action: #selector(toggleAutoTranslate(_:)))
        button.state = settings.autoTranslate ? .on : .off
        return button
    }()

    private lazy var rateLimitPopup: NSPopUpButton = {
        let popup = NSPopUpButton(title: "2/s", target: self, action: #selector(rateLimitChanged(_:)))
        let rates = ["0.5/s", "1/s", "2/s", "5/s", "Unlimited"]
        popup.addItems(withTitles: rates)
        popup.selectItem(withTitle: settings.rateLimit)
        return popup
    }()

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 400) // Default size
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        
        let urlStack = NSStackView(views: [baseURLField, defaultURLButton])
        urlStack.spacing = 8
        
        // Setup Grid
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "AI Configuration"), NSGridCell.emptyContentView],
            [enableCheckbox, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, NSTextField(wrappingLabelWithString: "Enable AI driven features like summary and translation.")],
            
            [createSectionLabel("AI Provider"), NSGridCell.emptyContentView], // Spacer/Header
            
            [NSTextField(labelWithString: "Provider:"), providerPopup],
            [NSTextField(labelWithString: "Base URL:"), urlStack],
            [NSTextField(labelWithString: "Model Name:"), modelField],
            [NSTextField(labelWithString: "API Key:"), apiKeyField],
            [NSTextField(labelWithString: "Output Language:"), outputLanguagePopup],
            [NSGridCell.emptyContentView, autoTranslateCheckbox],
            [NSTextField(labelWithString: "Rate Limit (QPS):"), rateLimitPopup]
        ])

        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        // Alignment
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        // Constraints
        NSLayoutConstraint.activate([
            baseURLField.widthAnchor.constraint(equalToConstant: 220),
            modelField.widthAnchor.constraint(equalToConstant: 300),
            apiKeyField.widthAnchor.constraint(equalToConstant: 300)
        ])

        view.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    private func createSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: 13)
        return label
    }
    
    // MARK: - Actions
    @objc private func toggleEnable(_ sender: NSButton) {
        settings.isEnabled = (sender.state == .on)
    }
    
    @objc private func providerChanged(_ sender: NSPopUpButton) {
        settings.provider = sender.titleOfSelectedItem ?? "OpenAI"
    }
    
    @objc private func baseURLChanged(_ sender: NSTextField) {
        settings.baseURL = sender.stringValue
    }
    
    @objc private func useDefaultURL(_ sender: NSButton) {
        settings.baseURL = "https://api.openai.com/v1"
        baseURLField.stringValue = settings.baseURL
    }
    
    @objc private func modelChanged(_ sender: NSTextField) {
        settings.model = sender.stringValue
    }
    
    @objc private func apiKeyChanged(_ sender: NSTextField) {
        settings.apiKey = sender.stringValue
    }
    
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        settings.outputLanguage = sender.titleOfSelectedItem ?? "English"
    }
    
    @objc private func toggleAutoTranslate(_ sender: NSButton) {
        settings.autoTranslate = (sender.state == .on)
    }
    
    @objc private func rateLimitChanged(_ sender: NSPopUpButton) {
        settings.rateLimit = sender.titleOfSelectedItem ?? "2/s"
    }
}
