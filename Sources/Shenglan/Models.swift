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

/// A read-only snapshot used by SwiftUI. Core Audio property access may block
/// for Bluetooth and aggregate devices, so views must never query HAL while
/// building their body.
struct AudioDeviceRuntimeState: Equatable {
    var outputVolume: Double = 0
    var outputMuted = false
    var outputSupportsVolume = false
    var inputVolume: Double = 0
    var inputMuted = false
    var inputSupportsVolume = false
    var availableSampleRates: [Double] = []
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

enum EqualizerPreset: String, CaseIterable, Identifiable, Codable, Hashable {
    case flat
    case hifi
    case vocal
    case bass
    case pop
    case rock
    case smallRoom
    case studio
    case homeTheater
    case theater
    case concertHall
    case cathedral
    case custom

    var id: String { rawValue }

    static let tonePresets: [EqualizerPreset] = [.flat, .hifi, .vocal, .bass, .pop, .rock, .custom]
    static let spatialPresets: [EqualizerPreset] = [.smallRoom, .studio, .homeTheater, .theater, .concertHall, .cathedral]

    var title: String {
        switch self {
        case .flat: L10n.tr("原声直通")
        case .hifi: L10n.tr("HiFi 清晰")
        case .vocal: L10n.tr("人声清晰")
        case .bass: L10n.tr("低音增强")
        case .pop: L10n.tr("流行")
        case .rock: L10n.tr("摇滚")
        case .smallRoom: L10n.tr("小房间")
        case .studio: L10n.tr("录音棚")
        case .homeTheater: L10n.tr("私人影院")
        case .theater: L10n.tr("剧场")
        case .concertHall: L10n.tr("音乐厅")
        case .cathedral: L10n.tr("教堂")
        case .custom: L10n.tr("自定义")
        }
    }

    var systemImage: String {
        switch self {
        case .flat: "waveform"
        case .hifi: "sparkles"
        case .vocal: "mic.fill"
        case .bass: "speaker.wave.3.fill"
        case .pop: "music.note"
        case .rock: "bolt.fill"
        case .smallRoom: "house.fill"
        case .studio: "waveform.badge.mic"
        case .homeTheater: "tv.fill"
        case .theater: "theatermasks.fill"
        case .concertHall: "music.note.list"
        case .cathedral: "building.columns.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    var bandGainsDB: [Double] {
        switch self {
        case .flat, .custom:
            Array(repeating: 0, count: EqualizerSettings.bandFrequencies.count)
        case .hifi:
            [5.0, 4.0, 2.0, -2.0, -1.5, 1.0, 2.5, 4.5, 6.0, 5.0]
        case .vocal:
            [-6.5, -5.0, -2.0, 2.5, 5.0, 7.5, 7.0, 3.5, -2.0, -4.5]
        case .bass:
            [9.0, 8.0, 6.0, 3.0, 0, -2.0, -1.5, 0, 1.5, 2.0]
        case .pop:
            [5.0, 6.0, 3.0, 0, -3.0, 1.5, 5.0, 6.5, 5.0, 3.0]
        case .rock:
            [6.5, 5.0, 2.0, -2.0, -3.5, 1.5, 6.0, 8.0, 6.5, 4.0]
        case .smallRoom:
            [-3.0, -1.5, 0, 2.0, 2.5, 1.5, 0, -1.5, -3.0, -4.0]
        case .studio:
            [-2.0, -1.0, 0, 1.5, 2.0, 1.5, 0, -1.0, -2.0, -3.0]
        case .homeTheater:
            [5.0, 3.0, 1.0, -2.0, -2.0, 0, 2.5, 5.0, 4.0, 2.0]
        case .theater:
            [-3.0, -1.0, 1.5, 2.5, 0.5, -2.0, 0, 2.0, 0, -4.0]
        case .concertHall:
            [-4.0, -2.0, 0, 2.5, 2.0, 0, -2.0, 0, -2.0, -5.0]
        case .cathedral:
            [-5.0, -3.0, -1.5, 0, 2.0, 2.5, 0, -2.0, -4.0, -6.0]
        }
    }

    var preampDB: Double {
        switch self {
        case .flat, .custom: 0
        case .hifi: -6.5
        case .vocal: -8.0
        case .bass: -9.5
        case .pop: -7.0
        case .rock: -8.5
        case .smallRoom: -4.0
        case .studio: -3.0
        case .homeTheater: -6.0
        case .theater: -6.0
        case .concertHall: -7.0
        case .cathedral: -8.0
        }
    }

    var reverb: EqualizerReverbSettings {
        switch self {
        case .flat, .hifi, .vocal, .bass, .pop, .rock, .custom:
            .dry
        case .smallRoom:
            EqualizerReverbSettings(wetMix: 0.30, roomSize: 0.28, damping: 0.58, preDelayMS: 8, stereoWidth: 0.45)
        case .studio:
            EqualizerReverbSettings(wetMix: 0.24, roomSize: 0.20, damping: 0.70, preDelayMS: 4, stereoWidth: 0.35)
        case .homeTheater:
            EqualizerReverbSettings(wetMix: 0.38, roomSize: 0.50, damping: 0.56, preDelayMS: 18, stereoWidth: 0.68)
        case .theater:
            EqualizerReverbSettings(wetMix: 0.45, roomSize: 0.72, damping: 0.48, preDelayMS: 32, stereoWidth: 0.82)
        case .concertHall:
            EqualizerReverbSettings(wetMix: 0.52, roomSize: 0.84, damping: 0.40, preDelayMS: 44, stereoWidth: 0.92)
        case .cathedral:
            EqualizerReverbSettings(wetMix: 0.60, roomSize: 0.96, damping: 0.30, preDelayMS: 60, stereoWidth: 1.0)
        }
    }
}

struct EqualizerReverbSettings: Codable, Hashable {
    static let dry = EqualizerReverbSettings()

    var wetMix = 0.0
    var roomSize = 0.5
    var damping = 0.5
    var preDelayMS = 0.0
    var stereoWidth = 0.5

    mutating func normalize() {
        wetMix = min(max(wetMix, 0), 0.60)
        roomSize = min(max(roomSize, 0), 1)
        damping = min(max(damping, 0), 1)
        preDelayMS = min(max(preDelayMS, 0), 80)
        stereoWidth = min(max(stereoWidth, 0), 1)
    }
}

struct EqualizerCustomProfile: Codable, Hashable {
    var preampDB: Double
    var bandGainsDB: [Double]
    var reverb: EqualizerReverbSettings
    var stereoBalance: Double = 0

    private enum CodingKeys: String, CodingKey {
        case preampDB, bandGainsDB, reverb, stereoBalance
    }

    init(
        preampDB: Double,
        bandGainsDB: [Double],
        reverb: EqualizerReverbSettings,
        stereoBalance: Double = 0
    ) {
        self.preampDB = preampDB
        self.bandGainsDB = bandGainsDB
        self.reverb = reverb
        self.stereoBalance = stereoBalance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preampDB = try container.decodeIfPresent(Double.self, forKey: .preampDB) ?? 0
        bandGainsDB = try container.decodeIfPresent([Double].self, forKey: .bandGainsDB) ??
            Array(repeating: 0, count: EqualizerSettings.bandFrequencies.count)
        reverb = try container.decodeIfPresent(EqualizerReverbSettings.self, forKey: .reverb) ?? .dry
        stereoBalance = try container.decodeIfPresent(Double.self, forKey: .stereoBalance) ?? 0
        normalize()
    }

    mutating func normalize() {
        preampDB = min(max(preampDB, EqualizerSettings.preampRange.lowerBound), EqualizerSettings.preampRange.upperBound)
        if bandGainsDB.count < EqualizerSettings.bandFrequencies.count {
            bandGainsDB.append(
                contentsOf: repeatElement(0, count: EqualizerSettings.bandFrequencies.count - bandGainsDB.count)
            )
        } else if bandGainsDB.count > EqualizerSettings.bandFrequencies.count {
            bandGainsDB.removeSubrange(EqualizerSettings.bandFrequencies.count...)
        }
        bandGainsDB = bandGainsDB.map {
            min(max($0, EqualizerSettings.gainRange.lowerBound), EqualizerSettings.gainRange.upperBound)
        }
        reverb.normalize()
        stereoBalance = min(max(stereoBalance, -1), 1)
    }
}

struct EqualizerSettings: Codable, Hashable {
    static let bandFrequencies: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    static let gainRange: ClosedRange<Double> = -12...12
    static let preampRange: ClosedRange<Double> = -12...0

    var isEnabled = false
    var preset: EqualizerPreset = .flat
    var preampDB = 0.0
    var bandGainsDB = Array(repeating: 0.0, count: EqualizerSettings.bandFrequencies.count)
    var reverb = EqualizerReverbSettings.dry
    var stereoBalance = 0.0
    var customProfile: EqualizerCustomProfile?
    var savedProfiles: [String: EqualizerCustomProfile] = [:]

    private enum CodingKeys: String, CodingKey {
        case isEnabled, preset, preampDB, bandGainsDB, reverb, stereoBalance, customProfile, savedProfiles
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        preset = try container.decodeIfPresent(EqualizerPreset.self, forKey: .preset) ?? .flat
        preampDB = try container.decodeIfPresent(Double.self, forKey: .preampDB) ?? 0
        bandGainsDB = try container.decodeIfPresent([Double].self, forKey: .bandGainsDB) ??
            Array(repeating: 0, count: Self.bandFrequencies.count)
        reverb = try container.decodeIfPresent(EqualizerReverbSettings.self, forKey: .reverb) ?? .dry
        stereoBalance = try container.decodeIfPresent(Double.self, forKey: .stereoBalance) ?? 0
        customProfile = try container.decodeIfPresent(EqualizerCustomProfile.self, forKey: .customProfile)
        savedProfiles = try container.decodeIfPresent(
            [String: EqualizerCustomProfile].self,
            forKey: .savedProfiles
        ) ?? [:]
        normalize()
    }

    var hasAudibleProcessing: Bool {
        isEnabled && (
            abs(preampDB) > 0.001 ||
            bandGainsDB.contains { abs($0) > 0.001 } ||
            reverb.wetMix > 0.001 ||
            abs(stereoBalance) > 0.001
        )
    }

    mutating func normalize() {
        preampDB = min(max(preampDB, Self.preampRange.lowerBound), Self.preampRange.upperBound)
        if bandGainsDB.count < Self.bandFrequencies.count {
            bandGainsDB.append(contentsOf: repeatElement(0, count: Self.bandFrequencies.count - bandGainsDB.count))
        } else if bandGainsDB.count > Self.bandFrequencies.count {
            bandGainsDB.removeSubrange(Self.bandFrequencies.count...)
        }
        bandGainsDB = bandGainsDB.map { min(max($0, Self.gainRange.lowerBound), Self.gainRange.upperBound) }
        reverb.normalize()
        stereoBalance = min(max(stereoBalance, -1), 1)
        savedProfiles = savedProfiles.reduce(into: [:]) { result, entry in
            guard EqualizerPreset(rawValue: entry.key) != nil else { return }
            var saved = entry.value
            saved.normalize()
            result[entry.key] = saved
        }

        var legacyCustom = customProfile
        legacyCustom?.normalize()

        if savedProfiles.isEmpty {
            let current = currentProfile
            if preset == .custom {
                savedProfiles[EqualizerPreset.custom.rawValue] = current
            } else {
                if current != defaultProfile(for: preset) {
                    savedProfiles[preset.rawValue] = current
                }
                if let legacyCustom {
                    savedProfiles[EqualizerPreset.custom.rawValue] = legacyCustom
                }
            }
        } else if savedProfiles[EqualizerPreset.custom.rawValue] == nil,
                  let legacyCustom {
            savedProfiles[EqualizerPreset.custom.rawValue] = legacyCustom
        }

        customProfile = savedProfiles[EqualizerPreset.custom.rawValue]
    }

    var currentProfile: EqualizerCustomProfile {
        var saved = EqualizerCustomProfile(
            preampDB: preampDB,
            bandGainsDB: bandGainsDB,
            reverb: reverb,
            stereoBalance: stereoBalance
        )
        saved.normalize()
        return saved
    }

    func defaultProfile(for preset: EqualizerPreset) -> EqualizerCustomProfile {
        EqualizerCustomProfile(
            preampDB: preset.preampDB,
            bandGainsDB: preset.bandGainsDB,
            reverb: preset.reverb,
            stereoBalance: 0
        )
    }

    func hasSavedProfile(for preset: EqualizerPreset) -> Bool {
        savedProfiles[preset.rawValue] != nil
    }

    mutating func prepareCurrentPresetForEditing() {
        if preset == .flat {
            preset = .custom
        }
        isEnabled = true
    }

    mutating func saveCurrentPresetProfile() {
        savedProfiles[preset.rawValue] = currentProfile
        if preset == .custom {
            customProfile = currentProfile
        }
    }

    mutating func saveCustomProfile() {
        preset = .custom
        saveCurrentPresetProfile()
    }

    mutating func resetCurrentPreset() {
        let currentPreset = preset
        savedProfiles.removeValue(forKey: currentPreset.rawValue)
        if currentPreset == .custom {
            customProfile = nil
        }
        preampDB = currentPreset.preampDB
        bandGainsDB = currentPreset.bandGainsDB
        reverb = currentPreset.reverb
        stereoBalance = 0
        isEnabled = currentPreset != .flat
    }

    mutating func apply(_ preset: EqualizerPreset) {
        self.preset = preset
        var profile = savedProfiles[preset.rawValue] ?? defaultProfile(for: preset)
        profile.normalize()
        bandGainsDB = profile.bandGainsDB
        preampDB = profile.preampDB
        reverb = profile.reverb
        stereoBalance = profile.stereoBalance
        isEnabled = preset != .flat
    }
}

/// Shared batch rules for EQ activation. Keeping this transformation outside
/// the views makes the main window and menu-bar controller operate on exactly
/// the same master/app state while preserving every preset's saved values.
enum EqualizerBatchState {
    static func hasEnabled(
        master: EqualizerSettings,
        applications: [String: EqualizerSettings]
    ) -> Bool {
        master.isEnabled || applications.values.contains(where: \.isEnabled)
    }

    static func shouldShowDisableAllAction(
        master: EqualizerSettings,
        currentApplications: [EqualizerSettings]
    ) -> Bool {
        master.isEnabled || currentApplications.contains(where: \.isEnabled)
    }

    static func disableAll(
        master: inout EqualizerSettings,
        applications: inout [String: EqualizerSettings]
    ) {
        master.isEnabled = false
        applications = applications.mapValues { value in
            var disabled = value
            disabled.isEnabled = false
            return disabled
        }
    }
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

enum MenuBarPopoverStyle: String, CaseIterable, Identifiable {
    case minimal = "极简模式"
    case full = "完整模式"

    var id: String { rawValue }
    var displayName: String { L10n.tr(rawValue) }
    var symbol: String {
        switch self {
        case .minimal: "rectangle.compress.vertical"
        case .full: "slider.horizontal.3"
        }
    }
}
