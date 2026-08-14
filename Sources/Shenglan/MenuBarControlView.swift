import AppKit
import CoreAudio
import SwiftUI

struct MenuBarControlView: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: ApplicationListTab = .all

    private var panelGlassTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.42)
    }

    private var menuApplicationListHeight: CGFloat {
        guard audio.applicationCount(for: selectedTab) > 0 else { return 78 }

        let groups = selectedTab.orderGroup.map { [$0] } ?? ApplicationOrderGroup.categoryGroups
        var contentHeight: CGFloat = 0
        var elementCount = 0

        for group in groups {
            let applications = audio.orderedApplications(for: group)
            guard !applications.isEmpty else { continue }

            contentHeight += 34
            elementCount += 1

            if !audio.isApplicationGroupCollapsed(group) {
                contentHeight += CGFloat(applications.count) * 48
                elementCount += applications.count
            }
        }

        contentHeight += CGFloat(max(0, elementCount - 1)) * 6
        return min(max(contentHeight, 44), 360)
    }

    private var minimalApplicationListHeight: CGFloat {
        guard !audio.runningApplications.isEmpty else { return 70 }
        return min(CGFloat(audio.runningApplications.count) * 44, 264)
    }

    var body: some View {
        Group {
            switch audio.menuBarPopoverStyle {
            case .minimal:
                minimalPopover
            case .full:
                fullPopover
            }
        }
        .font(ShenglanTypography.body)
        .background {
            ThemeBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var fullPopover: some View {
        VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ShenglanIcon(size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("音合流", language: audio.language)).font(ShenglanTypography.sectionTitle)
                        Text(L10n.tr("系统与应用声音", language: audio.language)).font(ShenglanTypography.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { audio.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(GlassIconButtonStyle(size: 34, radius: 10))
                    Button { openMain(.settings) } label: { Image(systemName: "gearshape.fill") }
                        .buttonStyle(GlassIconButtonStyle(size: 34, radius: 10))
                }

                VStack(spacing: 10) {
                    HStack {
                        Text(L10n.tr("系统音量")).font(ShenglanTypography.bodyStrong)
                        Spacer()
                        Text(audio.masterMuted ? L10n.tr("已静音") : "\(Int(audio.masterVolume * 100))%")
                            .font(ShenglanTypography.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Button { audio.setMasterMuted(!audio.masterMuted) } label: {
                            Image(systemName: audio.masterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .buttonStyle(GlassIconButtonStyle(size: 32, radius: 10))
                        .disabled(!audio.selectedOutputSupportsVolume)
                        FluidSlider(
                            value: audio.masterMuted ? 0 : audio.masterVolume,
                            onEditingChanged: audio.setUserInteractionActive,
                            onChange: audio.setMasterVolume
                        )
                        .disabled(!audio.selectedOutputSupportsVolume)
                    }
                    HStack(spacing: 8) {
                        deviceMenu(
                            title: "输出",
                            symbol: "speaker.wave.2.fill",
                            selectedID: audio.selectedOutputID,
                            devices: audio.outputDevices,
                            onSelect: audio.selectOutput
                        )
                        deviceMenu(
                            title: "输入",
                            symbol: "mic.fill",
                            selectedID: audio.selectedInputID,
                            devices: audio.inputDevices,
                            onSelect: audio.selectInput
                        )
                    }
                }
                .padding(13)
                .liquidGlass(radius: 16, tint: panelGlassTint)

                if audio.runningApplications.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "waveform.slash").foregroundStyle(.secondary)
                        Text(L10n.tr("当前没有音频应用")).font(ShenglanTypography.caption)
                        Text(L10n.tr("播放声音后会加入列表")).font(ShenglanTypography.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(L10n.tr("音频应用")).font(ShenglanTypography.bodyStrong)
                            Spacer()
                            Text(L10n.tr("\(audio.applicationCount(for: selectedTab)) 个应用"))
                                .font(ShenglanTypography.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        ApplicationListTabBar(selection: $selectedTab, compact: true)
                            .environmentObject(audio)

                        ScrollView {
                            LazyVStack(spacing: 6) {
                                menuApplicationContent
                            }
                        }
                        .scrollIndicators(.automatic)
                        .frame(height: menuApplicationListHeight)
                    }
                }

                Divider().opacity(0.4)
                HStack {
                    Button { openMain(.mixer) } label: { Label(L10n.tr("打开控制器"), systemImage: "macwindow") }
                        .buttonStyle(GlassButtonStyle(minHeight: 34, horizontalPadding: 10, radius: 10))
                    Spacer()
                    Button(L10n.tr("退出音合流")) { NSApp.terminate(nil) }
                        .buttonStyle(GlassButtonStyle(minHeight: 34, horizontalPadding: 10, radius: 10))
                        .foregroundStyle(.secondary)
                }
                .font(ShenglanTypography.caption)
        }
        .padding(14)
        .frame(width: 640)
    }

    private var minimalPopover: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ShenglanIcon(size: 28)
                Text(L10n.tr("音合流", language: audio.language))
                    .font(ShenglanTypography.sectionTitle)
                Spacer()
                Button { openMain(.settings) } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(GlassIconButtonStyle(size: 28, radius: 8))
                .help(L10n.tr("设置", language: audio.language))
            }

            HStack(spacing: 7) {
                Button { audio.setMasterMuted(!audio.masterMuted) } label: {
                    Image(systemName: audio.masterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(GlassIconButtonStyle(size: 28, radius: 8))
                .disabled(!audio.selectedOutputSupportsVolume)

                Text(L10n.tr("整体音量"))
                    .font(ShenglanTypography.captionStrong)
                    .frame(width: 56, alignment: .leading)

                FluidSlider(
                    value: audio.masterMuted ? 0 : audio.masterVolume,
                    onEditingChanged: audio.setUserInteractionActive,
                    onChange: audio.setMasterVolume
                )
                .disabled(!audio.selectedOutputSupportsVolume)

                Text(audio.masterMuted ? "0%" : "\(Int(audio.masterVolume * 100))%")
                    .font(ShenglanTypography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 7)
            .frame(height: 44)
            .liquidGlass(radius: 12, tint: panelGlassTint)

            if audio.runningApplications.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "waveform.slash")
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("当前没有音频应用"))
                        .font(ShenglanTypography.captionStrong)
                    Text(L10n.tr("播放声音后会加入列表"))
                        .font(ShenglanTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: minimalApplicationListHeight)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(audio.orderedMinimalApplications) { app in
                            MinimalMenuBarApplicationRow(app: app)
                                .environmentObject(audio)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(height: minimalApplicationListHeight)
            }
        }
        .padding(10)
        .frame(width: 336)
    }

    @ViewBuilder
    private var menuApplicationContent: some View {
        if let group = selectedTab.orderGroup {
            let items = audio.orderedApplications(for: group)
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: group.symbol).foregroundStyle(.secondary)
                    Text(group == .favorites ? L10n.tr("还没有收藏应用") : L10n.tr("当前没有音频应用"))
                        .font(ShenglanTypography.captionStrong)
                    if group == .favorites {
                        Text(L10n.tr("点击应用左侧星标即可收藏"))
                            .font(ShenglanTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                menuGroup(group, applications: items)
            }
        } else {
            ForEach(ApplicationOrderGroup.categoryGroups) { group in
                let items = audio.orderedApplications(for: group)
                if !items.isEmpty {
                    menuGroup(group, applications: items)
                }
            }
        }
    }

    @ViewBuilder
    private func menuGroup(_ group: ApplicationOrderGroup, applications: [ApplicationMixState]) -> some View {
        ApplicationGroupHeader(group: group, count: applications.count, compact: true)
            .environmentObject(audio)
        if !audio.isApplicationGroupCollapsed(group) {
            ForEach(applications) { app in
                MenuBarApplicationRow(app: app, orderGroup: group)
                    .environmentObject(audio)
            }
        }
    }

    private func deviceMenu(
        title: String,
        symbol: String,
        selectedID: AudioObjectID,
        devices: [AudioDeviceModel],
        onSelect: @escaping (AudioObjectID) -> Void
    ) -> some View {
        let selected = devices.first { $0.id == selectedID }
        return Menu {
            ForEach(devices) { device in
                Button { onSelect(device.id) } label: {
                    Label(device.name, systemImage: device.symbol)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selected?.symbol ?? symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.tr(title)).font(ShenglanTypography.caption).foregroundStyle(.secondary)
                    Text(selected?.name ?? L10n.tr("未检测到"))
                        .font(ShenglanTypography.captionStrong)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, minHeight: 44)
        .glassControl(radius: 11)
    }

    private func openMain(_ section: ControllerSection) {
        MenuBarPopoverController.shared.closePopover()
        audio.selectedSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MinimalMenuBarApplicationRow: View {
    @EnvironmentObject private var audio: AudioController
    let app: ApplicationMixState
    @State private var reorderDragOffset: CGFloat = 0

    private var current: ApplicationMixState {
        audio.applicationState(id: app.id) ?? app
    }

    private var controlsAvailable: Bool {
        audio.systemAudioPermissionGranted != false
    }

    var body: some View {
        HStack(spacing: 6) {
            MinimalApplicationDragHandle(app: app, rowOffset: $reorderDragOffset)
                .environmentObject(audio)

            AppIconView(image: app.icon, size: 26)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(current.isRunningOutput ? Color.green : Color.secondary.opacity(0.55))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.25))
                }

            Text(L10n.tr(app.name))
                .font(ShenglanTypography.captionStrong)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 78, alignment: .leading)

            Button {
                audio.setApplicationMuted(id: app.id, muted: !current.isMuted)
            } label: {
                Image(systemName: current.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(current.isMuted ? Color.orange : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controlsAvailable)
            .opacity(controlsAvailable ? 1 : 0.5)

            FluidSlider(
                value: audio.masterMuted || current.isMuted ? 0 : current.volume,
                onEditingChanged: audio.setUserInteractionActive,
                onChange: { audio.setApplicationVolume(id: app.id, volume: $0) }
            )
            .frame(minWidth: 64, maxWidth: .infinity)
            .disabled(audio.masterMuted || !controlsAvailable)
            .opacity(audio.masterMuted || !controlsAvailable ? 0.5 : 1)

            Text(audio.masterMuted || current.isMuted ? "0%" : "\(Int(current.volume * 100))%")
                .font(ShenglanTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.2)
                .padding(.leading, 40)
        }
        .contentShape(Rectangle())
        .offset(y: reorderDragOffset)
        .zIndex(reorderDragOffset == 0 ? 0 : 10)
        .accessibilityLabel(
            "\(L10n.tr(app.name))，\(current.isRunningOutput ? L10n.tr("正在发声") : L10n.tr("已暂停"))"
        )
    }
}

private struct MinimalApplicationDragHandle: View {
    @EnvironmentObject private var audio: AudioController
    let app: ApplicationMixState
    @Binding var rowOffset: CGFloat
    @State private var isDragging = false
    @State private var lastTranslationBand = 0
    @State private var committedRows = 0

    private let rowStep: CGFloat = 44
    private let activationDistance: CGFloat = 20

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 28)
            .contentShape(Rectangle())
            .scaleEffect(isDragging ? 1.05 : 1)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            lastTranslationBand = 0
                            committedRows = 0
                            audio.setUserInteractionActive(true)
                        }

                        let band = Int(value.translation.height / activationDistance)
                        if band != lastTranslationBand {
                            let direction = band > lastTranslationBand ? 1 : -1
                            while lastTranslationBand != band {
                                lastTranslationBand += direction
                                if audio.moveMinimalApplication(
                                    preferenceKey: audio.minimalApplicationOrderKey(for: app),
                                    by: direction
                                ) {
                                    committedRows += direction
                                }
                            }
                        }
                        rowOffset = value.translation.height - CGFloat(committedRows) * rowStep
                    }
                    .onEnded { value in
                        if committedRows == 0, abs(value.translation.height) >= 12 {
                            _ = audio.moveMinimalApplication(
                                preferenceKey: audio.minimalApplicationOrderKey(for: app),
                                by: value.translation.height > 0 ? 1 : -1
                            )
                        }
                        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.88)) {
                            rowOffset = 0
                            isDragging = false
                        }
                        lastTranslationBand = 0
                        committedRows = 0
                        audio.setUserInteractionActive(false)
                    }
            )
            .accessibilityAdjustableAction { direction in
                let step: Int
                switch direction {
                case .increment: step = 1
                case .decrement: step = -1
                @unknown default: return
                }
                _ = audio.moveMinimalApplication(
                    preferenceKey: audio.minimalApplicationOrderKey(for: app),
                    by: step
                )
            }
            .accessibilityLabel("\(L10n.tr("拖动调整")) \(L10n.tr(app.name)) \(L10n.tr("的顺序"))")
            .help(L10n.tr("按住并上下拖动调整应用顺序"))
    }
}

private struct MenuBarApplicationRow: View {
    @EnvironmentObject private var audio: AudioController
    let app: ApplicationMixState
    let orderGroup: ApplicationOrderGroup
    @State private var reorderDragOffset: CGFloat = 0

    private var controlsAvailable: Bool {
        audio.systemAudioPermissionGranted != false
    }

    var body: some View {
        HStack(spacing: 7) {
            ApplicationDragHandle(
                app: app,
                group: orderGroup,
                rowStep: 48,
                rowOffset: $reorderDragOffset,
                size: 30,
                showsBackground: false
            )
            .environmentObject(audio)
            ApplicationFavoriteButton(app: app, size: 25)
                .environmentObject(audio)
            AppIconView(image: app.icon, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(app.isRunningOutput ? Color.green : Color.secondary.opacity(0.55))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.25))
                }
            Text(L10n.tr(app.name))
                .font(ShenglanTypography.captionStrong)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 96, idealWidth: 114, maxWidth: 124, alignment: .leading)

            muteButton

            FluidSlider(
                value: audio.masterMuted || app.isMuted
                    ? 0
                    : (audio.applicationState(id: app.id)?.volume ?? app.volume),
                onEditingChanged: audio.setUserInteractionActive,
                onChange: { audio.setApplicationVolume(id: app.id, volume: $0) }
            )
            .frame(minWidth: 64, maxWidth: .infinity)
            .disabled(audio.masterMuted || !controlsAvailable)
            .opacity(audio.masterMuted || !controlsAvailable ? 0.5 : 1)

            Text(audio.masterMuted || app.isMuted ? "0%" : "\(Int(app.volume * 100))%")
                .font(ShenglanTypography.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)

            routeMenu
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 8)
        // NSPopover is already the shared liquid-glass surface. Keep the row
        // completely transparent so the app does not appear to sit on a
        // second white plate inside that surface.
        .background(Color.clear.allowsHitTesting(false))
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.2)
                .padding(.leading, 98)
        }
        .contentShape(Rectangle())
        .offset(y: reorderDragOffset)
        .zIndex(reorderDragOffset == 0 ? 0 : 10)
        .accessibilityLabel("\(L10n.tr(app.name))，\(app.category.title)，\(app.isRunningOutput ? L10n.tr("正在发声") : L10n.tr("已暂停"))")
    }

    private var muteButton: some View {
        Button { audio.setApplicationMuted(id: app.id, muted: !app.isMuted) } label: {
            Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(app.isMuted ? Color.orange : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!controlsAvailable)
        .opacity(controlsAvailable ? 1 : 0.5)
    }

    private var routeMenu: some View {
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
            HStack(spacing: 5) {
                Image(systemName: resolvedDevice?.symbol ?? "hifispeaker.slash")
                Text(resolvedDevice?.name ?? (followsSystem ? L10n.tr("输出不可用") : L10n.tr(app.route)))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(ShenglanTypography.caption)
            .padding(.horizontal, 8)
            .frame(width: 172, height: 30)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 172, height: 30)
        .glassControl(radius: 9)
        .disabled(!controlsAvailable)
    }
}
