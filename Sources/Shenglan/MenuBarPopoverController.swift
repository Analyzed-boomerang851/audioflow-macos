import AppKit
import Combine
import SwiftUI

/// Owns one status item and one native popover for the lifetime of the app.
/// `NSPopover` supplies the arrow, glass surface, shadow, anchoring and reveal
/// animation as one AppKit surface, avoiding a second custom shell.
@MainActor
final class MenuBarPopoverController: NSObject, NSPopoverDelegate {
    static let shared = MenuBarPopoverController()

    weak var mainWindow: NSWindow?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private weak var audio: AudioController?
    private var cancellables = Set<AnyCancellable>()
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    private override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    func bind(to audio: AudioController) {
        guard self.audio !== audio else { return }
        self.audio = audio
        cancellables.removeAll()

        let hostingController = NSHostingController(rootView: makeRootView(for: audio))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            updateAccessibility(for: button, audio: audio)
        }

        // The popover observes the controller and updates its own content.
        // Rebuilding the status item for every per-app volume event caused the
        // AppKit shell to repaint while a slider was tracking. Listen only to
        // properties that actually change the status image.
        Publishers.MergeMany([
            audio.$masterVolume.map { _ in () }.eraseToAnyPublisher(),
            audio.$masterMuted.map { _ in () }.eraseToAnyPublisher(),
            audio.$menuBarIcon.map { _ in () }.eraseToAnyPublisher(),
            audio.$showMenuBarVolume.map { _ in () }.eraseToAnyPublisher(),
            audio.$menuBarVolumeStyle.map { _ in () }.eraseToAnyPublisher()
        ])
            // The NSSlider already tracks at the display refresh rate.  The
            // menu-bar image is a separate AppKit render and does not need to
            // be regenerated for every pointer event; doing so competed with
            // slider tracking and made the whole controller feel sticky.
            .throttle(for: .milliseconds(34), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        // Theme is special: the SwiftUI hierarchy and the AppKit popover shell
        // must adopt the resolved appearance in the same update.  Waiting for
        // the generic objectWillChange refresh leaves one light popover frame
        // around already-dark SwiftUI content (or the inverse).
        audio.$theme
            .combineLatest(audio.$systemUsesDarkAppearance)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self, let audio = self.audio else { return }
                // Reassigning the root makes the resolved color scheme part of
                // the new SwiftUI environment in the same pass as AppKit.
                // Merely observing the controller can leave a cached light
                // environment inside a dark NSPopover.
                if let hostingController = self.popover.contentViewController
                    as? NSHostingController<MenuBarPopoverRoot> {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        hostingController.rootView = self.makeRootView(for: audio)
                    }
                }
                self.applyAppearance()
            }
            .store(in: &cancellables)

        audio.$language
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let audio = self.audio else { return }
                if let hostingController = self.popover.contentViewController
                    as? NSHostingController<MenuBarPopoverRoot> {
                    hostingController.rootView = self.makeRootView(for: audio)
                }
                if let button = self.statusItem.button {
                    self.updateAccessibility(for: button, audio: audio)
                }
            }
            .store(in: &cancellables)

        audio.$menuBarPopoverStyle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let audio = self.audio,
                      let hostingController = self.popover.contentViewController
                        as? NSHostingController<MenuBarPopoverRoot> else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    hostingController.rootView = self.makeRootView(for: audio)
                }
                hostingController.view.layoutSubtreeIfNeeded()
            }
            .store(in: &cancellables)

        refreshPresentation()
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        applyAppearance()
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        configurePopoverWindowForCurrentSpace()
        // AppKit can finish attaching the private NSPopover window one run-loop
        // after `show`. Configure it again once attached so a click from another
        // app's full-screen Space never leaves the panel on the desktop Space.
        DispatchQueue.main.async { [weak self] in
            self?.configurePopoverWindowForCurrentSpace()
        }
        installOutsideClickMonitors()
    }

    func popoverDidShow(_ notification: Notification) {
        configurePopoverWindowForCurrentSpace()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem.button?.window
            if event.window !== popoverWindow, event.window !== statusWindow {
                self.closePopover()
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    /// A status-item popover must be allowed into the currently active
    /// full-screen Space. NSPopover's private window does not consistently add
    /// these behaviors when the owning app is inactive, which made 音合流 look
    /// unresponsive over full-screen apps even though the menu-bar click fired.
    private func configurePopoverWindowForCurrentSpace() {
        guard let window = popover.contentViewController?.view.window else { return }

        // `moveToActiveSpace` conflicts with `canJoinAllSpaces`; remove it before
        // adding the same full-screen behaviors used by menu-bar utility panels.
        window.collectionBehavior.remove(.moveToActiveSpace)
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.transient)
        window.collectionBehavior.insert(.ignoresCycle)
        window.level = .statusBar
        window.orderFrontRegardless()
    }

    private func refreshPresentation() {
        refreshStatusItem()
        applyAppearance()
    }

    private func refreshStatusItem() {
        guard let audio, let button = statusItem.button else { return }
        let image = MenuBarStatusImage.make(
            icon: audio.menuBarIcon,
            volume: audio.masterVolume,
            muted: audio.masterMuted,
            showsVolume: audio.showMenuBarVolume,
            volumeStyle: audio.menuBarVolumeStyle
        )
        button.image = image
        statusItem.length = max(NSStatusItem.squareLength, image.size.width + 12)
        updateAccessibility(for: button, audio: audio)
    }

    private func updateAccessibility(for button: NSStatusBarButton, audio: AudioController) {
        button.setAccessibilityLabel(L10n.tr("打开音合流", language: audio.language))
        button.setAccessibilityHelp(L10n.tr("打开系统与应用音量控制器", language: audio.language))
    }

    private func applyAppearance() {
        guard let audio else { return }
        let appearance: NSAppearance?
        let useDarkAppearance = audio.theme == .dark
            || (audio.theme == .system && audio.systemUsesDarkAppearance)
        appearance = NSAppearance(named: useDarkAppearance ? .darkAqua : .aqua)

        // NSPopover, NSHostingController and native Glass Effect otherwise run
        // separate implicit appearance transitions.  Disable those AppKit and
        // Core Animation actions so the shell, arrow and every glass control
        // swap as a single surface.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        popover.appearance = appearance
        if let view = popover.contentViewController?.view {
            view.appearance = appearance
            view.needsDisplay = true
            view.layer?.setNeedsDisplay()
        }
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }

    private func makeRootView(for audio: AudioController) -> MenuBarPopoverRoot {
        let useDarkAppearance = audio.theme == .dark
            || (audio.theme == .system && audio.systemUsesDarkAppearance)
        return MenuBarPopoverRoot(audio: audio, colorScheme: useDarkAppearance ? .dark : .light)
    }
}

private struct MenuBarPopoverRoot: View {
    @ObservedObject var audio: AudioController
    let colorScheme: ColorScheme
    @State private var contentVisible = false

    var body: some View {
        MenuBarControlView()
            .environmentObject(audio)
            .environment(\.liquidGlassEnabled, audio.useLiquidGlass)
            .environment(\.glassPanelOpacity, audio.glassPanelOpacity)
            .environment(\.appLanguage, audio.language)
            .environment(\.locale, audio.language.locale)
            .preferredColorScheme(colorScheme)
            // NSPopover supplies the shell animation. This short content reveal
            // removes the hard one-frame pop without introducing a second,
            // visibly detached layer.
            .opacity(contentVisible ? 1 : 0.94)
            .scaleEffect(contentVisible ? 1 : 0.992, anchor: .top)
            .offset(y: contentVisible ? 0 : -3)
            .onAppear {
                withAnimation(.easeOut(duration: 0.13)) {
                    contentVisible = true
                }
            }
    }
}
