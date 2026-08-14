import AppKit
import SwiftUI

enum EqualizerEditorScope: Identifiable {
    case master
    case application(key: String, name: String, icon: NSImage?)

    var id: String {
        switch self {
        case .master: "master"
        case .application(let key, _, _): "application-\(key)"
        }
    }
}

struct EqualizerEditorSheet: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    let scope: EqualizerEditorScope

    @State private var draftSettings: EqualizerSettings?
    @State private var didAppear = false
    @State private var lastDSPCommitTime = 0.0

    private let dspCommitInterval = 1.0 / 30.0

    private var sourceSettings: EqualizerSettings {
        switch scope {
        case .master:
            audio.masterEqualizer
        case .application(let key, _, _):
            audio.applicationEqualizer(forKey: key)
        }
    }

    private var settings: EqualizerSettings {
        draftSettings ?? sourceSettings
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            presetPanel
            Divider().opacity(0.35)
            EqualizerCurveView(gainsDB: settings.bandGainsDB)
                .frame(height: 76)
                .opacity(settings.isEnabled ? 1 : 0.42)
                .animation(ShenglanMotion.quick, value: settings.isEnabled)
            bandControls
            Divider().opacity(0.35)
            preampControl
            reverbControl
            channelBalanceControl
        }
        .padding(24)
        .frame(width: 780, height: 780)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 8)
        .animation(ShenglanMotion.standard, value: didAppear)
        .background {
            ThemeBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            draftSettings = sourceSettings
            didAppear = true
        }
        .onDisappear {
            audio.setUserInteractionActive(false)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            scopeIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(ShenglanTypography.sectionTitle)
                Text(subtitle)
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            dspStatus

            Toggle(
                L10n.tr("启用"),
                isOn: Binding(
                    get: { settings.isEnabled },
                    set: setEnabled
                )
            )
            .toggleStyle(.switch)

            Button(L10n.tr("重置预设")) { resetEqualizer() }
                .buttonStyle(GlassButtonStyle(minHeight: 34, horizontalPadding: 12, radius: 11))
                .help(L10n.tr("恢复当前预设的默认参数，不影响其他预设记忆"))

            Button(L10n.tr("完成")) { dismiss() }
                .buttonStyle(GlassButtonStyle(minHeight: 34, horizontalPadding: 14, radius: 11))
        }
    }

    private var dspStatus: some View {
        Label(
            settings.isEnabled ? L10n.tr("实时 DSP 已开启") : L10n.tr("旁路直通"),
            systemImage: settings.isEnabled ? "waveform.badge.checkmark" : "arrow.triangle.branch"
        )
        .font(ShenglanTypography.captionStrong)
        .foregroundStyle(settings.isEnabled ? Color.green : Color.secondary)
        .contentTransition(.opacity)
        .animation(ShenglanMotion.quick, value: settings.isEnabled)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var scopeIcon: some View {
        switch scope {
        case .master:
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 42, height: 42)
                .glassControl(radius: 12)
        case .application(_, _, let icon):
            AppIconView(image: icon, size: 40)
        }
    }

    private var title: String {
        switch scope {
        case .master: L10n.tr("总均衡器")
        case .application(_, let name, _): L10n.format("%@ · 应用均衡器", L10n.tr(name))
        }
    }

    private var subtitle: String {
        switch scope {
        case .master:
            L10n.tr("对混音页中的全部音频应用生效")
        case .application:
            L10n.tr("先应用此曲线，再叠加总均衡器")
        }
    }

    private var presetPanel: some View {
        VStack(spacing: 12) {
            presetSection(
                title: L10n.tr("音色预设"),
                systemImage: "slider.horizontal.3",
                presets: EqualizerPreset.tonePresets
            )

            Divider().opacity(0.30)

            presetSection(
                title: L10n.tr("空间场景"),
                systemImage: "theatermasks.fill",
                presets: EqualizerPreset.spatialPresets
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func presetSection(
        title: String,
        systemImage: String,
        presets: [EqualizerPreset]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .lineLimit(1)
            }
            .font(ShenglanTypography.captionStrong)
            .foregroundStyle(.primary)

            HStack(spacing: 6) {
                ForEach(presets) { preset in
                    let selected = settings.preset == preset
                    Button {
                        applyPreset(preset)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: preset.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(height: 15)

                            Text(preset.title)
                                .font(selected ? ShenglanTypography.captionStrong : ShenglanTypography.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.66)
                        }
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                selected
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.primary.opacity(0.035)
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selected
                                    ? Color.accentColor.opacity(0.24)
                                    : Color.primary.opacity(0.045),
                                lineWidth: 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(5)
                        }
                    }
                    .animation(ShenglanMotion.quick, value: selected)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help(
                        preset == .custom
                            ? L10n.tr("自动保存并恢复最近一次自定义设置")
                            : preset.title
                    )
                }
            }
        }
    }

    private var bandControls: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(EqualizerSettings.bandFrequencies.indices, id: \.self) { index in
                EqualizerBandControl(
                    frequency: EqualizerSettings.bandFrequencies[index],
                    gainDB: settings.bandGainsDB[index],
                    onEditingChanged: { handleBandEditingChanged(index: index, active: $0) },
                    onChange: { previewBandGain(index: index, gainDB: $0) }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var preampControl: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("前级余量"))
                    .font(ShenglanTypography.bodyStrong)
                Text(L10n.tr("提升频段时降低前级，可减少削波失真"))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)

            FluidSlider(
                value: settings.preampDB,
                in: EqualizerSettings.preampRange,
                onEditingChanged: handlePreampEditingChanged,
                onChange: previewPreamp
            )
            .frame(height: 20)

            Text(String(format: "%+.1f dB", settings.preampDB))
                .font(ShenglanTypography.caption.monospacedDigit())
                .contentTransition(.numericText(value: settings.preampDB))
                .frame(width: 66, alignment: .trailing)
        }
    }

    private var reverbControl: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("空间强度"))
                    .font(ShenglanTypography.bodyStrong)
                Text(L10n.tr("控制房间与剧场混响的湿声比例"))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)

            FluidSlider(
                value: settings.reverb.wetMix,
                in: 0...0.60,
                onEditingChanged: handleReverbEditingChanged,
                onChange: previewReverbMix
            )
            .frame(height: 20)

            Text("\(Int((settings.reverb.wetMix * 100).rounded()))%")
                .font(ShenglanTypography.caption.monospacedDigit())
                .contentTransition(.numericText(value: settings.reverb.wetMix))
                .frame(width: 66, alignment: .trailing)
        }
    }

    private var channelBalanceControl: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("左右声道平衡"))
                    .font(ShenglanTypography.bodyStrong)
                Text(L10n.tr("只衰减一侧声道，不额外提高音量"))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)

            Text("L")
                .font(ShenglanTypography.captionStrong)
                .foregroundStyle(.secondary)

            FluidSlider(
                value: settings.stereoBalance,
                in: -1...1,
                onEditingChanged: handleStereoBalanceEditingChanged,
                onChange: previewStereoBalance
            )
            .frame(height: 20)
            .accessibilityLabel(L10n.tr("左右声道平衡"))

            Text("R")
                .font(ShenglanTypography.captionStrong)
                .foregroundStyle(.secondary)

            Text(stereoBalanceLabel)
                .font(ShenglanTypography.caption.monospacedDigit())
                .contentTransition(.numericText(value: settings.stereoBalance))
                .frame(width: 66, alignment: .trailing)
        }
    }

    private var stereoBalanceLabel: String {
        let amount = Int((abs(settings.stereoBalance) * 100).rounded())
        if amount == 0 { return L10n.tr("居中") }
        return "\(settings.stereoBalance < 0 ? "L" : "R") \(amount)%"
    }

    private func setEnabled(_ enabled: Bool) {
        var next = settings
        next.isEnabled = enabled
        withAnimation(ShenglanMotion.quick) {
            draftSettings = next
        }
        switch scope {
        case .master:
            audio.setMasterEqualizerEnabled(enabled)
        case .application(let key, _, _):
            audio.setApplicationEqualizerEnabled(key: key, enabled: enabled)
        }
    }

    private func applyPreset(_ preset: EqualizerPreset) {
        var next = settings
        next.apply(preset)
        withAnimation(ShenglanMotion.standard) {
            draftSettings = next
        }
        switch scope {
        case .master:
            audio.setMasterEqualizerPreset(preset)
        case .application(let key, _, _):
            audio.setApplicationEqualizerPreset(key: key, preset: preset)
        }
    }

    private func resetEqualizer() {
        var next = settings
        next.resetCurrentPreset()
        withAnimation(ShenglanMotion.standard) {
            draftSettings = next
        }
        switch scope {
        case .master:
            audio.resetMasterEqualizer()
        case .application(let key, _, _):
            audio.resetApplicationEqualizer(key: key)
        }
    }

    private func previewBandGain(index: Int, gainDB: Double) {
        guard EqualizerSettings.bandFrequencies.indices.contains(index) else { return }
        var next = settings
        next.prepareCurrentPresetForEditing()
        next.bandGainsDB[index] = min(
            max(gainDB, EqualizerSettings.gainRange.lowerBound),
            EqualizerSettings.gainRange.upperBound
        )
        next.saveCurrentPresetProfile()
        draftSettings = next
        commitBandGainIfDue(index: index, gainDB: next.bandGainsDB[index])
    }

    private func handleBandEditingChanged(index: Int, active: Bool) {
        if active {
            audio.setUserInteractionActive(true)
            return
        }
        if EqualizerSettings.bandFrequencies.indices.contains(index) {
            commitBandGain(index: index, gainDB: settings.bandGainsDB[index])
        }
        audio.setUserInteractionActive(false)
    }

    private func commitBandGainIfDue(index: Int, gainDB: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDSPCommitTime >= dspCommitInterval else { return }
        lastDSPCommitTime = now
        commitBandGain(index: index, gainDB: gainDB)
    }

    private func commitBandGain(index: Int, gainDB: Double) {
        switch scope {
        case .master:
            audio.setMasterEqualizerBandGain(index: index, gainDB: gainDB)
        case .application(let key, _, _):
            audio.setApplicationEqualizerBandGain(key: key, index: index, gainDB: gainDB)
        }
    }

    private func previewPreamp(_ preampDB: Double) {
        var next = settings
        next.prepareCurrentPresetForEditing()
        let steppedPreamp = (preampDB * 10).rounded() / 10
        next.preampDB = min(
            max(steppedPreamp, EqualizerSettings.preampRange.lowerBound),
            EqualizerSettings.preampRange.upperBound
        )
        next.saveCurrentPresetProfile()
        draftSettings = next

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDSPCommitTime >= dspCommitInterval else { return }
        lastDSPCommitTime = now
        commitPreamp(next.preampDB)
    }

    private func handlePreampEditingChanged(_ active: Bool) {
        if active {
            audio.setUserInteractionActive(true)
            return
        }
        commitPreamp(settings.preampDB)
        audio.setUserInteractionActive(false)
    }

    private func commitPreamp(_ preampDB: Double) {
        switch scope {
        case .master:
            audio.setMasterEqualizerPreamp(preampDB)
        case .application(let key, _, _):
            audio.setApplicationEqualizerPreamp(key: key, preampDB: preampDB)
        }
    }

    private func previewReverbMix(_ wetMix: Double) {
        var next = settings
        next.prepareCurrentPresetForEditing()
        let clampedMix = min(max((wetMix * 100).rounded() / 100, 0), 0.60)
        if next.reverb.wetMix <= 0.001, clampedMix > 0.001 {
            next.reverb = EqualizerReverbSettings(
                wetMix: clampedMix,
                roomSize: 0.55,
                damping: 0.50,
                preDelayMS: 18,
                stereoWidth: 0.72
            )
        } else {
            next.reverb.wetMix = clampedMix
        }
        next.saveCurrentPresetProfile()
        draftSettings = next

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDSPCommitTime >= dspCommitInterval else { return }
        lastDSPCommitTime = now
        commitReverbMix(next.reverb.wetMix)
    }

    private func handleReverbEditingChanged(_ active: Bool) {
        if active {
            audio.setUserInteractionActive(true)
            return
        }
        commitReverbMix(settings.reverb.wetMix)
        audio.setUserInteractionActive(false)
    }

    private func commitReverbMix(_ wetMix: Double) {
        switch scope {
        case .master:
            audio.setMasterEqualizerReverbMix(wetMix)
        case .application(let key, _, _):
            audio.setApplicationEqualizerReverbMix(key: key, wetMix: wetMix)
        }
    }

    private func previewStereoBalance(_ balance: Double) {
        var next = settings
        next.prepareCurrentPresetForEditing()
        next.stereoBalance = min(max((balance * 100).rounded() / 100, -1), 1)
        next.saveCurrentPresetProfile()
        draftSettings = next

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDSPCommitTime >= dspCommitInterval else { return }
        lastDSPCommitTime = now
        commitStereoBalance(next.stereoBalance)
    }

    private func handleStereoBalanceEditingChanged(_ active: Bool) {
        if active {
            audio.setUserInteractionActive(true)
            return
        }
        commitStereoBalance(settings.stereoBalance)
        audio.setUserInteractionActive(false)
    }

    private func commitStereoBalance(_ balance: Double) {
        switch scope {
        case .master:
            audio.setMasterEqualizerStereoBalance(balance)
        case .application(let key, _, _):
            audio.setApplicationEqualizerStereoBalance(key: key, balance: balance)
        }
    }
}

private struct EqualizerBandControl: View {
    let frequency: Double
    let gainDB: Double
    let onEditingChanged: (Bool) -> Void
    let onChange: (Double) -> Void

    @State private var isEditing = false
    @State private var lastUIEmissionTime = 0.0

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%+.1f", gainDB))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(gainDB == 0 ? .secondary : .primary)
                .contentTransition(.numericText(value: gainDB))
                .frame(width: 46)

            GeometryReader { geometry in
                let trackHeight = max(1, geometry.size.height - 14)
                let knobY = 7 + (1 - normalizedGain) * trackHeight
                let zeroY = 7 + trackHeight / 2

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 4, height: trackHeight)
                        .offset(y: 7)

                    Capsule()
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: 4, height: max(2, abs(knobY - zeroY)))
                        .offset(y: min(knobY, zeroY))

                    Rectangle()
                        .fill(Color.primary.opacity(0.26))
                        .frame(width: 16, height: 1)
                        .offset(y: zeroY)

                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.primary.opacity(0.28), lineWidth: 1))
                        .shadow(
                            color: Color.accentColor.opacity(isEditing ? 0.24 : 0),
                            radius: isEditing ? 7 : 0
                        )
                        .shadow(color: .black.opacity(isEditing ? 0.18 : 0.12), radius: isEditing ? 5 : 3, y: 1)
                        .scaleEffect(isEditing ? 1.18 : 1)
                        .offset(y: knobY - 7)
                }
                .animation(ShenglanMotion.press, value: isEditing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isEditing {
                                isEditing = true
                                onEditingChanged(true)
                            }
                            let normalized = 1 - min(max((value.location.y - 7) / trackHeight, 0), 1)
                            let raw = EqualizerSettings.gainRange.lowerBound +
                                normalized * (EqualizerSettings.gainRange.upperBound - EqualizerSettings.gainRange.lowerBound)
                            let now = ProcessInfo.processInfo.systemUptime
                            guard now - lastUIEmissionTime >= 1.0 / 60.0 else { return }
                            lastUIEmissionTime = now
                            onChange((raw * 10).rounded() / 10)
                        }
                        .onEnded { value in
                            let normalized = 1 - min(max((value.location.y - 7) / trackHeight, 0), 1)
                            let raw = EqualizerSettings.gainRange.lowerBound +
                                normalized * (EqualizerSettings.gainRange.upperBound - EqualizerSettings.gainRange.lowerBound)
                            onChange((raw * 10).rounded() / 10)
                            isEditing = false
                            onEditingChanged(false)
                        }
                )
            }
            .frame(width: 42, height: 210)

            Text(frequencyLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(frequencyLabel) Hz")
        .accessibilityValue(String(format: "%+.1f dB", gainDB))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.5 : -0.5
            onEditingChanged(true)
            onChange(min(max(gainDB + delta, EqualizerSettings.gainRange.lowerBound), EqualizerSettings.gainRange.upperBound))
            onEditingChanged(false)
        }
    }

    private var normalizedGain: Double {
        (gainDB - EqualizerSettings.gainRange.lowerBound) /
            (EqualizerSettings.gainRange.upperBound - EqualizerSettings.gainRange.lowerBound)
    }

    private var frequencyLabel: String {
        frequency >= 1_000
            ? "\(Int(frequency / 1_000))k"
            : "\(Int(frequency))"
    }
}

private struct EqualizerCurveVector: VectorArithmetic {
    var values: [Double]

    static var zero: EqualizerCurveVector {
        EqualizerCurveVector(values: Array(repeating: 0, count: EqualizerSettings.bandFrequencies.count))
    }

    static func + (lhs: EqualizerCurveVector, rhs: EqualizerCurveVector) -> EqualizerCurveVector {
        EqualizerCurveVector(values: combined(lhs.values, rhs.values, operation: +))
    }

    static func - (lhs: EqualizerCurveVector, rhs: EqualizerCurveVector) -> EqualizerCurveVector {
        EqualizerCurveVector(values: combined(lhs.values, rhs.values, operation: -))
    }

    static func += (lhs: inout EqualizerCurveVector, rhs: EqualizerCurveVector) {
        lhs = lhs + rhs
    }

    static func -= (lhs: inout EqualizerCurveVector, rhs: EqualizerCurveVector) {
        lhs = lhs - rhs
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func combined(
        _ lhs: [Double],
        _ rhs: [Double],
        operation: (Double, Double) -> Double
    ) -> [Double] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map { index in
            operation(index < lhs.count ? lhs[index] : 0, index < rhs.count ? rhs[index] : 0)
        }
    }
}

private struct EqualizerCurveView: View, Animatable {
    var gainsDB: [Double]

    var animatableData: EqualizerCurveVector {
        get { EqualizerCurveVector(values: gainsDB) }
        set { gainsDB = newValue.values }
    }

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 8
            let usableWidth = max(1, size.width - inset * 2)
            let usableHeight = max(1, size.height - inset * 2)
            let zeroY = inset + usableHeight / 2

            var zero = Path()
            zero.move(to: CGPoint(x: inset, y: zeroY))
            zero.addLine(to: CGPoint(x: size.width - inset, y: zeroY))
            context.stroke(zero, with: .color(.primary.opacity(0.15)), lineWidth: 1)

            guard gainsDB.count > 1 else { return }
            let points = gainsDB.indices.map { index -> CGPoint in
                let x = inset + usableWidth * CGFloat(index) / CGFloat(gainsDB.count - 1)
                // Compress the full ±12 dB range non-linearly so ordinary
                // 1–5 dB adjustments read clearly without changing DSP gain.
                let linearMagnitude = min(abs(gainsDB[index]) / 12, 1)
                let emphasizedMagnitude = sqrt(linearMagnitude)
                let normalized = gainsDB[index] < 0 ? -emphasizedMagnitude : emphasizedMagnitude
                let y = zeroY - CGFloat(normalized) * usableHeight / 2
                return CGPoint(x: x, y: y)
            }

            var curve = Path()
            curve.move(to: points[0])
            let tension: CGFloat = 0.82
            for index in 0..<(points.count - 1) {
                let p0 = points[max(index - 1, 0)]
                let p1 = points[index]
                let p2 = points[index + 1]
                let p3 = points[min(index + 2, points.count - 1)]
                let control1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) * tension / 6,
                    y: clampedCurveY(p1.y + (p2.y - p0.y) * tension / 6, inset: inset, height: size.height)
                )
                let control2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) * tension / 6,
                    y: clampedCurveY(p2.y - (p3.y - p1.y) * tension / 6, inset: inset, height: size.height)
                )
                curve.addCurve(to: p2, control1: control1, control2: control2)
            }

            var area = curve
            area.addLine(to: CGPoint(x: points.last?.x ?? inset, y: zeroY))
            area.addLine(to: CGPoint(x: points.first?.x ?? inset, y: zeroY))
            area.closeSubpath()
            context.fill(area, with: .color(.accentColor.opacity(0.055)))

            context.stroke(
                curve,
                with: .color(.accentColor.opacity(0.12)),
                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                curve,
                with: .color(.accentColor.opacity(0.82)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }
        .padding(.horizontal, 4)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func clampedCurveY(_ y: CGFloat, inset: CGFloat, height: CGFloat) -> CGFloat {
        min(max(y, inset), height - inset)
    }
}
