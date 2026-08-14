import SwiftUI
import AppKit
import Combine
import ApplicationServices

// MARK: - Main App Entry Point
@main
struct typer: App {
    @StateObject private var typerLogic = TyperLogic()

    var body: some Scene {
        MenuBarExtra("AutoTyper", systemImage: "keyboard") {
            
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

        // Set of UTF-16 code points that require Shift key on standard US keyboards
        let shiftedSymbols: Set<UInt16> = [
            126, 33, 64, 35, 36, 37, 94, 38, 42, 40, 41, 95, 43, // ~ ! @ # $ % ^ & * ( ) _ +
            123, 125, 124, 58, 34, 60, 62, 63                   // { } | : " < > ?
        ]

        // Activate target application window
        app.activate()

        // Type characters asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait 300ms for target window focus animation to complete
            Thread.sleep(forTimeInterval: 0.3)

            // CRITICAL: Use .privateState so physical modifier keys (Ctrl/Opt/Cmd) do NOT leak into virtual keypresses
            guard let source = CGEventSource(stateID: .privateState) else { return }

            for char in clipboardText.utf16 {
                
                // STRICT FOCUS SAFETY SWITCH: Stop typing if target loses active window status
                guard app.isActive else {
                    print("⚠️ Focus switched away from target app. Auto-typing cancelled immediately.")
                    return
                }

                if char == 10 {
                    // --- NEWLINE / ENTER (\n) -> Keycode 36 ---
                    if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
                       let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) {
                        eventDown.flags = []
                        eventUp.flags = []
                        eventDown.post(tap: .cghidEventTap)
                        eventUp.post(tap: .cghidEventTap)
                    }
                } else if char == 9 {
                    // --- TAB (\t) -> Keycode 48 ---
                    if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: true),
                       let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: false) {
                        eventDown.flags = []
                        eventUp.flags = []
                        eventDown.post(tap: .cghidEventTap)
                        eventUp.post(tap: .cghidEventTap)
                    }
                } else if char == 32 {
                    // --- SPACE ( ) -> Keycode 49 ---
                    if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true),
                       let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false) {
                        eventDown.flags = []
                        eventUp.flags = []
                        eventDown.post(tap: .cghidEventTap)
                        eventUp.post(tap: .cghidEventTap)
                    }
                } else {
                    // --- REGULAR UNICODE CHARACTERS ---
                    var unichar = char
                    let isUppercase = (char >= 65 && char <= 90) // 'A'...'Z'
                    let needsShift = isUppercase || shiftedSymbols.contains(char)

                    if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                       let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                        
                        // Explicitly set or clear shift flag
                        let targetFlags: CGEventFlags = needsShift ? .maskShift : []
                        eventDown.flags = targetFlags
                        eventUp.flags = targetFlags

                        eventDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                        eventUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)

                        eventDown.post(tap: .cghidEventTap)
                        eventUp.post(tap: .cghidEventTap)
                    }
                }

                // 20ms throttle delay per character
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
