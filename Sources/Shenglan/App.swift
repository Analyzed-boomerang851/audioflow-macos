import AppKit
import SwiftUI

/// 音合流是菜单栏常驻应用。关闭控制器窗口只隐藏界面，不能结束音频服务
/// 或移除菜单栏图标；真正退出只能由“退出音合流”或 Command-Q 触发。
@MainActor
private final class ShenglanApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, let window = MenuBarPopoverController.shared.mainWindow {
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}

@main
struct ShenglanApp: App {
    @NSApplicationDelegateAdaptor(ShenglanApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var audio: AudioController

    init() {
        // 音合流既是菜单栏控制器，也是一个完整的桌面应用。使用 regular
        // activation policy 才会在 Dock 中保留真实应用图标，并让最小化窗口
        // 收进该图标，而不是生成一个孤立的窗口缩略图。
        NSApplication.shared.setActivationPolicy(.regular)
        let controller = AudioController()
        _audio = StateObject(wrappedValue: controller)
        MenuBarPopoverController.shared.bind(to: controller)
    }

    var body: some Scene {
        // `WindowGroup` creates another controller every time `openWindow` is
        // called.  音合流 is a single-workspace utility, so a single `Window`
        // scene is the correct lifecycle: repeated menu-bar clicks focus the
        // existing controller instead of stacking duplicate windows.
        Window(L10n.tr("音合流", language: audio.language), id: "main") {
            MainWindowView()
                .environmentObject(audio)
                .environment(\.liquidGlassEnabled, audio.useLiquidGlass)
                .environment(\.glassPanelOpacity, audio.glassPanelOpacity)
                .environment(\.appLanguage, audio.language)
                .environment(\.locale, audio.language.locale)
                .preferredColorScheme(colorScheme)
                .background(
                    WindowConfigurator(
                        theme: audio.theme,
                        systemUsesDarkAppearance: audio.systemUsesDarkAppearance,
                        language: audio.language
                    )
                )
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands { ShenglanCommands(audio: audio) }

    }

    private var colorScheme: ColorScheme {
        switch audio.theme {
        case .system: audio.systemUsesDarkAppearance ? .dark : .light
        case .light: .light
        case .dark: .dark
        }
    }

}

struct ShenglanCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var audio: AudioController

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandMenu(L10n.tr("声音控制", language: audio.language)) {
            Button(L10n.tr("打开声音控制器", language: audio.language)) {
                audio.selectedSection = .mixer
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("s", modifiers: [.option, .shift])
        }
        CommandGroup(replacing: .appSettings) {
            Button(L10n.tr("设置…", language: audio.language)) {
                audio.selectedSection = .settings
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    private static var configuredWindows = Set<ObjectIdentifier>()
    let theme: ThemeChoice
    let systemUsesDarkAppearance: Bool
    let language: AppLanguage

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        // `updateNSView` already runs on the main actor.  Deferring this to the
        // next run-loop turn leaves one frame where SwiftUI is dark but the
        // AppKit-hosted glass is still light.
        configure(view.window)
    }
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        let useDarkAppearance = theme == .dark || (theme == .system && systemUsesDarkAppearance)
        let appearance = NSAppearance(named: useDarkAppearance ? .darkAqua : .aqua)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.appearance = appearance
        window.contentView?.appearance = appearance
        window.backgroundColor = .windowBackgroundColor
        window.contentView?.needsDisplay = true
        CATransaction.commit()
        NSAnimationContext.endGrouping()
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: 1040, height: 720)
        window.maxSize = NSSize(width: 1600, height: 1050)
        window.miniwindowImage = NSApp.applicationIconImage
        window.title = L10n.tr("音合流", language: language)
        window.miniwindowTitle = L10n.tr("音合流", language: language)
        MenuBarPopoverController.shared.mainWindow = window
        let identifier = ObjectIdentifier(window)
        if !Self.configuredWindows.contains(identifier) {
            Self.configuredWindows.insert(identifier)
            window.setContentSize(NSSize(width: 1180, height: 780))
            window.center()
        }
    }
}

private final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Bridges AppKit's real expanded-window lifecycle into SwiftUI. The user-facing
/// "full screen" state includes both the green-button zoomed window and a native
/// full-screen Space, but deliberately excludes a regular window dragged wider.
struct WindowExpandedStateObserver: NSViewRepresentable {
    @Binding var isExpanded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isExpanded: $isExpanded)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isExpanded = $isExpanded
        context.coordinator.attach(to: view.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var isExpanded: Binding<Bool>
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(isExpanded: Binding<Bool>) {
            self.isExpanded = isExpanded
        }

        func attach(to candidate: NSWindow?) {
            guard let candidate else { return }
            guard window !== candidate else {
                synchronize(with: candidate)
                return
            }

            detach()
            window = candidate

            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification
            ]
            observers = names.map { name in
                center.addObserver(forName: name, object: candidate, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.synchronize(with: candidate)
                    }
                }
            }
            synchronize(with: candidate)
        }

        func detach() {
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
            window = nil
        }

        private func synchronize(with window: NSWindow) {
            let current = window.styleMask.contains(.fullScreen) || window.isZoomed
            if isExpanded.wrappedValue != current {
                isExpanded.wrappedValue = current
            }
        }
    }
}
