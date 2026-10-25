import SwiftUI
import AppKit
import Combine
import ApplicationServices

// MARK: - Main App Entry Point
@main
struct typer: App {
    @StateObject private var typerLogic = TyperLogic()

    var body: some Scene {
        MenuBarExtra("AutoTyper", image: "MenuBarIcon") {
            
            // 1. Accessibility Status Banner
            if !typerLogic.isAccessibilityGranted {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠️ Accessibility Required")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.red)
                    Text("Granted permission in System Settings?")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button("Open Accessibility Settings") {
                        typerLogic.openAccessibilitySettings()
                    }
                }
                Divider()
            } else {
                Text("Hotkey: ⌃ ⌥ V (Ctrl + Opt + V)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
            }

            // 2. Active Targets
            Text("Select target to type into:")
                .font(.caption2)
                .foregroundColor(.secondary)

            ForEach(typerLogic.runningApps, id: \.bundleIdentifier) { app in
                Button(app.localizedName ?? "Unknown App") {
                    typerLogic.typeClipboard(into: app)
                }
            }

            if typerLogic.runningApps.isEmpty {
                Text("No target apps (VS Code, Zoom, Teams) running")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // 3. Settings Options
            Toggle("Preview before typing", isOn: $typerLogic.previewBeforeType)

            Divider()

            Button("Check Permissions Again") {
                typerLogic.checkAccessibilityPermissions()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Logic Class
class TyperLogic: ObservableObject {
    
    @Published var isAccessibilityGranted: Bool = false
    @Published var runningApps: [NSRunningApplication] = []
    
    // Default to TRUE; persist choice across app restarts using UserDefaults
    @Published var previewBeforeType: Bool = UserDefaults.standard.object(forKey: "previewBeforeType") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(previewBeforeType, forKey: "previewBeforeType")
        }
    }
    
    let targetBundleIDs: Set<String> = [
        "com.microsoft.VSCode",          // Visual Studio Code
        "com.microsoft.VSCodeInsiders",  // VS Code Insiders
        "com.todesktop.230313m09beyd92",  // Cursor IDE
        "us.zoom.xos",                   // Zoom
        "com.microsoft.teams2",          // New Microsoft Teams
        "com.microsoft.teams",           // Classic Microsoft Teams
        "com.cisco.webexmeetingsapp"     // Webex
    ]

    private var globalMonitor: Any?
    private let typingQueue = DispatchQueue(label: "AutoTyper.typing", qos: .userInitiated)
    private var isTyping = false
    
    init() {
        checkAccessibilityPermissions()
        updateRunningApps()
        setupWorkspaceObervers()
    }
    
    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func updateRunningApps() {
        let activeTargets = NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return targetBundleIDs.contains(bundleID)
        }
        
        DispatchQueue.main.async {
            self.runningApps = activeTargets
        }
    }
    
    private func setupWorkspaceObervers() {
        let center = NSWorkspace.shared.notificationCenter
        
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningApps()
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRunningApps()
        }
    }

    // MARK: - Accessibility Helpers
    func checkAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
            if trusted {
                self.setupGlobalHotkey()
            }
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Global Hotkey
    func setupGlobalHotkey() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isVKey = event.keyCode == 9 // 'V' key

            let hasControl = flags.contains(.control)
            let hasOption = flags.contains(.option)

            if isVKey && hasControl && hasOption {
                DispatchQueue.main.async {
                    self?.triggerAutoTypeForActiveApp()
                }
            }
        }
    }

    private func triggerAutoTypeForActiveApp() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else { return }
        
        if let bundleID = activeApp.bundleIdentifier, targetBundleIDs.contains(bundleID) {
            typeClipboard(into: activeApp)
        } else {
            NSSound.beep()
            print("⚠️ Hotkey pressed in non-target app: \(activeApp.localizedName ?? "Unknown") [\(activeApp.bundleIdentifier ?? "No Bundle ID")]")
        }
    }

    // MARK: - Core Typing Engine
    func typeClipboard(into app: NSRunningApplication) {
        guard !isTyping else {
            NSSound.beep()
            return
        }

        // 1. Verify Accessibility permission
        if !AXIsProcessTrusted() {
            checkAccessibilityPermissions()
            openAccessibilitySettings()
            NSSound.beep()
            return
        }

        // 2. Read clipboard content
        guard let rawText = NSPasteboard.general.string(forType: .string), !rawText.isEmpty else {
            NSSound.beep()
            return
        }

        // 3. Show Preview Dialog IF Enabled
        if previewBeforeType {
            let alert = NSAlert()
            alert.messageText = "Confirm AutoType into \(app.localizedName ?? "Target App")"
            alert.informativeText = "Review the text below before typing (\(rawText.count) characters):"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Type Text") // Default button (Enter)
            alert.addButton(withTitle: "Cancel")    // Cancel button (Esc)

            // --- Construct Scrollable Text Area ---
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 220))
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = false
            scrollView.borderType = .bezelBorder

            let contentSize = scrollView.contentSize
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
            textView.minSize = NSSize(width: 0.0, height: contentSize.height)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            
            // Set monospaced font & text content
            textView.string = rawText
            textView.isEditable = false
            textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

            scrollView.documentView = textView
            alert.accessoryView = scrollView

            // Bring dialog to front of all windows
            NSApp.activate(ignoringOtherApps: true)
            
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                print("❌ AutoType cancelled by user.")
                return
            }
        }

        // 4. Proceed with typing execution
        // Normalize line endings
        let clipboardText = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // A modal preview can process another trigger while it is open.
        guard !isTyping else { return }
        isTyping = true
        app.activate()

        typingQueue.async {
            defer {
                DispatchQueue.main.async { self.isTyping = false }
            }
            // Allow the target window to activate before delivering events.
            Thread.sleep(forTimeInterval: 0.3)
            guard let source = CGEventSource(stateID: .privateState) else { return }

            for scalar in clipboardText.unicodeScalars {
                guard let input = KeyboardInput(scalar: scalar, source: source),
                      input.send(shouldContinue: { app.isActive }) else {
                    print("Auto-typing stopped: target lost focus or a keyboard event could not be created.")
                    return
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
