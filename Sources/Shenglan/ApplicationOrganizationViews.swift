import SwiftUI

struct ApplicationListTabBar: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: ApplicationListTab
    var compact = false

    private var height: CGFloat { compact ? 34 : 38 }

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(ApplicationListTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 5) {
                        if !compact || tab == .favorites {
                            Image(systemName: tab.symbol)
                                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        }
                        Text(tab.title)
                            .font(compact ? ShenglanTypography.captionStrong : ShenglanTypography.control)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: height - 6)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.07))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
                            }
                            .opacity(selection == tab ? 1 : 0)
                            .scaleEffect(selection == tab ? 1 : 0.985)
                            .animation(ShenglanMotion.quick, value: selection)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.title)，\(L10n.format("%@ 个应用", String(audio.applicationCount(for: tab))))")
            }
        }
        .padding(3)
        .frame(height: height)
        .liquidGlass(
            radius: 12,
            tint: colorScheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.32),
            interactive: true
        )
    }
}

struct ApplicationGroupHeader: View {
    @EnvironmentObject private var audio: AudioController
    let group: ApplicationOrderGroup
    let count: Int
    var compact = false

    var body: some View {
        Button {
            withAnimation(ShenglanMotion.quick) {
                audio.toggleApplicationGroupCollapsed(group)
            }
        } label: {
            HStack(spacing: compact ? 7 : 9) {
                Image(systemName: group.symbol)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .frame(width: 16)
                Text(group.title)
                    .font(compact ? ShenglanTypography.captionStrong : ShenglanTypography.bodyStrong)
                Text(L10n.tr("\(count)"))
                    .font(ShenglanTypography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 22)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                Spacer()
                Text(audio.isApplicationGroupCollapsed(group) ? L10n.tr("展开") : L10n.tr("收起"))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(audio.isApplicationGroupCollapsed(group) ? -90 : 0))
                    .animation(ShenglanMotion.quick, value: audio.isApplicationGroupCollapsed(group))
            }
            .padding(.horizontal, compact ? 8 : 40)
            .frame(maxWidth: .infinity, minHeight: compact ? 34 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.title)，\(L10n.format("%@ 个应用", String(count)))，\(audio.isApplicationGroupCollapsed(group) ? L10n.tr("已折叠") : L10n.tr("已展开"))")
    }
}

struct ApplicationFavoriteButton: View {
    @EnvironmentObject private var audio: AudioController
    let app: ApplicationMixState
    var size: CGFloat = 30

    var body: some View {
        Button {
            audio.toggleApplicationFavorite(app)
        } label: {
            Image(systemName: audio.isApplicationFavorite(app) ? "star.fill" : "star")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(audio.isApplicationFavorite(app) ? Color.primary : Color.secondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audio.isApplicationFavorite(app) ? "\(L10n.tr("取消收藏")) \(L10n.tr(app.name))" : "\(L10n.tr("收藏")) \(L10n.tr(app.name))")
        .help(audio.isApplicationFavorite(app) ? L10n.tr("取消收藏") : L10n.tr("加入收藏"))
    }
}

struct ApplicationDragHandle: View {
    @EnvironmentObject private var audio: AudioController
    let app: ApplicationMixState
    let group: ApplicationOrderGroup
    let rowStep: CGFloat
    @Binding var rowOffset: CGFloat
    var size: CGFloat = 30
    var showsBackground = true
    @State private var isDragging = false
    @State private var lastTranslationBand = 0
    @State private var committedRows = 0

    private var activationDistance: CGFloat {
        max(24, rowStep * 0.46)
    }

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isDragging ? 0.065 : 0.022))
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(isDragging ? 1.04 : 1)
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
                                if audio.moveApplication(
                                    preferenceKey: audio.applicationPreferenceKey(for: app),
                                    by: direction,
                                    in: group
                                ) {
                                    committedRows += direction
                                }
                            }
                        }

                        rowOffset = value.translation.height - CGFloat(committedRows) * rowStep
                    }
                    .onEnded { value in
                        if committedRows == 0, abs(value.translation.height) >= 14 {
                            _ = audio.moveApplication(
                                preferenceKey: audio.applicationPreferenceKey(for: app),
                                by: value.translation.height > 0 ? 1 : -1,
                                in: group
                            )
                        }
                        withAnimation(ShenglanMotion.settle) {
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
                withAnimation(ShenglanMotion.settle) {
                    _ = audio.moveApplication(
                        preferenceKey: audio.applicationPreferenceKey(for: app),
                        by: step,
                        in: group
                    )
                }
            }
            .accessibilityLabel("\(L10n.tr("拖动调整")) \(L10n.tr(app.name)) \(L10n.tr("的顺序"))")
            .help(L10n.tr("按住并上下拖动调整应用顺序"))
    }
}

struct ApplicationOrderControls: View {
    @EnvironmentObject private var audio: AudioController
    let app: ApplicationMixState
    let group: ApplicationOrderGroup
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            moveButton(.up, symbol: "chevron.up", label: "上移")
            moveButton(.down, symbol: "chevron.down", label: "下移")
        }
    }

    private func moveButton(_ move: ApplicationOrderMove, symbol: String, label: String) -> some View {
        let enabled = audio.canMoveApplication(app, in: group, move: move)
        return Button {
            audio.moveApplication(app, in: group, move: move)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
        }
        .buttonStyle(GlassIconButtonStyle(size: compact ? 28 : 30, radius: 9))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel("\(L10n.tr("将")) \(L10n.tr(app.name)) \(L10n.tr(label))")
    }
}
