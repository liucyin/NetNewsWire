import AppKit

final class AIPreferencesViewController: NSViewController {

    private let settings = AISettings.shared
    
    // MARK: - UI Configuration
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
    
    // MARK: - General Tab UI
    private lazy var generalView: NSView = {
        let view = NSView()
        setupGeneralUI(in: view)
        return view
    }()
    
    private lazy var enableCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Enable AI Features", target: self, action: #selector(toggleEnable(_:)))
        button.state = settings.isEnabled ? .on : .off
        return button
    }()
    
    // Profile Management
    private lazy var profilesTableView: NSTableView = {
        let table = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        col.title = "Providers"
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.headerView = nil 
        return table
    }()
    
    private lazy var addProfileButton: NSButton = {
        let btn = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Profile")!, target: self, action: #selector(addProfile))
        btn.bezelStyle = .smallSquare
        return btn
    }()
    
    private lazy var removeProfileButton: NSButton = {
        let btn = NSButton(image: NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove Profile")!, target: self, action: #selector(removeProfile))
        btn.bezelStyle = .smallSquare
        return btn
    }()
    
    // Profile Editing Form
    private lazy var profileNameField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "Name (e.g. OpenAI)"
        f.target = self; f.action = #selector(updateCurrentProfile)
        return f
    }()
    
    private lazy var baseURLField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "https://api.openai.com/v1"
        f.target = self; f.action = #selector(updateCurrentProfile)
        return f
    }()
    
    private lazy var modelField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = "gpt-4o-mini"
        f.target = self; f.action = #selector(updateCurrentProfile)
        return f
    }()
    
    private lazy var apiKeyField: NSSecureTextField = {
        let f = NSSecureTextField()
        f.placeholderString = "sk-..."
        f.target = self; f.action = #selector(updateCurrentProfile)
        return f
    }()
    
    private lazy var rateLimitPopup: NSPopUpButton = {
        let p = NSPopUpButton(title: "2/s", target: self, action: #selector(updateCurrentProfile))
        p.addItems(withTitles: ["0.5/s", "1/s", "2/s", "5/s", "Unlimited"])
        return p
    }()
    
    private lazy var testConnectionButton: NSButton = {
        NSButton(title: "Test Connection", target: self, action: #selector(testConnection))
    }()
    
    private lazy var connectionStatusLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.textColor = .secondaryLabelColor
        l.font = NSFont.systemFont(ofSize: 11)
        l.lineBreakMode = .byTruncatingTail
        return l
    }()
    
    private lazy var profileFormContainer: NSView = {
        let v = NSView()
        v.isHidden = true
        return v
    }()
    
    private lazy var noProfileLabel: NSTextField = {
        let l = NSTextField(labelWithString: "No Provider Selected")
        l.textColor = .secondaryLabelColor
        l.alignment = .center
        l.isHidden = true
        return l
    }()

    // MARK: - Summary Tab UI
    private lazy var summaryView: NSView = {
        let view = NSView()
        setupSummaryUI(in: view)
        return view
    }()
    
    private lazy var summaryProviderPopup: NSPopUpButton = {
        let p = NSPopUpButton(title: "", target: self, action: #selector(summaryProviderChanged(_:)))
        return p
    }()

    private lazy var summaryPromptField: NSTextView = {
        let tv = NSTextView()
        tv.string = settings.summaryPrompt
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.delegate = self
        tv.isEditable = true; tv.allowsUndo = true;
        tv.autoresizingMask = [.width]
        return tv
    }()

    // MARK: - Translation Tab UI
    private lazy var translationView: NSView = {
        let view = NSView()
        setupTranslationUI(in: view)
        return view
    }()
    
    private lazy var translationProviderPopup: NSPopUpButton = {
        let p = NSPopUpButton(title: "", target: self, action: #selector(translationProviderChanged(_:)))
        return p
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
    
    private lazy var translationPromptField: NSTextView = {
        let tv = NSTextView()
        tv.string = settings.translationPrompt
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.delegate = self
        tv.isEditable = true
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)
        return tv
    }()
    
    private lazy var autoTranslateCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Auto translate non-target language articles", target: self, action: #selector(toggleAutoTranslate(_:)))
        button.state = settings.autoTranslate ? .on : .off
        return button
    }()

    private lazy var autoTranslateTitlesCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Auto translate titles (if non-target language)", target: self, action: #selector(toggleAutoTranslateTitles(_:)))
        button.state = settings.autoTranslateTitles ? .on : .off
        return button
    }()

    // MARK: - Lifecycle
    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 450)
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
        
        reloadProfilePopups()
        
        // Select first profile if available
        if !settings.profiles.isEmpty {
            profilesTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            updateFormFromSelection()
        } else {
             profileFormContainer.isHidden = true
        }
    }
    
    // MARK: - Setup UI
    private func setupGeneralUI(in view: NSView) {
        // Left: Table list + Buttons
        let scroll = NSScrollView()
        scroll.documentView = profilesTableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        
        let buttonStack = NSStackView(views: [addProfileButton, removeProfileButton])
        buttonStack.spacing = 0
        buttonStack.orientation = .horizontal
        buttonStack.distribution = .fillEqually
        
        let leftCol = NSStackView(views: [scroll, buttonStack])
        leftCol.orientation = .vertical
        leftCol.spacing = 0
        
        // Right: Form
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name:"), profileNameField],
            [NSTextField(labelWithString: "Base URL:"), baseURLField],
            [NSTextField(labelWithString: "Model:"), modelField],
            [NSTextField(labelWithString: "API Key:"), apiKeyField],
            [NSTextField(labelWithString: "Rate Limit:"), rateLimitPopup]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        
        let formStack = NSStackView(views: [grid, NSBox(), testConnectionButton, connectionStatusLabel])
        formStack.orientation = .vertical
        formStack.alignment = .centerX
        formStack.spacing = 16
        
        profileFormContainer.addSubview(formStack)
        formStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            formStack.centerXAnchor.constraint(equalTo: profileFormContainer.centerXAnchor),
            formStack.centerYAnchor.constraint(equalTo: profileFormContainer.centerYAnchor),
            profileNameField.widthAnchor.constraint(equalToConstant: 200),
            baseURLField.widthAnchor.constraint(equalToConstant: 200),
            apiKeyField.widthAnchor.constraint(equalToConstant: 200)
        ])
        
        profileFormContainer.addSubview(noProfileLabel)
        noProfileLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            noProfileLabel.centerXAnchor.constraint(equalTo: profileFormContainer.centerXAnchor),
            noProfileLabel.centerYAnchor.constraint(equalTo: profileFormContainer.centerYAnchor)
        ])
        
        let mainSplit = NSStackView(views: [leftCol, profileFormContainer])
        mainSplit.spacing = 20
        mainSplit.distribution = .fillProportionally
        
        let topStack = NSStackView(views: [enableCheckbox])
        
        let container = NSStackView(views: [topStack, mainSplit])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 19),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            leftCol.widthAnchor.constraint(equalToConstant: 150),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }
    
    private func setupSummaryUI(in view: NSView) {
        let scroll = NSScrollView()
        scroll.documentView = summaryPromptField
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        
        let topGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Provider:"), summaryProviderPopup],
        ])
        topGrid.rowSpacing = 8
        topGrid.column(at: 0).xPlacement = .trailing
        
        let resetBtn = NSButton(title: "Reset Prompt", target: self, action: #selector(resetSummaryPrompt))
        let clearCacheBtn = NSButton(title: "Clear Cache", target: self, action: #selector(clearSummaryCache))
        
        let contentStack = NSStackView(views: [
            topGrid,
            NSTextField(labelWithString: "System Prompt:"),
            scroll,
            NSStackView(views: [resetBtn, clearCacheBtn])
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            summaryPromptField.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }
    
    private func setupTranslationUI(in view: NSView) {
        let scroll = NSScrollView()
        scroll.documentView = translationPromptField
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        
        let topGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Provider:"), translationProviderPopup],
            [NSTextField(labelWithString: "Target Language:"), outputLanguagePopup],
            [NSGridCell.emptyContentView, autoTranslateCheckbox],
            [NSGridCell.emptyContentView, autoTranslateTitlesCheckbox]
        ])
        topGrid.rowSpacing = 8
        topGrid.column(at: 0).xPlacement = .trailing
        
        let resetBtn = NSButton(title: "Reset Prompt", target: self, action: #selector(resetTranslationPrompt))
        let clearCacheBtn = NSButton(title: "Clear Cache", target: self, action: #selector(clearTranslationCache))
        
        let contentStack = NSStackView(views: [
            topGrid,
            NSTextField(labelWithString: "System Prompt (%TARGET_LANGUAGE% will be replaced):"),
            scroll,
            NSStackView(views: [resetBtn, clearCacheBtn])
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            translationPromptField.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }
    
    // MARK: - Logic
    
    @objc private func addProfile() {
        let newProfile = AIProviderProfile(name: "New Provider", baseURL: "https://api.openai.com/v1", apiKey: "", model: "gpt-4o-mini", rateLimit: "2/s")
        settings.addProfile(newProfile)
        profilesTableView.reloadData()
        
        let index = settings.profiles.count - 1
        profilesTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        updateFormFromSelection()
        reloadProfilePopups()
    }
    
    @objc private func removeProfile() {
        let row = profilesTableView.selectedRow
        guard row >= 0 && row < settings.profiles.count else { return }
        
        settings.deleteProfile(at: row)
        profilesTableView.reloadData()
        
        if settings.profiles.isEmpty {
           profileFormContainer.isHidden = true
           noProfileLabel.isHidden = false
        } else {
            let nextRow = min(row, settings.profiles.count - 1)
            profilesTableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
            updateFormFromSelection()
        }
        reloadProfilePopups()
    }
    
    @objc private func updateCurrentProfile() {
        let row = profilesTableView.selectedRow
        guard row >= 0 && row < settings.profiles.count else { return }
        
        var profile = settings.profiles[row]
        profile.name = profileNameField.stringValue
        profile.baseURL = baseURLField.stringValue
        profile.model = modelField.stringValue
        profile.apiKey = apiKeyField.stringValue
        profile.rateLimit = rateLimitPopup.titleOfSelectedItem ?? "2/s"
        
        settings.updateProfile(profile)
        // Refresh name in table
        profilesTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        
        reloadProfilePopups()
    }
    
    private func updateFormFromSelection() {
        let row = profilesTableView.selectedRow
        if row >= 0 && row < settings.profiles.count {
            let profile = settings.profiles[row]
            profileNameField.stringValue = profile.name
            baseURLField.stringValue = profile.baseURL
            modelField.stringValue = profile.model
            apiKeyField.stringValue = profile.apiKey
            rateLimitPopup.selectItem(withTitle: profile.rateLimit)
            
            profileFormContainer.isHidden = false
            noProfileLabel.isHidden = true
            connectionStatusLabel.stringValue = ""
        } else {
            profileFormContainer.isHidden = true
            noProfileLabel.isHidden = false
        }
    }
    
    private func reloadProfilePopups() {
        // Summary
        summaryProviderPopup.removeAllItems()
        translationProviderPopup.removeAllItems()
        
        let names = settings.profiles.map { $0.name }
        
        if names.isEmpty {
            summaryProviderPopup.addItem(withTitle: "No Providers")
            translationProviderPopup.addItem(withTitle: "No Providers")
            return
        }
        
        summaryProviderPopup.addItems(withTitles: names)
        translationProviderPopup.addItems(withTitles: names)
        
        if let sID = settings.summaryProfileID, let p = settings.profiles.first(where: { $0.id == sID }) {
            summaryProviderPopup.selectItem(withTitle: p.name)
        }
        
        if let tID = settings.translationProfileID, let p = settings.profiles.first(where: { $0.id == tID }) {
            translationProviderPopup.selectItem(withTitle: p.name)
        }
    }
    
    @objc private func summaryProviderChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if index >= 0 && index < settings.profiles.count {
            settings.summaryProfileID = settings.profiles[index].id
        }
    }
    
    @objc private func translationProviderChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if index >= 0 && index < settings.profiles.count {
            settings.translationProfileID = settings.profiles[index].id
        }
    }

    // Actions
    @objc private func toggleEnable(_ sender: NSButton) { settings.isEnabled = (sender.state == .on) }
    @objc private func languageChanged(_ sender: NSPopUpButton) { settings.outputLanguage = sender.titleOfSelectedItem ?? "English" }
    @objc private func toggleAutoTranslate(_ sender: NSButton) { settings.autoTranslate = (sender.state == .on) }
    @objc private func toggleAutoTranslateTitles(_ sender: NSButton) { settings.autoTranslateTitles = (sender.state == .on) }
    
    @objc private func resetSummaryPrompt() {
        settings.resetSummaryPrompt()
        summaryPromptField.string = settings.summaryPrompt
    }
    
    @objc private func resetTranslationPrompt() {
        settings.resetTranslationPrompt()
        translationPromptField.string = settings.translationPrompt
    }
    
    @objc private func clearSummaryCache() {
        AICacheManager.shared.clearSummaryCache()
        showDone("Summary Cache Cleared")
    }
    
    @objc private func clearTranslationCache() {
        AICacheManager.shared.clearTranslationCache()
        AICacheManager.shared.clearTitleTranslationCache()
        showDone("Translation Cache Cleared")
    }
    
    private func showDone(_ msg: String) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func testConnection(_ sender: NSButton) {
        updateCurrentProfile()
        
        connectionStatusLabel.stringValue = "Testing..."
        connectionStatusLabel.textColor = .secondaryLabelColor
        sender.isEnabled = false
        
        Task {
            do {
                _ = try await AIService.shared.testConnection()
                connectionStatusLabel.stringValue = "Success (General)"
                connectionStatusLabel.textColor = .systemGreen
            } catch {
                connectionStatusLabel.stringValue = "Failed: \(error.localizedDescription)"
                connectionStatusLabel.textColor = .systemRed
            }
            sender.isEnabled = true
        }
    }
}

extension AIPreferencesViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return settings.profiles.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("NameCell")
        var view = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField
        if view == nil {
            view = NSTextField()
            view?.identifier = id
            view?.isBordered = false
            view?.drawsBackground = false
            view?.isEditable = false
        }
        view?.stringValue = settings.profiles[row].name
        return view
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateFormFromSelection()
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
