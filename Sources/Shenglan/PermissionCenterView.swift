import AppKit
import ServiceManagement
import SwiftUI

private enum PermissionDisplayState: Equatable {
    case granted
    case denied
    case notDetermined
    case requiresApproval
    case unavailable

    var title: String {
        switch self {
        case .granted: L10n.tr("已允许")
        case .denied: L10n.tr("未允许")
        case .notDetermined: L10n.tr("尚未申请")
        case .requiresApproval: L10n.tr("等待系统批准")
        case .unavailable: L10n.tr("当前不可用")
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .notDetermined: "questionmark.circle"
        case .requiresApproval: "clock.badge.exclamationmark"
        case .unavailable: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .denied: .red
        case .notDetermined, .requiresApproval: .orange
        case .unavailable: .secondary
        }
    }
}

struct PermissionCenterView: View {
    @EnvironmentObject private var audio: AudioController
    var embedded = false
    var showsHeader = true

    @ViewBuilder
    var body: some View {
        if embedded {
            permissionContent
        } else {
            permissionContent
                .padding(18)
                .liquidGlass(radius: 18)
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.tr("权限中心"), systemImage: "lock.shield.fill")
                        .font(ShenglanTypography.sectionTitle)
                    Text(L10n.tr("音合流只申请真实声音控制所需的权限，音频不会保存或上传。"))
                        .font(ShenglanTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 14)
            }

            permissionRow(
                title: "系统音频录制",
                detail: "用于发现正在发声的进程，并执行独立音量、静音、增强和输出路由。",
                symbol: "waveform.badge.mic",
                state: systemAudioState,
                requestTitle: "申请权限",
                request: audio.requestSystemAudioPermission,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
            )

            Divider().opacity(0.4)

            permissionRow(
                title: "登录时启动",
                detail: "登录 Mac 后自动启动音合流菜单栏控制器。",
                symbol: "power.circle.fill",
                state: loginItemState,
                requestTitle: "申请启动项",
                request: { audio.setLoginItemEnabled(true) },
                settingsURL: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            )

            Text(L10n.tr("设备枚举和系统主音量控制由 Core Audio 提供，不需要额外隐私权限。"))
                .font(ShenglanTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .padding(embedded ? 16 : 0)
        .background(
            embedded ? Color.primary.opacity(0.025) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(embedded ? 0.07 : 0), lineWidth: 0.8)
        )
    }

    private var systemAudioState: PermissionDisplayState {
        switch audio.systemAudioPermissionGranted {
        case true: .granted
        case false: .denied
        case nil: .notDetermined
        }
    }

    private var loginItemState: PermissionDisplayState {
        switch audio.loginItemStatus {
        case .enabled: .granted
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notDetermined
        case .notFound: .notDetermined
        @unknown default: .unavailable
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        symbol: String,
        state: PermissionDisplayState,
        requestTitle: String,
        request: @escaping () -> Void,
        settingsURL: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .glassControl(radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr(title)).font(ShenglanTypography.bodyStrong)
                Text(L10n.tr(detail))
                    .font(ShenglanTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                Label(state.title, systemImage: state.symbol)
                    .font(ShenglanTypography.captionStrong)
                    .foregroundStyle(state.color)

                HStack(spacing: 8) {
                if state != .granted && state != .unavailable {
                        Button(L10n.tr(requestTitle), action: request)
                            .buttonStyle(GlassButtonStyle(minHeight: 32, horizontalPadding: 10, radius: 10))
                }
                if state == .denied || state == .requiresApproval {
                    Button(L10n.tr("打开系统设置")) {
                        guard let url = URL(string: settingsURL) else { return }
                        NSWorkspace.shared.open(url)
                    }
                        .buttonStyle(GlassButtonStyle(minHeight: 32, horizontalPadding: 10, radius: 10))
                    }
                }
            }
        }
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }
}
