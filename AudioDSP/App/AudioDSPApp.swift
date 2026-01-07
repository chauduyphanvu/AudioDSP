import SwiftUI
import AppKit

@main
struct AudioDSPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 800)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show Main Window") {
                    showMainWindow()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
        .commands {
            // Edit menu with undo/redo
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .undo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    NotificationCenter.default.post(name: .redo, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            // Custom audio menu
            CommandMenu("Audio") {
                Button("Start Engine") {
                    NotificationCenter.default.post(name: .startEngine, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Stop Engine") {
                    NotificationCenter.default.post(name: .stopEngine, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Toggle A/B") {
                    NotificationCenter.default.post(name: .toggleAB, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }

            // Preset menu
            CommandMenu("Presets") {
                Button("Save Preset...") {
                    NotificationCenter.default.post(name: .savePreset, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Load Previous Preset") {
                    NotificationCenter.default.post(name: .previousPreset, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Load Next Preset") {
                    NotificationCenter.default.post(name: .nextPreset, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
}

func showMainWindow() {
    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let undo = Notification.Name("undo")
    static let redo = Notification.Name("redo")
    static let startEngine = Notification.Name("startEngine")
    static let stopEngine = Notification.Name("stopEngine")
    static let toggleAB = Notification.Name("toggleAB")
    static let savePreset = Notification.Name("savePreset")
    static let previousPreset = Notification.Name("previousPreset")
    static let nextPreset = Notification.Name("nextPreset")
}
