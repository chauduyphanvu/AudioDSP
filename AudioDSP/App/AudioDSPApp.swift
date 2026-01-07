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

                Divider()

                Button("Bypass All Effects") {
                    NotificationCenter.default.post(name: .bypassAll, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }

            // Effects bypass menu
            CommandMenu("Effects") {
                Button("Bypass EQ") {
                    NotificationCenter.default.post(name: .toggleEQ, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Bypass Compressor") {
                    NotificationCenter.default.post(name: .toggleCompressor, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Bypass Limiter") {
                    NotificationCenter.default.post(name: .toggleLimiter, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Bypass Reverb") {
                    NotificationCenter.default.post(name: .toggleReverb, object: nil)
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Bypass Delay") {
                    NotificationCenter.default.post(name: .toggleDelay, object: nil)
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Bypass Stereo Widener") {
                    NotificationCenter.default.post(name: .toggleStereoWidener, object: nil)
                }
                .keyboardShortcut("6", modifiers: .command)

                Divider()

                Button("Bypass Bass Enhancer") {
                    NotificationCenter.default.post(name: .toggleBassEnhancer, object: nil)
                }
                .keyboardShortcut("7", modifiers: .command)

                Button("Bypass Vocal Clarity") {
                    NotificationCenter.default.post(name: .toggleVocalClarity, object: nil)
                }
                .keyboardShortcut("8", modifiers: .command)

                Divider()

                Button("Reset All Parameters") {
                    NotificationCenter.default.post(name: .resetAll, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
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
    // Edit
    static let undo = Notification.Name("undo")
    static let redo = Notification.Name("redo")

    // Audio
    static let startEngine = Notification.Name("startEngine")
    static let stopEngine = Notification.Name("stopEngine")
    static let toggleAB = Notification.Name("toggleAB")
    static let bypassAll = Notification.Name("bypassAll")

    // Effects bypass
    static let toggleEQ = Notification.Name("toggleEQ")
    static let toggleCompressor = Notification.Name("toggleCompressor")
    static let toggleLimiter = Notification.Name("toggleLimiter")
    static let toggleReverb = Notification.Name("toggleReverb")
    static let toggleDelay = Notification.Name("toggleDelay")
    static let toggleStereoWidener = Notification.Name("toggleStereoWidener")
    static let toggleBassEnhancer = Notification.Name("toggleBassEnhancer")
    static let toggleVocalClarity = Notification.Name("toggleVocalClarity")
    static let resetAll = Notification.Name("resetAll")

    // Presets
    static let savePreset = Notification.Name("savePreset")
    static let previousPreset = Notification.Name("previousPreset")
    static let nextPreset = Notification.Name("nextPreset")
}
