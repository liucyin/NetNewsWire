
import AppKit

enum AIMode {
    case summary
    case translation
}

final class AIPopoverViewController: NSViewController {
    
    private let articleText: String
    private let mode: AIMode
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Processing...")
    
    init(articleText: String, mode: AIMode) {
        self.articleText = articleText
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        performTask()
    }
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        
        view.addSubview(spinner)
        spinner.style = .spinning
        spinner.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        scrollView.isHidden = true
    }
    
    private func performTask() {
        spinner.startAnimation(nil)
        scrollView.isHidden = true
        statusLabel.isHidden = false
        statusLabel.stringValue = (mode == .summary) ? "Summarizing..." : "Translating..."
        
        Task {
            do {
                let result: String
                switch mode {
                case .summary:
                    result = try await AIService.shared.summarize(text: articleText)
                case .translation:
                    let target = AISettings.shared.outputLanguage
                    result = try await AIService.shared.translate(text: articleText, targetLanguage: target)
                }
                
                showResult(result)
            } catch {
                showError(error)
            }
        }
    }
    
    private func showResult(_ text: String) {
        // UI Updates on main thread
        Task { @MainActor in
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            statusLabel.isHidden = true
            scrollView.isHidden = false
            
            textView.string = text
        }
    }
    
    private func showError(_ error: Error) {
        Task { @MainActor in
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            statusLabel.isHidden = false
            statusLabel.stringValue = "Error: \(error.localizedDescription)"
            statusLabel.textColor = .red
        }
    }
}
