import AppKit
import CoreAudio
import Foundation
import SwiftUI

struct AudioDeviceModel: Identifiable, Hashable {
    let id: AudioObjectID
    var uid: String
    var name: String
    var inputChannels: Int
    var outputChannels: Int
    var sampleRate: Double
    var transportType: UInt32
    var manufacturer: String
    var isDefaultInput: Bool
    var isDefaultOutput: Bool

    var isInput: Bool { inputChannels > 0 }
    var isOutput: Bool { outputChannels > 0 }
    var symbol: String {
        if name.localizedCaseInsensitiveContains("AirPods") { return "airpodspro" }
        if transportType == kAudioDeviceTransportTypeAirPlay { return "airplayaudio" }
        if transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE { return "headphones" }
        if transportType == kAudioDeviceTransportTypeHDMI || transportType == kAudioDeviceTransportTypeDisplayPort { return "display" }
        if transportType == kAudioDeviceTransportTypeUSB { return "cable.connector" }
        if name.localizedCaseInsensitiveContains("iPhone") { return "iphone" }
        if isInput && isOutput { return "hifispeaker.2.fill" }
        if isInput { return "mic.fill" }
        return "speaker.wave.3.fill"
    }

    var transportName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: L10n.tr("内建设备")
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: L10n.tr("蓝牙")
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: L10n.tr("雷雳")
        case kAudioDeviceTransportTypeAggregate: L10n.tr("聚合设备")
        case kAudioDeviceTransportTypeVirtual: L10n.tr("虚拟设备")
        default: "Core Audio"
        }
    }

    var isWireless: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE || transportType == kAudioDeviceTransportTypeAirPlay
    }
}

struct RememberedAudioDevice: Identifiable, Codable, Hashable {
    var id: String { uid }
    let uid: String
    var name: String
    var inputChannels: Int
    var outputChannels: Int
    var transportType: UInt32
    var manufacturer: String
    var lastSeen: Date
    var usedAsInput: Bool
    var usedAsOutput: Bool

    var isInput: Bool { inputChannels > 0 }
    var isOutput: Bool { outputChannels > 0 }
    var symbol: String {
        if name.localizedCaseInsensitiveContains("AirPods") { return "airpodspro" }
        if transportType == kAudioDeviceTransportTypeAirPlay { return "airplayaudio" }
        if transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE { return "headphones" }
        if transportType == kAudioDeviceTransportTypeHDMI || transportType == kAudioDeviceTransportTypeDisplayPort { return "display" }
        if transportType == kAudioDeviceTransportTypeUSB { return "cable.connector" }
        if name.localizedCaseInsensitiveContains("iPhone") { return "iphone" }
        if isInput && isOutput { return "hifispeaker.2.fill" }
        if isInput { return "mic.fill" }
        return "speaker.wave.3.fill"
    }

    var transportName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: L10n.tr("内建设备")
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: L10n.tr("蓝牙")
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: L10n.tr("雷雳")
        default: "Core Audio"
        }
    }
}

struct AudioProcessModel: Identifiable, Hashable {
    let id: AudioObjectID
    let pid: pid_t
    var bundleID: String
    var name: String
    var icon: NSImage?
    var category: AudioApplicationCategory
    var isRunningOutput: Bool
}

struct ApplicationMixState: Identifiable, Hashable {
    var id: AudioObjectID
    var pid: pid_t
    var bundleID: String
    var name: String
    var icon: NSImage?
    var category: AudioApplicationCategory = .other
    var volume: Double = 1.0
    var isMuted: Bool = false
    var boost: Int = 1
    var route: String = "跟随系统输出"
    var routeDeviceUID: String?
    var overdriveEnabled: Bool = false
    var processingActive: Bool = false
    var isRunningOutput: Bool = true
}

enum AudioApplicationCategory: Int, CaseIterable, Identifiable, Hashable {
    case music
    case video
    case other

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .music: L10n.tr("音乐")
        case .video: L10n.tr("视频")
        case .other: L10n.tr("其他音效")
        }
    }
    var symbol: String {
        switch self {
        case .music: "music.note"
        case .video: "play.rectangle.fill"
        case .other: "waveform"
        }
    }
}

enum ApplicationOrderGroup: String, CaseIterable, Identifiable, Codable {
    case favorites
    case music
    case video
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: L10n.tr("收藏")
        case .music: L10n.tr("音乐")
        case .video: L10n.tr("视频")
        case .other: L10n.tr("其他音效")
        }
    }

    var symbol: String {
        switch self {
        case .favorites: "star.fill"
        case .music: AudioApplicationCategory.music.symbol
        case .video: AudioApplicationCategory.video.symbol
        case .other: AudioApplicationCategory.other.symbol
        }
    }

    var category: AudioApplicationCategory? {
        switch self {
        case .favorites: nil
        case .music: .music
        case .video: .video
        case .other: .other
        }
    }

    static let categoryGroups: [ApplicationOrderGroup] = [.music, .video, .other]
}

enum ApplicationListTab: String, CaseIterable, Identifiable {
    case all
    case favorites
    case music
    case video
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.tr("全部")
        case .favorites: L10n.tr("收藏")
        case .music: L10n.tr("音乐")
        case .video: L10n.tr("视频")
        case .other: L10n.tr("其他")
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "star.fill"
        case .music: AudioApplicationCategory.music.symbol
        case .video: AudioApplicationCategory.video.symbol
        case .other: AudioApplicationCategory.other.symbol
        }
    }

    var orderGroup: ApplicationOrderGroup? {
        switch self {
        case .all: nil
        case .favorites: .favorites
        case .music: .music
        case .video: .video
        case .other: .other
        }
    }
}

enum ApplicationOrderMove {
    case up
    case down
    case first
    case last
}

enum ControllerSection: String, CaseIterable, Identifiable {
    case mixer = "混音"
    case devices = "设备"
    case settings = "设置"

    var id: String { rawValue }
    var displayName: String { L10n.tr(rawValue) }
    var symbol: String {
        switch self {
        case .mixer: "slider.horizontal.3"
        case .devices: "hifispeaker.2"
        case .settings: "gearshape"
        }
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
    var id: String { rawValue }
    var displayName: String { L10n.tr(rawValue) }
    var symbol: String { switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max.fill"; case .dark: "moon.stars.fill" } }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case french = "fr"
    case german = "de"
    case korean = "ko"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        case .french: "Français"
        case .german: "Deutsch"
        case .korean: "한국어"
        }
    }

    var localizedName: String { L10n.tr(nativeName, language: self) }
    var symbol: String { "character.bubble.fill" }
}

enum MenuBarIconChoice: String, CaseIterable, Identifiable {
    case waveform = "声波（音合流）"
    case speaker = "扬声器"
    case meter = "音量刻度"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .waveform: L10n.tr("音合流声环")
        case .speaker: L10n.tr("动态扬声器")
        case .meter: L10n.tr("音量柱")
        }
    }
    var symbol: String { symbol(volume: 1, muted: false) }
    func symbol(volume: Double, muted: Bool) -> String {
        switch self {
        case .waveform:
            return muted ? "waveform.slash" : "waveform.circle.fill"
        case .speaker:
            if muted || volume < 0.001 { return "speaker.slash.fill" }
            if volume < 0.34 { return "speaker.wave.1.fill" }
            if volume < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .meter:
            return muted ? "chart.bar.xaxis" : "chart.bar.fill"
        }
    }
}

enum MenuBarVolumeStyle: String, CaseIterable, Identifiable {
    case percentage = "百分比数字"
    case compactNumber = "紧凑数字"
    case segments = "分段音量格"
    case progress = "迷你进度条"
    case gauge = "动态仪表"

    var id: String { rawValue }
    var displayName: String { L10n.tr(rawValue) }
    var symbol: String {
        switch self {
        case .percentage: "percent"
        case .compactNumber: "number"
        case .segments: "chart.bar.fill"
        case .progress: "slider.horizontal.3"
        case .gauge: "gauge.with.dots.needle.67percent"
        }
    }
}
