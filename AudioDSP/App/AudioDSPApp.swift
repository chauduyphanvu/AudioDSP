import SwiftUI
import AppKit

@main
struct AudioDSPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appSettings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 700)
                .preferredColorScheme(appSettings.colorScheme)
                .onAppear {
                    WindowStateManager.shared.restoreWindowState()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openKeyboardShortcuts)) { _ in
                    openWindow(id: "keyboard-shortcuts")
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 800)
        .commands {
            appCommands
        }

        Settings {
            SettingsView()
                .environmentObject(appSettings)
        }

        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 600)
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Acknowledgments") {
                showAcknowledgments()
            }
        }

        CommandGroup(after: .windowArrangement) {
            Button("Show Main Window") {
                showMainWindow()
            }
            .keyboardShortcut("0", modifiers: .command)
        }

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

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                openKeyboardShortcuts()
            }
            .keyboardShortcut("/", modifiers: .command)

            Divider()

            Button("Audio DSP Help") {
                openHelp()
            }
        }
    }
}

private func openKeyboardShortcuts() {
    NotificationCenter.default.post(name: .openKeyboardShortcuts, object: nil)
}

private func openHelp() {
    if let helpURL = Bundle.main.url(forResource: "AudioDSPHelp", withExtension: "html") {
        NSWorkspace.shared.open(helpURL)
    }
}

private func showAcknowledgments() {
    let alert = NSAlert()
    alert.messageText = "Acknowledgments"
    alert.informativeText = """
    Audio DSP uses the following technologies:

    • CoreAudio for low-latency audio processing
    • Accelerate.framework for DSP operations
    • SwiftUI for the user interface

    Thank you for using Audio DSP!
    """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Initialize menu bar status item
        statusBarController = StatusBarController()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowStateManager.shared.saveWindowState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        DockMenuBuilder.buildMenu()
    }
}

// MARK: - Dock Menu Builder

enum DockMenuBuilder {
    static func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Engine controls
        let startItem = NSMenuItem(
            title: "Start Engine",
            action: #selector(DockMenuActions.startEngine),
            keyEquivalent: ""
        )
        startItem.target = DockMenuActions.shared
        menu.addItem(startItem)

        let stopItem = NSMenuItem(
            title: "Stop Engine",
            action: #selector(DockMenuActions.stopEngine),
            keyEquivalent: ""
        )
        stopItem.target = DockMenuActions.shared
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        // A/B Toggle
        let abItem = NSMenuItem(
            title: "Toggle A/B",
            action: #selector(DockMenuActions.toggleAB),
            keyEquivalent: ""
        )
        abItem.target = DockMenuActions.shared
        menu.addItem(abItem)

        // Bypass All
        let bypassItem = NSMenuItem(
            title: "Bypass All Effects",
            action: #selector(DockMenuActions.bypassAll),
            keyEquivalent: ""
        )
        bypassItem.target = DockMenuActions.shared
        menu.addItem(bypassItem)

        menu.addItem(NSMenuItem.separator())

        // Preset navigation
        let prevPresetItem = NSMenuItem(
            title: "Previous Preset",
            action: #selector(DockMenuActions.previousPreset),
            keyEquivalent: ""
        )
        prevPresetItem.target = DockMenuActions.shared
        menu.addItem(prevPresetItem)

        let nextPresetItem = NSMenuItem(
            title: "Next Preset",
            action: #selector(DockMenuActions.nextPreset),
            keyEquivalent: ""
        )
        nextPresetItem.target = DockMenuActions.shared
        menu.addItem(nextPresetItem)

        menu.addItem(NSMenuItem.separator())

        // Reset
        let resetItem = NSMenuItem(
            title: "Reset All Parameters",
            action: #selector(DockMenuActions.resetAll),
            keyEquivalent: ""
        )
        resetItem.target = DockMenuActions.shared
        menu.addItem(resetItem)

        return menu
    }
}

// MARK: - Dock Menu Actions

class DockMenuActions: NSObject {
    static let shared = DockMenuActions()

    @objc func startEngine() {
        NotificationCenter.default.post(name: .startEngine, object: nil)
    }

    @objc func stopEngine() {
        NotificationCenter.default.post(name: .stopEngine, object: nil)
    }

    @objc func toggleAB() {
        NotificationCenter.default.post(name: .toggleAB, object: nil)
    }

    @objc func bypassAll() {
        NotificationCenter.default.post(name: .bypassAll, object: nil)
    }

    @objc func previousPreset() {
        NotificationCenter.default.post(name: .previousPreset, object: nil)
    }

    @objc func nextPreset() {
        NotificationCenter.default.post(name: .nextPreset, object: nil)
    }

    @objc func resetAll() {
        NotificationCenter.default.post(name: .resetAll, object: nil)
    }
}

// MARK: - Status Bar Controller

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var isEngineRunning = false
    private var engineObserver: Any?

    override init() {
        super.init()
        setupStatusItem()
        observeEngineStatus()
    }

    deinit {
        if let observer = engineObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateIcon(isRunning: false)
            button.toolTip = "Audio DSP"
        }

        statusItem?.menu = buildMenu()
    }

    private func observeEngineStatus() {
        // Observe engine start
        engineObserver = NotificationCenter.default.addObserver(
            forName: .engineStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let isRunning = notification.userInfo?["isRunning"] as? Bool {
                self?.isEngineRunning = isRunning
                self?.updateIcon(isRunning: isRunning)
                self?.statusItem?.menu = self?.buildMenu()
            }
        }
    }

    private func updateIcon(isRunning: Bool) {
        guard let button = statusItem?.button else { return }

        let iconName = isRunning ? "waveform.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Audio DSP")

        // Configure for menu bar
        image?.isTemplate = !isRunning  // Template for inactive, colored for active

        if isRunning {
            // Create a colored version for active state
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            button.image = image?.withSymbolConfiguration(config)
        } else {
            button.image = image
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Status header
        let statusItem = NSMenuItem(title: isEngineRunning ? "Engine Running" : "Engine Stopped", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        if let image = NSImage(systemSymbolName: isEngineRunning ? "checkmark.circle.fill" : "xmark.circle", accessibilityDescription: nil) {
            image.isTemplate = false
            let config = NSImage.SymbolConfiguration(paletteColors: [isEngineRunning ? .systemGreen : .systemRed])
            statusItem.image = image.withSymbolConfiguration(config)
        }
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Engine toggle
        let engineItem = NSMenuItem(
            title: isEngineRunning ? "Stop Engine" : "Start Engine",
            action: isEngineRunning ? #selector(StatusBarActions.stopEngine) : #selector(StatusBarActions.startEngine),
            keyEquivalent: ""
        )
        engineItem.target = StatusBarActions.shared
        if let image = NSImage(systemSymbolName: isEngineRunning ? "stop.fill" : "play.fill", accessibilityDescription: nil) {
            engineItem.image = image
        }
        menu.addItem(engineItem)

        menu.addItem(NSMenuItem.separator())

        // A/B Toggle
        let abItem = NSMenuItem(
            title: "Toggle A/B",
            action: #selector(StatusBarActions.toggleAB),
            keyEquivalent: "B"
        )
        abItem.keyEquivalentModifierMask = .command
        abItem.target = StatusBarActions.shared
        if let image = NSImage(systemSymbolName: "a.square.fill", accessibilityDescription: nil) {
            abItem.image = image
        }
        menu.addItem(abItem)

        // Bypass All
        let bypassItem = NSMenuItem(
            title: "Bypass All Effects",
            action: #selector(StatusBarActions.bypassAll),
            keyEquivalent: ""
        )
        bypassItem.target = StatusBarActions.shared
        if let image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: nil) {
            bypassItem.image = image
        }
        menu.addItem(bypassItem)

        menu.addItem(NSMenuItem.separator())

        // Presets submenu
        let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        if let image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
            presetsItem.image = image
        }
        let presetsSubmenu = NSMenu()

        let prevItem = NSMenuItem(
            title: "Previous",
            action: #selector(StatusBarActions.previousPreset),
            keyEquivalent: "["
        )
        prevItem.keyEquivalentModifierMask = .command
        prevItem.target = StatusBarActions.shared
        presetsSubmenu.addItem(prevItem)

        let nextItem = NSMenuItem(
            title: "Next",
            action: #selector(StatusBarActions.nextPreset),
            keyEquivalent: "]"
        )
        nextItem.keyEquivalentModifierMask = .command
        nextItem.target = StatusBarActions.shared
        presetsSubmenu.addItem(nextItem)

        presetsSubmenu.addItem(NSMenuItem.separator())

        let saveItem = NSMenuItem(
            title: "Save Preset...",
            action: #selector(StatusBarActions.savePreset),
            keyEquivalent: "S"
        )
        saveItem.keyEquivalentModifierMask = .command
        saveItem.target = StatusBarActions.shared
        presetsSubmenu.addItem(saveItem)

        presetsItem.submenu = presetsSubmenu
        menu.addItem(presetsItem)

        menu.addItem(NSMenuItem.separator())

        // Show Window
        let windowItem = NSMenuItem(
            title: "Show Audio DSP",
            action: #selector(StatusBarActions.showMainWindow),
            keyEquivalent: ""
        )
        windowItem.target = StatusBarActions.shared
        if let image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) {
            windowItem.image = image
        }
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Audio DSP",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }
}

// MARK: - Status Bar Actions

class StatusBarActions: NSObject {
    static let shared = StatusBarActions()

    @objc func startEngine() {
        NotificationCenter.default.post(name: .startEngine, object: nil)
    }

    @objc func stopEngine() {
        NotificationCenter.default.post(name: .stopEngine, object: nil)
    }

    @objc func toggleAB() {
        NotificationCenter.default.post(name: .toggleAB, object: nil)
    }

    @objc func bypassAll() {
        NotificationCenter.default.post(name: .bypassAll, object: nil)
    }

    @objc func previousPreset() {
        NotificationCenter.default.post(name: .previousPreset, object: nil)
    }

    @objc func nextPreset() {
        NotificationCenter.default.post(name: .nextPreset, object: nil)
    }

    @objc func savePreset() {
        NotificationCenter.default.post(name: .savePreset, object: nil)
    }

    @objc func showMainWindow() {
        showMainWindowGlobal()
    }
}

// MARK: - Engine Status Notification

extension Notification.Name {
    static let engineStatusChanged = Notification.Name("engineStatusChanged")
}

func showMainWindowGlobal() {
    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// Alias for backwards compatibility
func showMainWindow() {
    showMainWindowGlobal()
}

// MARK: - App Settings

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("colorSchemePreference") var colorSchemePreference: ColorSchemePreference = .dark {
        didSet { objectWillChange.send() }
    }

    @AppStorage("showSpectrumByDefault") var showSpectrumByDefault: Bool = true
    @AppStorage("peakHoldDuration") var peakHoldDuration: Double = 2.0
    @AppStorage("meterDecayRate") var meterDecayRate: Double = 20.0

    var colorScheme: ColorScheme? {
        switch colorSchemePreference {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    enum ColorSchemePreference: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
    }

    private init() {}
}

// MARK: - Window State Manager

final class WindowStateManager {
    static let shared = WindowStateManager()

    private let autosaveName = "AudioDSPMainWindow"

    func saveWindowState() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        window.saveFrame(usingName: autosaveName)
    }

    func restoreWindowState() {
        DispatchQueue.main.async { [self] in
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            window.setFrameAutosaveName(autosaveName)
        }
    }

    private init() {}
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appSettings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AppearanceSettingsView()
                .environmentObject(appSettings)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        Form {
            Toggle("Show Spectrum Analyzer by Default", isOn: $appSettings.showSpectrumByDefault)

            LabeledContent("Peak Hold Duration") {
                Picker("", selection: $appSettings.peakHoldDuration) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("Infinite").tag(Double.infinity)
                }
                .labelsHidden()
                .frame(width: 120)
            }

            LabeledContent("Meter Decay Rate") {
                Picker("", selection: $appSettings.meterDecayRate) {
                    Text("Slow (10 dB/s)").tag(10.0)
                    Text("Normal (20 dB/s)").tag(20.0)
                    Text("Fast (40 dB/s)").tag(40.0)
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        Form {
            Picker("Appearance", selection: $appSettings.colorSchemePreference) {
                ForEach(AppSettings.ColorSchemePreference.allCases, id: \.self) { preference in
                    Text(preference.rawValue).tag(preference)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Keyboard Shortcuts View

struct KeyboardShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShortcutSection(title: "Audio Engine", shortcuts: [
                    ("Start Engine", "⌘R"),
                    ("Stop Engine", "⌘."),
                    ("Toggle A/B Comparison", "⌘B"),
                    ("Bypass All Effects", "⌥⌘0"),
                ])

                ShortcutSection(title: "Effects", shortcuts: [
                    ("Bypass EQ", "⌘1"),
                    ("Bypass Compressor", "⌘2"),
                    ("Bypass Limiter", "⌘3"),
                    ("Bypass Reverb", "⌘4"),
                    ("Bypass Delay", "⌘5"),
                    ("Bypass Stereo Widener", "⌘6"),
                    ("Bypass Bass Enhancer", "⌘7"),
                    ("Bypass Vocal Clarity", "⌘8"),
                    ("Reset All Parameters", "⌥⌘R"),
                ])

                ShortcutSection(title: "Presets", shortcuts: [
                    ("Save Preset", "⌘S"),
                    ("Previous Preset", "⌘["),
                    ("Next Preset", "⌘]"),
                ])

                ShortcutSection(title: "Edit", shortcuts: [
                    ("Undo", "⌘Z"),
                    ("Redo", "⇧⌘Z"),
                ])

                ShortcutSection(title: "Window", shortcuts: [
                    ("Show Main Window", "⌘0"),
                    ("Settings", "⌘,"),
                    ("Keyboard Shortcuts", "⌘/"),
                ])

                ShortcutSection(title: "Controls", shortcuts: [
                    ("Fine Adjustment", "Hold ⌥ while dragging"),
                    ("Reset to Default", "Double-click control"),
                ])
            }
            .padding(24)
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    HStack {
                        Text(shortcut.0)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(shortcut.1)
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
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

    // Window
    static let openKeyboardShortcuts = Notification.Name("openKeyboardShortcuts")
}
