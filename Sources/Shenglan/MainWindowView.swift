import AppKit
import CoreAudio
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsExpandedWindowBrand = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.35)
            navigationBar
            ZStack {
                content
                    .id(audio.selectedSection)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.12), value: audio.selectedSection)
        }
        .id("language-\(audio.language.rawValue)")
        // A custom image must live in SwiftUI's background slot instead of a
        // sibling ZStack layer. That makes the visual stacking contract
        // explicit and prevents the image/blur backing view from ever winning
        // hit testing over settings controls.
        .background {
            ThemeBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .frame(minWidth: 1040, minHeight: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .font(ShenglanTypography.body)
        .tint(controlTint)
        .foregroundStyle(.primary)
        .transaction(value: colorScheme) { transaction in
            // A theme switch is an immediate appearance update, not a page
            // transition. Prevent material snapshots from cross-fading at
            // different times across the hierarchy.
            transaction.disablesAnimations = true
        }
        .alert(
            L10n.tr("音合流提示"),
            isPresented: Binding(
                get: { audio.errorMessage != nil },
                set: { if !$0 { audio.errorMessage = nil } }
            )
        ) {
            Button(L10n.tr("知道了")) { audio.errorMessage = nil }
        } message: {
            Text(audio.errorMessage ?? "")
        }
    }

    private var controlTint: Color {
        colorScheme == .dark ? .white : .black
    }

    private var titleBar: some View {
        ZStack(alignment: .leading) {
            WindowDragArea()

            // The compact brand belongs only to the expanded-window title bar.
            // A width threshold would incorrectly show it after an ordinary
            // manual resize, so AppKit supplies the real zoom/full-screen state.
            WindowExpandedStateObserver(isExpanded: $showsExpandedWindowBrand)
                .allowsHitTesting(false)

        if showsExpandedWindowBrand {
            HStack(spacing: 8) {
                ShenglanIcon(size: 26)
                Text(L10n.tr("音合流", language: audio.language))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            // Expanded windows no longer need to reserve the traffic-light
            // area. Keep the brand on the same 28 pt left safe line as the
            // navigation and workspace below it.
            .padding(.leading, 28)
            .allowsHitTesting(false)
        }
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    private var navigationBar: some View {
        HStack {
            ControllerSectionSlider(selection: $audio.selectedSection)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    audio.selectedSection = .settings
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: permissionSymbol)
                        .foregroundStyle(permissionColor)
                    Text(permissionLabel)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(GlassButtonStyle(minHeight: 36, horizontalPadding: 12, radius: 12))
        }
        .padding(.horizontal, 28)
        .frame(height: 64)
    }

    @ViewBuilder
    private var content: some View {
        switch audio.selectedSection {
        case .mixer:
            MixerWorkspaceView()
        case .devices:
            DeviceWorkspaceView()
        case .settings:
            SettingsWorkspaceView()
        }
    }

    private var permissionLabel: String {
        switch audio.systemAudioPermissionGranted {
        case true: L10n.tr("权限已授权")
        case false: L10n.tr("权限未授权")
        case nil: L10n.tr("检查系统权限")
        }
    }

    private var permissionSymbol: String {
        switch audio.systemAudioPermissionGranted {
        case true: "checkmark.circle.fill"
        case false: "exclamationmark.triangle.fill"
        case nil: "lock.shield"
        }
    }

    private var permissionColor: Color {
        switch audio.systemAudioPermissionGranted {
        case true: .green
        case false: .orange
        case nil: .secondary
        }
    }
}

private struct ControllerSectionSlider: View {
    @Binding var selection: ControllerSection
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.glassPanelOpacity) private var glassPanelOpacity
    @Environment(\.colorScheme) private var colorScheme

    private let width: CGFloat = 340
    private let height: CGFloat = 44
    private let inset: CGFloat = 3
    private var sections: [ControllerSection] { ControllerSection.allCases }
    private var segmentWidth: CGFloat { (width - inset * 2) / CGFloat(sections.count) }
    private var selectedIndex: Int { sections.firstIndex(of: selection) ?? 0 }

    var body: some View {
        Group {
            if liquidGlassEnabled {
                if #available(macOS 26.0, *) {
                    nativeLiquidGlassSlider
                } else {
                    fallbackGlassSlider
                }
            } else {
                fallbackGlassSlider
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .simultaneousGesture(tabDragGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("控制器页面"))
        // Theme changes are state changes, not navigation motion.  In
        // particular, do not let AppKit cross-fade the glass snapshot after
        // the rest of the window has already switched appearance.
        .animation(nil, value: colorScheme)
    }

    @available(macOS 26.0, *)
    private var nativeLiquidGlassSlider: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tabSurfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tabBorderColor, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.075), radius: 8, y: 3)

            // Keep the specular glass edge, but paint the resolved light/dark
            // surface explicitly.  A raw SwiftUI `glassEffect` here owns an
            // independent AppKit appearance cross-fade; that was the lone
            // white bar left visible during a dark-theme switch.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tabHighlightColor, lineWidth: 0.7)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selectedTabSurfaceColor)
                    .frame(width: segmentWidth, height: height - inset * 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(tabBorderColor, lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.11), radius: 7, y: 3)
                    .offset(x: CGFloat(selectedIndex) * segmentWidth)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.14), value: selectedIndex)

            HStack(spacing: 0) {
                ForEach(sections) { section in
                    tabButton(section)
                }
            }
            .padding(.horizontal, inset)
            .zIndex(10)
        }
    }

    private var fallbackGlassSlider: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tabSurfaceColor)
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tabBorderColor, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.075), radius: 8, y: 3)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selectedTabSurfaceColor)
                .frame(width: segmentWidth, height: height - inset * 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(tabBorderColor, lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.11), radius: 7, y: 3)
                .offset(x: inset + CGFloat(selectedIndex) * segmentWidth)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.14), value: selectedIndex)

            HStack(spacing: 0) {
                ForEach(sections) { section in
                    tabButton(section)
                }
            }
            .padding(.horizontal, inset)
        }
    }

    private var tabSurfaceColor: Color {
        if liquidGlassEnabled {
            return colorScheme == .dark
                ? Color(white: 0.115).opacity(0.30 + 0.66 * glassPanelOpacity)
                : Color.white.opacity(0.22 + 0.50 * glassPanelOpacity)
        }
        return colorScheme == .dark
            ? Color.black.opacity(0.30 + 0.64 * glassPanelOpacity)
            : Color.white.opacity(0.30 + 0.64 * glassPanelOpacity)
    }

    private var selectedTabSurfaceColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055 + 0.065 * glassPanelOpacity)
            : Color.black.opacity(0.035 + 0.055 * glassPanelOpacity)
    }

    private var tabBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07 + 0.08 * glassPanelOpacity)
            : Color.black.opacity(0.05 + 0.06 * glassPanelOpacity)
    }

    private var tabHighlightColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045 + 0.075 * glassPanelOpacity)
            : Color.white.opacity(0.18 + 0.40 * glassPanelOpacity)
    }

    private func tabButton(_ section: ControllerSection) -> some View {
        Button {
            // Keep the page switch out of the animation transaction. Only the
            // single glass indicator above animates; the destination page does
            // not re-render through an expensive glass transition.
            withAnimation(.easeOut(duration: 0.14)) {
                selection = section
            }
        } label: {
            Text(section.displayName)
                .font(selection == section ? ShenglanTypography.navigationSelected : ShenglanTypography.navigation)
                .foregroundStyle(selection == section ? .primary : .secondary)
                .frame(width: segmentWidth, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tabDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let rawIndex = Int((value.location.x - inset) / segmentWidth)
                let index = min(max(rawIndex, 0), sections.count - 1)
                guard sections[index] != selection else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    selection = sections[index]
                }
            }
    }
}

private struct MixerWorkspaceView: View {
    @EnvironmentObject private var audio: AudioController

    var body: some View {
        HStack(spacing: 18) {
            SystemVolumeDock()
                .frame(width: 380)
            ActiveAudioList()
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

private struct SystemVolumeDock: View {
    @EnvironmentObject private var audio: AudioController

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                dockContent(compact: geometry.size.height < 780)
                    .frame(width: 380, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .liquidGlass(radius: 20)
    }

    private func dockContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.tr("系统输出"))
                .font(ShenglanTypography.sectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 24)
            .padding(.bottom, compact ? 8 : 20)

            FullWidthDeviceMenu(
                title: "系统输出设备",
                selectedID: audio.selectedOutputID,
                devices: audio.outputDevices,
                onSelect: audio.selectOutput
            )

            Spacer().frame(height: compact ? 10 : 27)

            CircularVolumeControl(
                value: audio.masterVolume,
                muted: audio.masterMuted,
                onEditingChanged: audio.setUserInteractionActive,
                onChange: audio.setMasterVolume
            )
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .allowsHitTesting(audio.selectedOutputSupportsVolume)
            .opacity(audio.selectedOutputSupportsVolume ? 1 : 0.5)

            HStack(spacing: 10) {
                Button { audio.setMasterVolume(0) } label: {
                    Image(systemName: "speaker.wave.1.fill")
                }
                .buttonStyle(GlassIconButtonStyle(size: 28, radius: 9))
                .disabled(!audio.selectedOutputSupportsVolume)

                FluidSlider(
                    value: audio.masterMuted ? 0 : audio.masterVolume,
                    onEditingChanged: audio.setUserInteractionActive,
                    onChange: audio.setMasterVolume
                )
                    .frame(width: 205)
                    .disabled(!audio.selectedOutputSupportsVolume)

                Button { audio.setMasterVolume(1) } label: {
                    Image(systemName: "speaker.wave.3.fill")
                }
                .buttonStyle(GlassIconButtonStyle(size: 28, radius: 9))
                .disabled(!audio.selectedOutputSupportsVolume)
            }
            .frame(width: 320, height: 28)
            .padding(.top, compact ? 0 : 7)

            if !audio.selectedOutputSupportsVolume {
                Text(L10n.tr("当前输出设备不支持由 Core Audio 调节系统音量"))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 320, alignment: .center)
                    .padding(.top, 8)
            }

            Divider()
                .frame(width: 320)
                .padding(.top, compact ? 10 : 40)
                .padding(.bottom, compact ? 10 : 29)

            devicePicker(
                title: "默认输出设备",
                selectedID: audio.selectedOutputID,
                devices: audio.outputDevices,
                onSelect: audio.selectOutput,
                compact: compact
            )

            Divider()
                .frame(width: 320)
                .padding(.top, compact ? 14 : 26)
                .padding(.bottom, compact ? 14 : 30)

            devicePicker(
                title: "默认输入设备",
                selectedID: audio.selectedInputID,
                devices: audio.inputDevices,
                onSelect: audio.selectInput,
                compact: compact
            )

            // The annotated 27 px gap is a rendered Retina-pixel target.
            // Fourteen SwiftUI points render to about 28 physical pixels while
            // remaining fixed when the window is compact.
            Spacer()
                .frame(height: 14)

            Button { audio.selectedSection = .devices } label: {
                HStack {
                    Label(L10n.tr("设备与音量控制"), systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.horizontal, 15)
                .frame(width: 320, height: 60)
            }
            .buttonStyle(GlassButtonStyle(minHeight: 60, horizontalPadding: 0, radius: 14))
        }
        .padding(.horizontal, 30)
        .padding(.top, compact ? 14 : 35)
        .padding(.bottom, compact ? 14 : 45)
    }

    private func devicePicker(
        title: String,
        selectedID: AudioObjectID,
        devices: [AudioDeviceModel],
        onSelect: @escaping (AudioObjectID) -> Void,
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 17) {
            Text(L10n.tr(title)).font(ShenglanTypography.bodyStrong).foregroundStyle(.secondary)
            FullWidthDeviceMenu(
                title: title,
                selectedID: selectedID,
                devices: devices,
                onSelect: onSelect
            )
        }
    }
}

private struct FullWidthDeviceMenu: View {
    let title: String
    let selectedID: AudioObjectID
    let devices: [AudioDeviceModel]
    let onSelect: (AudioObjectID) -> Void

    private var selectedDevice: AudioDeviceModel? { devices.first { $0.id == selectedID } }

    var body: some View {
        return Menu {
            ForEach(devices) { device in
                Button { onSelect(device.id) } label: {
                    Label(device.name, systemImage: device.symbol)
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: selectedDevice?.symbol ?? "hifispeaker")
                    .frame(width: 20)
                Text(selectedDevice?.name ?? L10n.tr("未检测到设备"))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(ShenglanTypography.control)
            .padding(.horizontal, 16)
            .frame(width: 320, height: 48)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 320, height: 48)
        .glassControl(radius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(title)
    }
}

private struct CircularVolumeControl: View {
    @Environment(\.colorScheme) private var colorScheme
    let value: Double
    let muted: Bool
    let onEditingChanged: (Bool) -> Void
    let onChange: (Double) -> Void

    @State private var localValue: Double
    @State private var isEditing = false
    @State private var eventLimiter = VolumeEventLimiter(updatesPerSecond: 60)

    private let size: CGFloat = 200
    private let lineWidth: CGFloat = 10
    private let knobSize: CGFloat = 28
    private let startDegrees = 135.0
    private let sweepDegrees = 270.0

    init(
        value: Double,
        muted: Bool,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        onChange: @escaping (Double) -> Void
    ) {
        self.value = value
        self.muted = muted
        self.onEditingChanged = onEditingChanged
        self.onChange = onChange
        _localValue = State(initialValue: value)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.primary.opacity(0.075),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(startDegrees))
                .frame(width: trackDiameter, height: trackDiameter)

            Circle()
                .trim(from: 0, to: max(0, min(0.75, displayedValue * 0.75)))
                .stroke(
                    Color.primary.opacity(0.42),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(startDegrees))
                .frame(width: trackDiameter, height: trackDiameter)

            VStack(spacing: 15) {
                Image(systemName: muted || displayedValue < 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.tr("\(Int(displayedValue * 100))%"))
                    .font(ShenglanTypography.sectionTitle.monospacedDigit())
            }

            Circle()
                // Keep the knob on the same resolved theme pass as the arc and
                // the rest of the controller. A raw Material here owns an
                // independent AppKit appearance transition and can leave one
                // stale light/dark frame during a theme switch.
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.18).opacity(0.98)
                        : Color.white.opacity(0.96)
                )
                .frame(width: knobSize, height: knobSize)
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .offset(knobOffset)
        }
        .frame(width: size, height: size)
        .animation(nil, value: colorScheme)
        .contentShape(Rectangle())
        // ScrollView's pan gesture used to win the race against SwiftUI's
        // DragGesture, so the dial looked interactive but frequently could not
        // be dragged. A native tracking surface owns mouseDown/drag/up for the
        // complete dial and updates the value without layout animation.
        .overlay {
            CircularVolumeTrackingSurface(
                onBegan: beginTracking,
                onChanged: continueTracking,
                onEnded: endTracking
            )
            .frame(width: size, height: size)
        }
        .onChange(of: value) { _, newValue in
            guard !isEditing else { return }
            localValue = newValue
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("系统主音量"))
        .accessibilityValue("\(Int(displayedValue * 100))%")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.05 : -0.05
            onChange(max(0, min(1, currentValue + delta)))
        }
    }

    private var currentValue: Double { isEditing ? localValue : value }
    private var displayedValue: Double { muted ? 0 : max(0, min(1, currentValue)) }
    private var trackDiameter: CGFloat { size - knobSize }

    private var knobOffset: CGSize {
        let angle = (startDegrees + sweepDegrees * displayedValue) * .pi / 180
        let radius = trackDiameter / 2
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    private func beginTracking(at point: CGPoint) {
        localValue = value
        isEditing = true
        onEditingChanged(true)
        continueTracking(at: point)
    }

    private func continueTracking(at point: CGPoint) {
        let nextValue = value(for: point)
        localValue = nextValue
        eventLimiter.emit(nextValue, action: onChange)
    }

    private func endTracking(at point: CGPoint) {
        let finalValue = value(for: point)
        localValue = finalValue
        eventLimiter.commit(finalValue, action: onChange)
        isEditing = false
        onEditingChanged(false)
    }

    private func value(for point: CGPoint) -> Double {
        let center = CGPoint(x: size / 2, y: size / 2)
        var degrees = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if degrees < 0 { degrees += 360 }

        let wrappedEnd = (startDegrees + sweepDegrees).truncatingRemainder(dividingBy: 360)
        if degrees >= startDegrees {
            return min(1, (degrees - startDegrees) / sweepDegrees)
        }
        if degrees <= wrappedEnd {
            return min(1, (degrees + 360 - startDegrees) / sweepDegrees)
        }

        // The 90-degree opening is not an active track. Clamp a pointer in
        // that gap to the nearest endpoint. Previously every point just below
        // the 0% endpoint was unwrapped past 360 degrees and became 100%, so a
        // tiny movement at zero caused a full-volume jump.
        let gapMidpoint = (wrappedEnd + startDegrees) / 2
        return degrees < gapMidpoint ? 1 : 0
    }
}

private struct CircularVolumeTrackingSurface: NSViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onBegan = onBegan
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    final class TrackingView: NSView {
        var onBegan: (CGPoint) -> Void = { _ in }
        var onChanged: (CGPoint) -> Void = { _ in }
        var onEnded: (CGPoint) -> Void = { _ in }

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            onBegan(convert(event.locationInWindow, from: nil))
        }

        override func mouseDragged(with event: NSEvent) {
            onChanged(convert(event.locationInWindow, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            onEnded(convert(event.locationInWindow, from: nil))
        }
    }
}

private struct ActiveAudioList: View {
    @EnvironmentObject private var audio: AudioController
    @State private var selectedTab: ApplicationListTab = .all

    private var allMuted: Bool {
        !audio.runningApplications.isEmpty && audio.runningApplications.allSatisfy(\.isMuted)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                        Text(L10n.tr("音频应用（\(audio.runningApplications.count)）")).font(ShenglanTypography.sectionTitle)
                    }
                    Spacer()
                    if !audio.runningApplications.isEmpty {
                        Button { audio.setAllActiveMuted(!allMuted) } label: {
                            Label(allMuted ? L10n.tr("取消全部静音") : L10n.tr("全部静音"), systemImage: allMuted ? "speaker.wave.2" : "speaker.slash")
                                .font(ShenglanTypography.control)
                                .frame(minWidth: 92, minHeight: 34)
                        }
                        .buttonStyle(GlassButtonStyle(minHeight: 34, horizontalPadding: 10, radius: 11))
                        .disabled(audio.systemAudioPermissionGranted == false)
                        .opacity(audio.systemAudioPermissionGranted == false ? 0.5 : 1)
                        .accessibilityHint(audio.systemAudioPermissionGranted == false ? L10n.tr("请先在权限中心允许系统音频录制") : "")
                    }
                }

                ApplicationListTabBar(selection: $selectedTab)
                    .environmentObject(audio)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
            .frame(minHeight: 112)

            Divider().opacity(0.35)

            if audio.runningApplications.isEmpty {
                ContentUnavailableView {
                    Label(L10n.tr("当前没有音频应用"), systemImage: "waveform.slash")
                } description: {
                    Text(L10n.tr("应用播放声音后会加入这里；暂停时保留，只有退出应用后才会消失。"))
                } actions: {
                    Button(L10n.tr("立即刷新")) { audio.refreshProcesses(force: true) }
                        .buttonStyle(GlassButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                applicationContent
            }

        }
        .liquidGlass(radius: 20)
    }

    @ViewBuilder
    private var applicationContent: some View {
        if let group = selectedTab.orderGroup {
            let items = audio.orderedApplications(for: group)
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: group.symbol)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(group == .favorites ? L10n.tr("还没有收藏应用") : L10n.tr("当前没有音频应用"))
                        .font(ShenglanTypography.bodyStrong)
                    Text(group == .favorites ? L10n.tr("点击应用最左侧的星标，即可固定到收藏页签。") : L10n.tr("应用启动并产生过音频后，会自动归入这里。"))
                        .font(ShenglanTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        groupSection(group, applications: items)
                    }
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(ApplicationOrderGroup.categoryGroups) { group in
                        let items = audio.orderedApplications(for: group)
                        if !items.isEmpty {
                            groupSection(group, applications: items)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: ApplicationOrderGroup, applications: [ApplicationMixState]) -> some View {
        ApplicationGroupHeader(group: group, count: applications.count)
            .environmentObject(audio)
        Divider().opacity(0.24)
            .padding(.horizontal, 30)
        if !audio.isApplicationGroupCollapsed(group) {
            ForEach(applications) { app in
                ActiveApplicationRow(app: app, orderGroup: group)
                Divider().opacity(0.28)
                    .padding(.leading, 40)
                    .padding(.trailing, 30)
            }
        }
    }
}

private struct ActiveApplicationRow: View {
    @EnvironmentObject private var audio: AudioController
    let app: ApplicationMixState
    let orderGroup: ApplicationOrderGroup
    @State private var reorderDragOffset: CGFloat = 0

    private var controlsAvailable: Bool {
        audio.systemAudioPermissionGranted != false
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = rowMetrics(for: geometry.size.width)
            singleLineRow(metrics: metrics)
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .offset(y: reorderDragOffset)
        .zIndex(reorderDragOffset == 0 ? 0 : 10)
        .accessibilityHint(controlsAvailable ? "" : L10n.tr("请先在权限中心允许系统音频录制"))
    }

    private struct RowMetrics {
        let compact: Bool
        let identityWidth: CGFloat
        let routeWidth: CGFloat
    }

    private func rowMetrics(for width: CGFloat) -> RowMetrics {
        let compact = width < 720
        let identity = compact
            ? min(max(width * 0.25, 130), 185)
            : min(max(width * 0.31, 185), 460)
        let route = compact
            ? min(max(width * 0.18, 95), 125)
            : min(max(width * 0.17, 130), 250)
        return RowMetrics(compact: compact, identityWidth: identity, routeWidth: route)
    }

    private func singleLineRow(metrics: RowMetrics) -> some View {
        let compact = metrics.compact
        return HStack(spacing: compact ? 6 : 7) {
            ApplicationDragHandle(
                app: app,
                group: orderGroup,
                rowStep: compact ? 58 : 64,
                rowOffset: $reorderDragOffset,
                size: compact ? 32 : 34
            )
            .environmentObject(audio)
            applicationIdentity(compact: compact)
                .frame(width: metrics.identityWidth, alignment: .leading)
                .layoutPriority(2)
            muteButton(size: compact ? 30 : 34)
            volumeSlider
                .frame(minWidth: compact ? 60 : 96, maxWidth: .infinity)
                .layoutPriority(1)
            volumeLabel
            routeMenu(width: metrics.routeWidth, height: compact ? 34 : 36)
            moreButton(size: compact ? 30 : 32)
        }
        .padding(.horizontal, compact ? 12 : 16)
        .frame(height: compact ? 58 : 64)
    }

    private func applicationIdentity(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 8) {
            ApplicationFavoriteButton(app: app, size: compact ? 24 : 26)
                .environmentObject(audio)
            AppIconView(image: app.icon, size: compact ? 27 : 29)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(app.isRunningOutput ? Color.green : Color.secondary.opacity(0.55))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                }
            Text(L10n.tr(app.name))
                .font(ShenglanTypography.bodyStrong)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            }
        .accessibilityLabel("\(L10n.tr(app.name))，\(app.category.title)，\(app.isRunningOutput ? L10n.tr("正在发声") : L10n.tr("已暂停"))")
    }

    private func muteButton(size: CGFloat) -> some View {
        Button { audio.setApplicationMuted(id: app.id, muted: !app.isMuted) } label: {
            Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(app.isMuted ? Color.orange : Color.secondary)
        }
        .buttonStyle(GlassIconButtonStyle(size: size, radius: 10))
        .disabled(audio.masterMuted || !controlsAvailable)
        .opacity(audio.masterMuted || !controlsAvailable ? 0.5 : 1)
    }

    private var volumeSlider: some View {
        FluidSlider(
            value: audio.masterMuted || app.isMuted
                ? 0
                : (audio.applicationState(id: app.id)?.volume ?? app.volume),
            onEditingChanged: audio.setUserInteractionActive,
            onChange: { audio.setApplicationVolume(id: app.id, volume: $0) }
        )
        .disabled(!controlsAvailable)
        .opacity(controlsAvailable ? 1 : 0.5)
    }

    private var volumeLabel: some View {
        Text(audio.masterMuted || app.isMuted ? "0%" : "\(Int(app.volume * 100))%")
            .font(ShenglanTypography.caption.monospacedDigit())
            .frame(width: 40, alignment: .trailing)
    }

    private func routeMenu(width: CGFloat, height: CGFloat) -> some View {
        let resolvedDevice = audio.resolvedOutputDevice(for: app)
        let followsSystem = app.routeDeviceUID == nil

        return Menu {
            Button {
                audio.setApplicationRoute(id: app.id, deviceID: nil)
            } label: {
                Label(
                    resolvedDevice.map { "\(L10n.tr("跟随系统输出")) · \($0.name)" } ?? L10n.tr("跟随系统输出"),
                    systemImage: resolvedDevice?.symbol ?? "hifispeaker"
                )
            }
            ForEach(audio.outputDevices) { device in
                Button {
                    audio.setApplicationRoute(id: app.id, deviceID: device.id)
                } label: {
                    Label(device.name, systemImage: device.symbol)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: resolvedDevice?.symbol ?? "hifispeaker.slash")
                    .foregroundStyle(.secondary)
                Text(resolvedDevice?.name ?? (followsSystem ? L10n.tr("输出不可用") : L10n.tr(app.route)))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: width, height: height)
        .glassControl(radius: 11)
        .disabled(!controlsAvailable)
        .opacity(controlsAvailable ? 1 : 0.5)
    }

    private func moreButton(size: CGFloat) -> some View {
        Menu {
            Button {
                audio.toggleApplicationFavorite(app)
            } label: {
                Label(
                    audio.isApplicationFavorite(app) ? L10n.tr("取消收藏") : L10n.tr("加入收藏"),
                    systemImage: audio.isApplicationFavorite(app) ? "star.slash" : "star"
                )
            }
            Button {
                audio.setApplicationMuted(id: app.id, muted: !app.isMuted)
            } label: {
                Label(
                    app.isMuted ? L10n.tr("取消静音") : L10n.tr("立即静音"),
                    systemImage: app.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
            }
            Menu(L10n.tr("音量增强"), systemImage: "waveform.path.ecg") {
                ForEach(1...4, id: \.self) { value in
                    Button {
                        audio.setApplicationBoost(id: app.id, boost: value)
                    } label: {
                        if app.boost == value {
                            Label(L10n.tr("\(value)×"), systemImage: "checkmark")
                        } else {
                            Text(L10n.tr("\(value)×"))
                        }
                    }
                }
            }
            Divider()
            Button {
                audio.scheduleTimedMute(id: app.id, seconds: 15 * 60)
            } label: {
                Label(L10n.tr("15 分钟后静音"), systemImage: "timer")
            }
            Button {
                audio.scheduleTimedMute(id: app.id, seconds: 30 * 60)
            } label: {
                Label(L10n.tr("30 分钟后静音"), systemImage: "timer")
            }
            Button {
                audio.cancelTimedMute(id: app.id)
            } label: {
                Label(L10n.tr("取消定时静音"), systemImage: "timer.square")
            }
            Divider()
            Button {
                audio.resetApplicationControls(id: app.id)
            } label: {
                Label(L10n.tr("恢复默认"), systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: size, height: size)
        .glassControl(radius: 10, tint: Color.primary.opacity(0.018))
        .accessibilityLabel(L10n.tr("更多控制"))
    }
}
