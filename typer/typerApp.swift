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
    
    let targetBundleIDs: Set<String> = [
        "com.microsoft.VSCode",      // Visual Studio Code
        "us.zoom.xos",               // Zoom
        "com.microsoft.teams2",      // New Microsoft Teams
        "com.microsoft.teams",       // Classic Microsoft Teams
        "com.cisco.webexmeetingsapp" // Webex
    ]

    init() {
        checkAccessibilityPermissions()
        setupGlobalHotkey()
    }

    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return targetBundleIDs.contains(bundleID)
        }
    }

    // MARK: - Accessibility Helpers
    func checkAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Global Hotkey
    private func setupGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isVKey = event.keyCode == 9 // 'V' key
            let hasControl = event.modifierFlags.contains(.control)
            let hasOption = event.modifierFlags.contains(.option)

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
            // Beep if hotkey was hit while in an unsupported app
            NSSound.beep()
        }
    }

    // MARK: - Core Typing Engine
    
    func typeClipboard(into app: NSRunningApplication) {
        // Verify Accessibility permission
        if !AXIsProcessTrusted() {
            checkAccessibilityPermissions()
            openAccessibilitySettings()
            NSSound.beep()
            return
        }

        guard let rawText = NSPasteboard.general.string(forType: .string), !rawText.isEmpty else {
            NSSound.beep()
            return
        }

        let targetPID = app.processIdentifier

        // Normalize line endings
        let clipboardText = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // 1. Force target app to front
        app.activate()

        // 2. Type characters asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait 300ms for window focus animation to complete
            Thread.sleep(forTimeInterval: 0.3)

            let source = CGEventSource(stateID: .hidSystemState)

            for char in clipboardText.utf16 {
                
                // --- FOCUS SAFETY SWITCH ---
                // If user clicks another window/app mid-typing, STOP IMMEDIATELY.
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
