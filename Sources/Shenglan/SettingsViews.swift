import AppKit
import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr(title)).font(ShenglanTypography.sectionTitle)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(radius: 18)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "通用"
    case appearance = "外观"
    case permissions = "权限"

    var id: Self { self }
    var displayName: String { L10n.tr(rawValue) }

    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .appearance: "circle.lefthalf.filled"
        case .permissions: "lock.shield.fill"
        }
    }

    var detail: String {
        switch self {
        case .general: L10n.tr("启动与菜单栏")
        case .appearance: L10n.tr("主题与玻璃材质")
        case .permissions: L10n.tr("系统授权状态")
        }
    }
}

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.glassPanelOpacity) private var glassPanelOpacity
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 16) {
            settingsSidebar
                .frame(width: 236)
            settingsDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("设置"))
                    .font(ShenglanTypography.pageTitle)
                Text(L10n.tr("音合流偏好"))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        // Avoid animating the entire glass detail hierarchy.
                        // The selected row updates immediately and only the
                        // lightweight navigation highlight changes.
                        selectedPane = pane
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: pane.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(selectedPane == pane ? .primary : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pane.displayName)
                                    .font(selectedPane == pane ? ShenglanTypography.navigationSelected : ShenglanTypography.navigation)
                                Text(pane.detail)
                                    .font(ShenglanTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if selectedPane == pane {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 58)
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .background(
                            selectedPane == pane ? Color.primary.opacity(0.07) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.primary.opacity(selectedPane == pane ? 0.11 : 0), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Label(L10n.tr("所有设置仅保存在本机"), systemImage: "lock.shield")
                .font(ShenglanTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .liquidGlass(radius: 22)
    }

    private var settingsDetail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 13) {
                    Image(systemName: selectedPane.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 14)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedPane.displayName)
                            .font(ShenglanTypography.pageTitle)
                        Text(selectedPaneDescription)
                            .font(ShenglanTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Group {
                    switch selectedPane {
                    case .general:
                        generalSettings
                    case .appearance:
                        appearanceSettings
                    case .permissions:
                        PermissionCenterView(embedded: true, showsHeader: false)
                    }
                }
                .id(selectedPane)
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(radius: 22)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsGroup(title: "语言") {
                preferenceRow(
                    symbol: "character.bubble.fill",
                    title: "界面语言",
                    detail: "切换整个应用与菜单栏控制器的显示语言。"
                ) {
                    languageMenu
                }
            }

            settingsGroup(title: "启动") {
                preferenceRow(
                    symbol: "power.circle.fill",
                    title: "登录时启动音合流",
                    detail: loginItemDescription
                ) {
                    Toggle(
                        L10n.tr("登录时启动音合流"),
                        isOn: Binding(get: { audio.loginItemEnabled }, set: audio.setLoginItemEnabled)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            settingsGroup(title: "菜单栏") {
                preferenceRow(
                    symbol: audio.menuBarPopoverStyle.symbol,
                    title: "弹层风格",
                    detail: "选择菜单栏弹层的功能密度。"
                ) {
                    popoverStylePicker
                }

                Divider().opacity(0.35)

                preferenceRow(
                    symbol: audio.menuBarIcon.symbol,
                    title: "菜单栏图标",
                    detail: "选择音合流声环、动态扬声器或音量柱。"
                ) {
                    menuBarIconMenu
                }

                Divider().opacity(0.35)

                preferenceRow(
                    symbol: "percent",
                    title: "显示系统音量",
                    detail: "在菜单栏图标旁显示实时系统音量。"
                ) {
                    Toggle(L10n.tr("显示系统音量"), isOn: $audio.showMenuBarVolume)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider().opacity(0.35)

                preferenceRow(
                    symbol: audio.menuBarVolumeStyle.symbol,
                    title: "音量显示样式",
                    detail: "可选择数字、分段、进度条或动态仪表。"
                ) {
                    menuBarVolumeStyleMenu
                        .disabled(!audio.showMenuBarVolume)
                        .opacity(audio.showMenuBarVolume ? 1 : 0.48)
                }
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsGroup(title: "主题") {
                HStack(spacing: 10) {
                    ForEach(ThemeChoice.allCases) { choice in
                        themeOption(choice)
                    }
                }
            }

            settingsGroup(title: "界面材质") {
                preferenceRow(
                    symbol: "circle.lefthalf.filled",
                    title: "macOS 原生液态玻璃",
                    detail: "浅色使用白色玻璃，深色使用黑色玻璃。"
                ) {
                    Toggle(L10n.tr("使用 macOS 原生液态玻璃"), isOn: $audio.useLiquidGlass)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider().opacity(0.35)

                appearanceAdjustmentRow(
                    symbol: "square.on.square",
                    title: "玻璃面板透明度",
                    detail: "调整卡片、按钮与弹层玻璃的透光程度。",
                    value: audio.glassPanelOpacity,
                    range: 0.18...1,
                    valueLabel: "\(Int((audio.glassPanelOpacity * 100).rounded()))%"
                ) { audio.glassPanelOpacity = $0 }
            }

            settingsGroup(title: "自定义主题背景") {
                customThemeBackgroundEditor
            }
        }
    }

    private var customThemeBackgroundEditor: some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image = audio.customThemeBackgroundImage {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .allowsHitTesting(false)
                    } else {
                        LinearGradient(
                            colors: [Color.primary.opacity(0.03), Color.primary.opacity(0.11)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .allowsHitTesting(false)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.58)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        audio.customThemeBackgroundImage == nil
                            ? L10n.tr("尚未选择图片")
                            : L10n.tr("自定义背景已启用")
                    )
                    .font(ShenglanTypography.bodyStrong)
                    .foregroundStyle(.white)
                    Text(audio.customThemeBackgroundName ?? L10n.tr("上传一张图片，让玻璃界面取样你的专属背景。"))
                        .font(ShenglanTypography.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(14)
                .allowsHitTesting(false)
            }
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                    .allowsHitTesting(false)
            )

            HStack(spacing: 10) {
                Toggle(
                    L10n.tr("启用自定义背景"),
                    isOn: Binding(
                        get: { audio.customThemeBackgroundEnabled },
                        set: audio.setCustomThemeBackgroundEnabled
                    )
                )
                .toggleStyle(.switch)
                .disabled(audio.customThemeBackgroundImage == nil)

                Spacer()

                if audio.customThemeBackgroundImage != nil {
                    Button(L10n.tr("移除图片")) { audio.removeCustomThemeBackground() }
                        .buttonStyle(GlassButtonStyle(minHeight: 36, horizontalPadding: 12, radius: 11))
                }

                Button(
                    L10n.tr(audio.customThemeBackgroundImage == nil ? "选择图片" : "更换图片")
                ) {
                    chooseCustomThemeBackground()
                }
                .buttonStyle(GlassButtonStyle(minHeight: 36, horizontalPadding: 12, radius: 11))
            }


            if audio.customThemeBackgroundImage != nil {
                Divider().opacity(0.35)

                appearanceAdjustmentRow(
                    symbol: "photo",
                    title: "背景图片透明度",
                    detail: "调整图片在玻璃下方的显现强度。",
                    value: audio.customThemeBackgroundOpacity,
                    range: 0...1,
                    valueLabel: "\(Int((audio.customThemeBackgroundOpacity * 100).rounded()))%"
                ) { audio.customThemeBackgroundOpacity = $0 }

                Divider().opacity(0.35)

                appearanceAdjustmentRow(
                    symbol: "drop.halffull",
                    title: "背景毛玻璃模糊度",
                    detail: "仅虚化自定义背景图片，不影响文字与控件清晰度。",
                    value: audio.customThemeBackgroundBlur,
                    range: 0...36,
                    valueLabel: "\(Int(audio.customThemeBackgroundBlur.rounded())) pt"
                ) { audio.customThemeBackgroundBlur = $0 }
            }

            Text(L10n.tr("支持 PNG、JPEG、HEIC 与 TIFF，图片会复制并保存在本机。"))
                .font(ShenglanTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseCustomThemeBackground() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择自定义主题背景")
        panel.message = L10n.tr("选择一张会显示在液态玻璃下方的图片。")
        panel.prompt = L10n.tr("选择图片")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try audio.importCustomThemeBackground(from: url)
            } catch {
                audio.errorMessage = error.localizedDescription
            }
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr(title))
                .font(ShenglanTypography.sectionTitle)
            VStack(spacing: 0) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.012 + 0.024 * glassPanelOpacity),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.035 + 0.045 * glassPanelOpacity),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        )
    }

    private func appearanceAdjustmentRow(
        symbol: String,
        title: String,
        detail: String,
        value: Double,
        range: ClosedRange<Double>,
        valueLabel: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .glassControl(radius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr(title))
                    .font(ShenglanTypography.bodyStrong)
                Text(L10n.tr(detail))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 18)

            FluidSlider(value: value, in: range, onChange: onChange)
                .frame(width: 176, height: 24)
                // These rows share the same view type. Give each AppKit slider
                // a stable SwiftUI identity so a conditional background row
                // can never inherit another row's coordinator/callback.
                .id("appearance-slider-\(title)")
                .accessibilityLabel(L10n.tr(title))
                .accessibilityValue(valueLabel)
                .zIndex(1)

            Text(verbatim: valueLabel)
                .font(ShenglanTypography.captionStrong.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var selectedPaneDescription: String {
        switch selectedPane {
        case .general: L10n.tr("管理登录启动和菜单栏显示方式。")
        case .appearance: L10n.tr("选择主题，并控制系统原生液态玻璃。")
        case .permissions: L10n.tr("查看并申请声音控制所需的系统权限。")
        }
    }

    private func preferenceRow<Accessory: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .glassControl(radius: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr(title)).font(ShenglanTypography.bodyStrong)
                Text(L10n.tr(detail))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 18)
            accessory()
                .zIndex(1)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private var menuBarIconMenu: some View {
        Menu {
            ForEach(MenuBarIconChoice.allCases) { choice in
                Button { audio.menuBarIcon = choice } label: {
                    Label(choice.displayName, systemImage: choice.symbol)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: audio.menuBarIcon.symbol)
                Text(audio.menuBarIcon.displayName).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(width: 190, height: 40)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 190, height: 40)
        .glassControl(radius: 11)
    }

    private var popoverStylePicker: some View {
        HStack(spacing: 8) {
            ForEach(MenuBarPopoverStyle.allCases) { style in
                Button {
                    audio.menuBarPopoverStyle = style
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: style.symbol)
                        Text(style.displayName)
                            .lineLimit(1)
                    }
                    .font(ShenglanTypography.control)
                    .frame(width: 94, height: 38)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(GlassSegmentButtonStyle(selected: audio.menuBarPopoverStyle == style))
                .help(
                    L10n.tr(
                        style == .minimal
                            ? "只显示整体音量和各应用音量，可拖动调整顺序。"
                            : "保留设备、分类、收藏、排序与输出路由。"
                    )
                )
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button { audio.language = language } label: {
                    HStack {
                        Text(verbatim: language.nativeName)
                        if audio.language == language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble.fill")
                Text(verbatim: audio.language.nativeName).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(width: 190, height: 40)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 190, height: 40)
        .glassControl(radius: 11)
    }

    private var menuBarVolumeStyleMenu: some View {
        Menu {
            ForEach(MenuBarVolumeStyle.allCases) { style in
                Button { audio.menuBarVolumeStyle = style } label: {
                    Label(style.displayName, systemImage: style.symbol)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: audio.menuBarVolumeStyle.symbol)
                Text(audio.menuBarVolumeStyle.displayName).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(width: 190, height: 40)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 190, height: 40)
        .glassControl(radius: 11)
    }

    private func themeOption(_ choice: ThemeChoice) -> some View {
        Button {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                audio.theme = choice
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: choice.symbol)
                Text(choice.displayName).font(ShenglanTypography.control)
                Spacer(minLength: 0)
                if audio.theme == choice {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(GlassSegmentButtonStyle(selected: audio.theme == choice))
    }

    private var loginItemDescription: String {
        switch audio.loginItemStatus {
        case .enabled: L10n.tr("已允许，登录后音合流会在菜单栏启动。")
        case .requiresApproval: L10n.tr("已提交申请，请前往系统设置的“登录项”完成批准。")
        case .notRegistered: L10n.tr("当前未申请登录时启动。")
        case .notFound: L10n.tr("当前尚未注册登录启动项。开启后会向 macOS 提交申请。")
        @unknown default: L10n.tr("登录启动状态未知。")
        }
    }
}

struct DeviceWorkspaceView: View {
    @EnvironmentObject private var audio: AudioController
    @State private var selectedID: AudioObjectID?

    private var selectedDevice: AudioDeviceModel? {
        audio.devices.first { $0.id == (selectedID ?? audio.selectedOutputID) }
    }

    var body: some View {
        HStack(spacing: 16) {
            deviceSidebar
                .frame(width: 320)

            if let device = selectedDevice {
                deviceDetail(device)
            } else {
                ContentUnavailableView(L10n.tr("没有检测到音频设备"), systemImage: "hifispeaker.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .onAppear {
            audio.refresh()
            selectedID = audio.selectedOutputID != kAudioObjectUnknown ? audio.selectedOutputID : audio.devices.first?.id
        }
        .onChange(of: audio.devices) { _, devices in
            if let selectedID, !devices.contains(where: { $0.id == selectedID }) {
                self.selectedID = audio.selectedOutputID != kAudioObjectUnknown ? audio.selectedOutputID : devices.first?.id
            }
        }
    }

    private var deviceSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("音频设备")).font(ShenglanTypography.pageTitle)
                    Text(L10n.tr("\(audio.devices.count) 个音频端点 · Core Audio 实时更新"))
                        .font(ShenglanTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { audio.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(GlassIconButtonStyle(size: 36, radius: 11))
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    deviceSection(title: "输出设备", devices: audio.outputDevices)
                    deviceSection(title: "输入设备", devices: audio.inputDevices)
                    if !audio.unavailableRememberedDevices.isEmpty {
                        rememberedDeviceSection
                    }
                }
            }
        }
        .padding(20)
        .liquidGlass(radius: 22)
    }

    private func deviceSection(title: String, devices: [AudioDeviceModel]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.tr(title))
                .font(ShenglanTypography.captionStrong)
                .foregroundStyle(.secondary)
            ForEach(devices) { device in
                Button { selectedID = device.id } label: {
                    HStack(spacing: 10) {
                        Image(systemName: device.symbol).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(ShenglanTypography.body).lineLimit(1)
                            Text(device.transportName).font(ShenglanTypography.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.isDefaultOutput || device.isDefaultInput {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 54)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(GlassSegmentButtonStyle(selected: selectedID == device.id))
            }
        }
    }

    private var rememberedDeviceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.tr("最近使用"))
                    .font(ShenglanTypography.captionStrong)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.tr("重新连接后自动恢复"))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(audio.unavailableRememberedDevices.prefix(6)) { device in
                HStack(spacing: 10) {
                    Image(systemName: device.symbol).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(ShenglanTypography.body).lineLimit(1)
                        Text("\(device.transportName) · \(L10n.tr("未连接"))")
                            .font(ShenglanTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                }
                .padding(.horizontal, 11)
                .frame(height: 50)
                .opacity(0.7)
                .glassControl(radius: 12)
            }
        }
    }

    private func deviceDetail(_ device: AudioDeviceModel) -> some View {
        let runtime = audio.deviceRuntimeState(for: device)
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: device.symbol)
                        .font(.system(size: 28))
                        .frame(width: 56, height: 56)
                        .liquidGlass(radius: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(ShenglanTypography.pageTitle)
                        Text(L10n.tr("\(device.manufacturer) · \(device.transportName)"))
                            .font(ShenglanTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if device.isDefaultInput || device.isDefaultOutput {
                        VStack(alignment: .trailing, spacing: 3) {
                            Label(L10n.tr("系统默认"), systemImage: "checkmark.circle.fill")
                                .font(ShenglanTypography.captionStrong)
                                .foregroundStyle(.green)
                            Text(L10n.tr("设备在线"))
                                .font(ShenglanTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { controlCards(for: device, runtime: runtime) }
                    VStack(spacing: 16) { controlCards(for: device, runtime: runtime) }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        formatCard(device, runtime: runtime).frame(minWidth: 300, maxWidth: .infinity)
                        infoCard(device).frame(minWidth: 300, maxWidth: .infinity)
                    }
                    VStack(spacing: 16) {
                        formatCard(device, runtime: runtime)
                        infoCard(device)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(radius: 22)
        .task(id: device.id) {
            audio.refreshDeviceRuntimeState(device.id)
        }
    }

    @ViewBuilder
    private func controlCards(for device: AudioDeviceModel, runtime: AudioDeviceRuntimeState) -> some View {
        if device.isOutput {
            SettingsCard(title: "输出控制") {
                HStack(spacing: 12) {
                    Button { audio.setOutputMuted(!runtime.outputMuted, for: device.id) } label: {
                        Image(systemName: runtime.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(GlassIconButtonStyle(size: 36, radius: 11))
                    .disabled(!runtime.outputSupportsVolume)
                    FluidSlider(
                        value: runtime.outputMuted ? 0 : runtime.outputVolume,
                        onEditingChanged: audio.setUserInteractionActive,
                        onChange: { audio.setOutputVolume($0, for: device.id) }
                    )
                    .disabled(!runtime.outputSupportsVolume)
                    Text(L10n.tr("\(Int((runtime.outputMuted ? 0 : runtime.outputVolume) * 100))%"))
                        .font(ShenglanTypography.caption.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }
                if !device.isDefaultOutput {
                    Button(L10n.tr("设为系统默认输出")) { audio.selectOutput(device.id) }
                        .buttonStyle(GlassButtonStyle())
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity)
        }
        if device.isInput {
            SettingsCard(title: "输入控制") {
                HStack(spacing: 12) {
                    Button { audio.setInputMuted(!runtime.inputMuted, for: device.id) } label: {
                        Image(systemName: runtime.inputMuted ? "mic.slash.fill" : "mic.fill")
                    }
                    .buttonStyle(GlassIconButtonStyle(size: 36, radius: 11))
                    .disabled(!runtime.inputSupportsVolume)
                    FluidSlider(
                        value: runtime.inputVolume,
                        onEditingChanged: audio.setUserInteractionActive,
                        onChange: { audio.setInputVolume($0, for: device.id) }
                    )
                    .disabled(!runtime.inputSupportsVolume)
                    Text(L10n.tr("\(Int(runtime.inputVolume * 100))%"))
                        .font(ShenglanTypography.caption.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }
                if !device.isDefaultInput {
                    Button(L10n.tr("设为系统默认输入")) { audio.selectInput(device.id) }
                        .buttonStyle(GlassButtonStyle())
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity)
        }
    }

    private func formatCard(_ device: AudioDeviceModel, runtime: AudioDeviceRuntimeState) -> some View {
        SettingsCard(title: "音频格式") {
            HStack {
                Text(L10n.tr("采样率"))
                Spacer()
                Picker(L10n.tr("采样率"), selection: sampleRateBinding(for: device)) {
                    ForEach(runtime.availableSampleRates, id: \.self) { rate in
                        Text(rateLabel(rate)).tag(rate)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            HStack { Text(L10n.tr("输入声道")); Spacer(); Text(L10n.tr("\(device.inputChannels)")).foregroundStyle(.secondary) }
            HStack { Text(L10n.tr("输出声道")); Spacer(); Text(L10n.tr("\(device.outputChannels)")).foregroundStyle(.secondary) }
        }
    }

    private func infoCard(_ device: AudioDeviceModel) -> some View {
        SettingsCard(title: "连接信息") {
            HStack { Text(L10n.tr("传输方式")); Spacer(); Text(device.transportName).foregroundStyle(.secondary) }
            HStack {
                Text(L10n.tr("制造商"))
                Spacer()
                Text(device.manufacturer == "未知厂商" ? L10n.tr("未知厂商") : device.manufacturer)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Text(L10n.tr("设备 UID"))
                Spacer()
                Text(device.uid).font(ShenglanTypography.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func sampleRateBinding(for device: AudioDeviceModel) -> Binding<Double> {
        Binding(get: { device.sampleRate }, set: { audio.setSampleRate($0, for: device.id) })
    }

    private func rateLabel(_ rate: Double) -> String {
        rate >= 1000 ? String(format: "%.1f kHz", rate / 1000) : "\(Int(rate)) Hz"
    }
}
