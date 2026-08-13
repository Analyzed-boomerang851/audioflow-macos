import AppKit
import SwiftUI

enum ShenglanTypography {
    // One compact type scale for the controller. Keeping every textual role on
    // 16 / 14 / 12 points prevents SwiftUI semantic styles from silently
    // producing unrelated sizes across the mixer, device and settings pages.
    static let navigation = Font.system(size: 16, weight: .medium)
    static let navigationSelected = Font.system(size: 16, weight: .semibold)
    static let pageTitle = Font.system(size: 16, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let control = Font.system(size: 14, weight: .medium)
    static let body = Font.system(size: 14, weight: .regular)
    static let bodyStrong = Font.system(size: 14, weight: .semibold)
    static let caption = Font.system(size: 12, weight: .regular)
    static let captionStrong = Font.system(size: 12, weight: .semibold)
}

private struct LiquidGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct GlassPanelOpacityKey: EnvironmentKey {
    static let defaultValue = 0.78
}

extension EnvironmentValues {
    var liquidGlassEnabled: Bool {
        get { self[LiquidGlassEnabledKey.self] }
        set { self[LiquidGlassEnabledKey.self] = newValue }
    }

    var glassPanelOpacity: Double {
        get { self[GlassPanelOpacityKey.self] }
        set { self[GlassPanelOpacityKey.self] = min(max(newValue, 0.18), 1) }
    }
}

private enum ShenglanAsset {
    static let icon: NSImage? = {
        if let url = Bundle.main.url(forResource: "ShenglanIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let image = NSImage(named: NSImage.applicationIconName) {
            return image
        }
        if let url = Bundle.module.url(forResource: "ShenglanIcon", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()
}

struct ShenglanIcon: View {
    var size: CGFloat = 38
    var body: some View {
        Group {
            if let image = ShenglanAsset.icon {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "waveform.path.ecg").resizable().scaledToFit().padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }
}

/// One shared backdrop for the controller window and menu-bar popover. The
/// uploaded image stays below every glass surface, so native material samples
/// the same pixels in both presentation modes instead of behaving like a
/// decorative image pasted into one page.
struct ThemeBackdrop: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ThemeBackdropContent(
            image: audio.customThemeBackgroundImage,
            imageIdentity: audio.customThemeBackgroundName,
            isEnabled: audio.customThemeBackgroundEnabled,
            opacity: audio.customThemeBackgroundOpacity,
            blur: audio.customThemeBackgroundBlur,
            isDark: colorScheme == .dark
        )
        .equatable()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keep the expensive, full-window image and blur renderer independent from
/// `AudioController`'s high-frequency volume publications. Without this
/// boundary, every application-volume event asked SwiftUI to rebuild the
/// backdrop and made otherwise-native sliders feel sticky.
private struct ThemeBackdropContent: View, Equatable {
    let image: NSImage?
    let imageIdentity: String?
    let isEnabled: Bool
    let opacity: Double
    let blur: Double
    let isDark: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.image === rhs.image
            && lhs.imageIdentity == rhs.imageIdentity
            && lhs.isEnabled == rhs.isEnabled
            && abs(lhs.opacity - rhs.opacity) < 0.0001
            && abs(lhs.blur - rhs.blur) < 0.0001
            && lhs.isDark == rhs.isDark
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                baseColor
                    .allowsHitTesting(false)

                if isEnabled, let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .saturation(isDark ? 0.78 : 0.7)
                        .contrast(isDark ? 0.92 : 0.88)
                        .blur(radius: blur, opaque: true)
                        .opacity(opacity)
                        .clipped()
                        // This is a full-window visual layer. Keep the rule on
                        // the image itself (not only on its parent) because the
                        // blur renderer may bridge through a separate AppKit
                        // surface when an uploaded image is present.
                        .allowsHitTesting(false)

                    LinearGradient(
                        colors: overlayColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .allowsHitTesting(false)

                    Color(isDark ? .black : .white)
                        .opacity(backgroundVeilOpacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private var baseColor: Color {
        isDark ? Color(white: 0.045) : Color(white: 0.985)
    }

    private var overlayColors: [Color] {
        if isDark {
            return [Color.black.opacity(0.22), Color.clear, Color.black.opacity(0.38)]
        }
        return [Color.white.opacity(0.28), Color.clear, Color.white.opacity(0.48)]
    }

    private var backgroundVeilOpacity: Double {
        let base = isDark ? 0.20 : 0.28
        return min(base + (1 - opacity) * 0.32, 0.62)
    }
}

struct AppIconView: View {
    var image: NSImage?
    var fallback: String = "app.fill"
    var size: CGFloat = 32
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high) }
            else { Image(systemName: fallback).resizable().scaledToFit().padding(size * 0.22).foregroundStyle(.primary) }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}

struct GlassCardModifier: ViewModifier {
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.glassPanelOpacity) private var glassPanelOpacity
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat
    var tint: Color?
    var interactive: Bool

    func body(content: Content) -> some View {
        // Keep `content` outside the material branches.  Switching material
        // now swaps only a decorative background instead of replacing the
        // card (and, for the settings detail card, its entire ScrollView).
        content
            .background { materialBackground }
            .overlay { materialBorder }
            .shadow(color: materialShadowColor, radius: 5, y: 2)
        // Keep the view identity stable, but do not disable the transaction of
        // the complete subtree. Doing so also disabled press, selection and
        // row animations for every control placed inside a glass card.
    }

    @ViewBuilder
    private var materialBackground: some View {
        if !liquidGlassEnabled {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(solidSurfaceColor)
                .allowsHitTesting(false)
        } else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(tint).interactive(interactive),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .opacity(glassPanelOpacity)
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.thinMaterial)
                .opacity(glassPanelOpacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var materialBorder: some View {
        if !liquidGlassEnabled {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.primary.opacity(0.055 + glassPanelOpacity * 0.055), lineWidth: 1)
                .allowsHitTesting(false)
        } else if #available(macOS 26.0, *) {
            EmptyView()
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.primary.opacity(0.04 + glassPanelOpacity * 0.06), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var materialShadowColor: Color {
        guard liquidGlassEnabled else { return .clear }
        if #available(macOS 26.0, *) { return .clear }
        return .black.opacity(0.025 + glassPanelOpacity * 0.04)
    }

    private var solidSurfaceColor: Color {
        let opacity = 0.28 + glassPanelOpacity * 0.64
        return colorScheme == .dark
            ? Color.black.opacity(opacity)
            : Color.white.opacity(opacity)
    }
}

extension View {
    func liquidGlass(radius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint, interactive: interactive))
    }

    func glassControl(radius: CGFloat = 11, tint: Color? = nil) -> some View {
        modifier(GlassControlModifier(radius: radius, tint: tint))
    }
}

private struct GlassControlModifier: ViewModifier {
    @Environment(\.glassPanelOpacity) private var glassPanelOpacity
    let radius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                Color.white.opacity(0.035 * glassPanelOpacity),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .liquidGlass(radius: radius, tint: tint, interactive: true)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.12 + 0.26 * glassPanelOpacity),
                                .white.opacity(0.03 + 0.05 * glassPanelOpacity),
                                .black.opacity(0.03 + 0.05 * glassPanelOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.02 + 0.035 * glassPanelOpacity), radius: 4, y: 2)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var minHeight: CGFloat = 34
    var horizontalPadding: CGFloat = 12
    var radius: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .foregroundStyle(.primary)
            // Interactive native glass already owns the pointer-down response.
            // Rebuilding its tint and adding another scale animation on every
            // press caused a visibly delayed, double-settling click.
            .glassControl(radius: radius, tint: tint?.opacity(0.12))
            .brightness(configuration.isPressed ? -0.025 : 0)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.075), value: configuration.isPressed)
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    var radius: CGFloat = 10
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .glassControl(radius: radius, tint: tint?.opacity(0.1))
            .brightness(configuration.isPressed ? -0.03 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.075), value: configuration.isPressed)
    }
}

struct GlassSegmentButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                selected ? Color.primary.opacity(0.065) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .glassControl(
                radius: 10,
                tint: selected ? Color.primary.opacity(0.035) : Color.clear
            )
            .opacity(selected ? 1 : 0.82)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.075), value: configuration.isPressed)
    }
}

/// Keeps pointer tracking on AppKit's native control so expensive SwiftUI glass
/// hierarchies are not rebuilt for every mouse event. Audio updates are sampled
/// at 30 Hz while dragging and the exact final value is always committed. The
/// native thumb still tracks every pointer event at the display refresh rate.
struct FluidSlider: NSViewRepresentable {
    let value: Double
    var range: ClosedRange<Double> = 0...1
    var onEditingChanged: (Bool) -> Void = { _ in }
    let onChange: (Double) -> Void

    init(
        value: Double,
        in range: ClosedRange<Double> = 0...1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        onChange: @escaping (Double) -> Void
    ) {
        self.value = value
        self.range = range
        self.onEditingChanged = onEditingChanged
        self.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEditingChanged: onEditingChanged, onChange: onChange)
    }

    func makeNSView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = clamped(value)
        slider.isContinuous = true
        slider.controlSize = .regular
        slider.focusRingType = .none
        slider.isEnabled = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.onTrackingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.trackingChanged(editing)
        }
        slider.onCommit = { [weak coordinator = context.coordinator] finalValue in
            coordinator?.commit(finalValue)
        }
        return slider
    }

    func updateNSView(_ slider: TrackingSlider, context: Context) {
        context.coordinator.onEditingChanged = onEditingChanged
        context.coordinator.onChange = onChange
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        guard !context.coordinator.isTracking else { return }
        let nextValue = clamped(value)
        if abs(slider.doubleValue - nextValue) > 0.0005 {
            slider.doubleValue = nextValue
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    final class Coordinator: NSObject {
        var onEditingChanged: (Bool) -> Void
        var onChange: (Double) -> Void
        private let limiter = VolumeEventLimiter(updatesPerSecond: 60)
        private(set) var isTracking = false

        init(
            onEditingChanged: @escaping (Bool) -> Void,
            onChange: @escaping (Double) -> Void
        ) {
            self.onEditingChanged = onEditingChanged
            self.onChange = onChange
        }

        @objc func valueChanged(_ sender: NSSlider) {
            if isTracking {
                limiter.emit(sender.doubleValue, action: onChange)
            } else {
                // Keyboard and accessibility changes are discrete, so they do
                // not need drag throttling.
                limiter.commit(sender.doubleValue, action: onChange)
            }
        }

        func trackingChanged(_ editing: Bool) {
            isTracking = editing
            onEditingChanged(editing)
        }

        func commit(_ value: Double) {
            limiter.commit(value, action: onChange)
        }
    }

    final class TrackingSlider: NSSlider {
        var onTrackingChanged: ((Bool) -> Void)?
        var onCommit: ((Double) -> Void)?
        private var isPointerTracking = false

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            isPointerTracking = true
            onTrackingChanged?(true)

            // Let NSSlider own its native tracking session. Manually handling
            // mouseDown/Dragged/Up without calling super left the control out
            // of AppKit's tracking loop: clicks could be ignored and drags
            // could be delivered to a neighbouring representable. The action
            // is already throttled by Coordinator, so native tracking remains
            // smooth without rebuilding SwiftUI on every mouse event.
            super.mouseDown(with: event)
            finishPointerTracking()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // SwiftUI can rebuild the surrounding material while the pointer
            // is down. Never leave the shared interaction counter latched if
            // the native control is detached during that rebuild.
            if window == nil, isPointerTracking {
                finishPointerTracking()
            }
        }

        private func finishPointerTracking() {
            onCommit?(doubleValue)
            onTrackingChanged?(false)
            isPointerTracking = false
        }

    }
}

/// Small reference-type limiter shared by the linear and circular controls.
/// It intentionally has no published state: pointer rendering stays local to
/// the control while audio I/O receives a stable stream of useful updates.
final class VolumeEventLimiter {
    private let minimumInterval: CFTimeInterval
    private var lastEmission = -Double.infinity

    init(updatesPerSecond: Double) {
        minimumInterval = 1 / max(updatesPerSecond, 1)
    }

    func emit(_ value: Double, action: (Double) -> Void) {
        let now = CACurrentMediaTime()
        guard now - lastEmission >= minimumInterval else { return }
        lastEmission = now
        action(value)
    }

    func commit(_ value: Double, action: (Double) -> Void) {
        lastEmission = CACurrentMediaTime()
        action(value)
    }
}
