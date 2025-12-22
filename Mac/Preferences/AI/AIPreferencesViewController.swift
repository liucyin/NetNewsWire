
import AppKit

final class AIPreferencesViewController: NSViewController {

    private let settings = AISettings.shared

    private lazy var tabView: NSTabView = {
        let tab = NSTabView()
        tab.translatesAutoresizingMaskIntoConstraints = false
        tab.addTabViewItem(NSTabViewItem(viewController: generalViewController))
        tab.addTabViewItem(NSTabViewItem(viewController: summaryViewController))
        tab.addTabViewItem(NSTabViewItem(viewController: translationViewController))
        
        tab.tabViewItem(at: 0).label = "General"
        tab.tabViewItem(at: 1).label = "Summary"
        tab.tabViewItem(at: 2).label = "Translation"
        return tab
    }()
    
    // MARK: - Sub View Controllers
    private lazy var generalViewController: NSViewController = {
        let vc = NSViewController()
        vc.view = generalView
        return vc
    }()
    
    private lazy var summaryViewController: NSViewController = {
        let vc = NSViewController()
        vc.view = summaryView
        return vc
    }()
    
    private lazy var translationViewController: NSViewController = {
        let vc = NSViewController()
        vc.view = translationView
        return vc
    }()
    
    // MARK: - General View Elements
    private lazy var generalView: NSView = {
        let view = NSView()
        setupGeneralUI(in: view)
        return view
    }()
    
    private lazy var summaryView: NSView = {
        let view = NSView()
        setupSummaryUI(in: view)
        return view
    }()
    
    private lazy var translationView: NSView = {
        let view = NSView()
        setupTranslationUI(in: view)
        return view
    }()

    // MARK: - General UI Components
    private lazy var enableCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Enable AI Features", target: self, action: #selector(toggleEnable(_:)))
        button.state = settings.isEnabled ? .on : .off
        return button
    }()

    private lazy var providerPopup: NSPopUpButton = {
        let popup = NSPopUpButton(title: "OpenAI", target: self, action: #selector(providerChanged(_:)))
        popup.addItems(withTitles: ["OpenAI"])
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
        let btn = NSButton(title: "Default", target: self, action: #selector(useDefaultURL(_:)))
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
    
    private lazy var testConnectionButton: NSButton = {
        let btn = NSButton(title: "Test Connection", target: self, action: #selector(testConnection(_:)))
        btn.bezelStyle = .rounded
        return btn
    }()
    
    private lazy var connectionStatusLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: 11)
        label.preferredMaxLayoutWidth = 350
        return label
    }()

    private lazy var rateLimitPopup: NSPopUpButton = {
        let popup = NSPopUpButton(title: "2/s", target: self, action: #selector(rateLimitChanged(_:)))
        let rates = ["0.5/s", "1/s", "2/s", "5/s", "Unlimited"]
        popup.addItems(withTitles: rates)
        popup.selectItem(withTitle: settings.rateLimit)
        return popup
    }()
    
    // MARK: - Summary UI Components
    private lazy var summaryPromptField: NSTextView = {
        let tv = NSTextView()
        tv.string = settings.summaryPrompt
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.delegate = self
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)
        return tv
    }()
    
    private lazy var resetSummaryButton: NSButton = {
        let btn = NSButton(title: "Reset to Default", target: self, action: #selector(resetSummaryPrompt(_:)))
        btn.bezelStyle = .rounded
        return btn
    }()
    
    // MARK: - Translation UI Components
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
    
    private lazy var translationPromptField: NSTextView = {
        let tv = NSTextView()
        tv.string = settings.translationPrompt
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.delegate = self
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)
        return tv
    }()
    
    private lazy var resetTranslationButton: NSButton = {
        let btn = NSButton(title: "Reset to Default", target: self, action: #selector(resetTranslationPrompt(_:)))
        btn.bezelStyle = .rounded
        return btn
    }()

    private lazy var autoTranslateCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Auto translate non-target language articles", target: self, action: #selector(toggleAutoTranslate(_:)))
        button.state = settings.autoTranslate ? .on : .off
        return button
    }()

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 450)
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    private func setupGeneralUI(in view: NSView) {
        let urlStack = NSStackView(views: [baseURLField, defaultURLButton])
        urlStack.spacing = 8
        
        let grid = NSGridView(views: [
            [enableCheckbox, NSGridCell.emptyContentView],
            [createSectionLabel("Provider Configuration"), NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Provider:"), providerPopup],
            [NSTextField(labelWithString: "Base URL:"), urlStack],
            [NSTextField(labelWithString: "Model:"), modelField],
            [NSTextField(labelWithString: "API Key:"), apiKeyField],
            [NSGridCell.emptyContentView, testConnectionButton],
            [NSGridCell.emptyContentView, connectionStatusLabel],
            [NSTextField(labelWithString: "Rate Limit:"), rateLimitPopup]
        ])

        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            baseURLField.widthAnchor.constraint(equalToConstant: 200),
            modelField.widthAnchor.constraint(equalToConstant: 280),
            apiKeyField.widthAnchor.constraint(equalToConstant: 280)
        ])
    }
    
    private lazy var summaryApiKeyField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.placeholderString = "Optional: Independent API Key"
        field.stringValue = settings.summaryApiKey
        field.target = self
        field.action = #selector(summaryApiKeyChanged(_:))
        return field
    }()

    private func setupSummaryUI(in view: NSView) {
        let label = NSTextField(labelWithString: "Summary System Prompt:")
        let scrollView = NSScrollView()
        scrollView.documentView = summaryPromptField
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        let apiKeyStack = NSStackView(views: [NSTextField(labelWithString: "API Key (Optional):"), summaryApiKeyField])
        apiKeyStack.spacing = 8
        apiKeyStack.orientation = .horizontal
        
        let headerStack = NSStackView(views: [label, resetSummaryButton])
        headerStack.distribution = .fillProportionally
        headerStack.spacing = 8
        
        let stack = NSStackView(views: [apiKeyStack, headerStack, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 8
        
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            summaryApiKeyField.widthAnchor.constraint(equalToConstant: 300),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            // ensure text view uses full width
            summaryPromptField.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }
    
    private lazy var translationApiKeyField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.placeholderString = "Optional: Independent API Key"
        field.stringValue = settings.translationApiKey
        field.target = self
        field.action = #selector(translationApiKeyChanged(_:))
        return field
    }()

    private func setupTranslationUI(in view: NSView) {
        let labelPrompt = NSTextField(labelWithString: "Translation System Prompt (%TARGET_LANGUAGE% will be replaced):")
        
        let scrollView = NSScrollView()
        scrollView.documentView = translationPromptField
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Target Language:"), outputLanguagePopup],
            [NSGridCell.emptyContentView, autoTranslateCheckbox],
            [NSTextField(labelWithString: "API Key (Optional):"), translationApiKeyField]
        ])
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        // grid.column(at: 2) does not exist (only 2 columns created from 2-element rows)

        let headerStack = NSStackView(views: [labelPrompt, resetTranslationButton])
        headerStack.spacing = 8

        let stack = NSStackView(views: [grid, headerStack, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            translationApiKeyField.widthAnchor.constraint(equalToConstant: 300),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            translationPromptField.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }
    
    // ...
    
    @objc private func resetSummaryPrompt(_ sender: NSButton) {
        settings.resetSummaryPrompt()
        summaryPromptField.string = settings.summaryPrompt
    }
    
    @objc private func resetTranslationPrompt(_ sender: NSButton) {
        settings.resetTranslationPrompt()
        translationPromptField.string = settings.translationPrompt
    }
    
    private func createSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: 13)
        return label
    }
    
    // MARK: - Actions
    @objc private func toggleEnable(_ sender: NSButton) { settings.isEnabled = (sender.state == .on) }
    @objc private func providerChanged(_ sender: NSPopUpButton) { settings.provider = sender.titleOfSelectedItem ?? "OpenAI" }
    @objc private func baseURLChanged(_ sender: NSTextField) { settings.baseURL = sender.stringValue }
    @objc private func useDefaultURL(_ sender: NSButton) {
        settings.baseURL = "https://api.openai.com/v1"
        baseURLField.stringValue = settings.baseURL
    }
    @objc private func modelChanged(_ sender: NSTextField) { settings.model = sender.stringValue }
    @objc private func apiKeyChanged(_ sender: NSTextField) { settings.apiKey = sender.stringValue }
    @objc private func languageChanged(_ sender: NSPopUpButton) { settings.outputLanguage = sender.titleOfSelectedItem ?? "English" }
    @objc private func toggleAutoTranslate(_ sender: NSButton) { settings.autoTranslate = (sender.state == .on) }
    @objc private func rateLimitChanged(_ sender: NSPopUpButton) { settings.rateLimit = sender.titleOfSelectedItem ?? "2/s" }
    
    @objc private func summaryApiKeyChanged(_ sender: NSTextField) { settings.summaryApiKey = sender.stringValue }
    @objc private func translationApiKeyChanged(_ sender: NSTextField) { settings.translationApiKey = sender.stringValue }
    
    @objc private func testConnection(_ sender: NSButton) {
        // Force update settings from UI to ensure we have the latest values
        settings.apiKey = apiKeyField.stringValue
        settings.baseURL = baseURLField.stringValue
        settings.model = modelField.stringValue
        
        connectionStatusLabel.stringValue = "Testing..."
        connectionStatusLabel.textColor = .secondaryLabelColor
        sender.isEnabled = false
        
        Task {
            do {
                _ = try await AIService.shared.testConnection()
                connectionStatusLabel.stringValue = "Success!"
                connectionStatusLabel.textColor = .systemGreen
            } catch {
                connectionStatusLabel.stringValue = "Failed: \(error.localizedDescription)"
                connectionStatusLabel.textColor = .systemRed
            }
            sender.isEnabled = true
        }
    }
}

extension AIPreferencesViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        if textView === summaryPromptField {
            settings.summaryPrompt = textView.string
        } else if textView === translationPromptField {
            settings.translationPrompt = textView.string
        }
    }
}
