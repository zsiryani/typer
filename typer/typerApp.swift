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
    
    let targetBundleIDs: Set<String> = [
        "com.microsoft.VSCode",        // Visual Studio Code
        "com.microsoft.VSCodeInsiders",// VS Code Insiders
        "us.zoom.xos",                 // Zoom
        "com.microsoft.teams2",        // New Microsoft Teams
        "com.microsoft.teams",         // Classic Microsoft Teams
        "com.cisco.webexmeetingsapp"   // Webex
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

    // MARK: - Core Typing Engine with Preview Dialog
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

        // 3. Format preview text for confirmation dialog
        let maxPreviewLength = 300
        let previewContent: String
        if rawText.count > maxPreviewLength {
            previewContent = String(rawText.prefix(maxPreviewLength)) + "\n\n... [Truncated: \(rawText.count) characters total]"
        } else {
            previewContent = rawText
        }

        // 4. Present Modal Preview Alert
        let alert = NSAlert()
        alert.messageText = "Confirm AutoType into \(app.localizedName ?? "Target App")"
        alert.informativeText = "Are you sure you want to type the following clipboard content?\n\n\"\(previewContent)\""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Type Text") // Default button (Enter / Return)
        alert.addButton(withTitle: "Cancel")    // Cancel button (Esc)

        // Bring dialog to front of all windows
        NSApp.activate()
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            print("❌ AutoType cancelled by user.")
            return
        }

        // 5. Proceed with typing if confirmed
        let targetPID = app.processIdentifier

        // Normalize line endings
        let clipboardText = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Activate target application window
        app.activate()

        // Type characters asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait 300ms for target window focus animation to complete
            Thread.sleep(forTimeInterval: 0.3)

            let source = CGEventSource(stateID: .hidSystemState)

            for char in clipboardText.utf16 {
                
                // FOCUS SAFETY SWITCH: Stop typing if target loses focus mid-way
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
                    print("⚠️ Focus switched away from target. Auto-typing cancelled.")
                    return
                }

                if char == 10 {
                    // --- NEWLINE / ENTER (\n) ---
                    if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
                       let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) {
                        eventDown.post(tap: .cghidEventTap)
                        eventUp.post(tap: .cghidEventTap)
                    }
                } else if char == 9 {
                    // --- TAB (\t) ---
                    if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: true),
                       let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: false) {
                        eventDown.post(tap: .cghidEventTap)
                        eventUp.post(tap: .cghidEventTap)
                    }
                } else {
                    // --- REGULAR UNICODE CHARACTERS ---
                    var unichar = char
                    if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                       let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                        
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
