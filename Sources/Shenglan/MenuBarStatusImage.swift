import AppKit

/// `MenuBarExtra` reliably maps one image and one text title into an
/// `NSStatusItem`.  Extra Shape/Image children can be discarded by the system
/// label bridge, so 音合流 renders the icon and volume indicator into one native
/// template image.  This also keeps every style visible in light and dark menu
/// bars without maintaining a second AppKit status item.
enum MenuBarStatusImage {
    // Match the optical weight of macOS system status icons. The previous
    // 16-point canvas made the waveform look visibly smaller than Wi-Fi,
    // Control Centre and nearby third-party items.
    private static let imageHeight: CGFloat = 22
    private static let iconSize: CGFloat = 20
    private static let iconIndicatorGap: CGFloat = 5
    private static let cache = NSCache<NSString, NSImage>()

    static func make(
        icon: MenuBarIconChoice,
        volume: Double,
        muted: Bool,
        showsVolume: Bool,
        volumeStyle: MenuBarVolumeStyle
    ) -> NSImage {
        let normalizedVolume = muted ? 0 : min(max(volume, 0), 1)
        let percentage = Int((normalizedVolume * 100).rounded())
        let key = "\(icon.rawValue)|\(percentage)|\(muted)|\(showsVolume)|\(volumeStyle.rawValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let indicatorWidth = showsVolume ? width(for: volumeStyle, percentage: percentage) : 0
        let totalWidth = iconSize + (showsVolume ? iconIndicatorGap + indicatorWidth : 0)
        let image = NSImage(size: NSSize(width: totalWidth, height: imageHeight), flipped: false) { _ in
            drawSymbol(
                icon.symbol(volume: normalizedVolume, muted: muted),
                in: NSRect(x: 0, y: (imageHeight - iconSize) / 2, width: iconSize, height: iconSize),
                pointSize: 19
            )

            guard showsVolume else { return true }
            let indicatorRect = NSRect(
                x: iconSize + iconIndicatorGap,
                y: 0,
                width: indicatorWidth,
                height: imageHeight
            )
            drawIndicator(volumeStyle, percentage: percentage, in: indicatorRect)
            return true
        }
        image.isTemplate = true
        cache.countLimit = 500
        cache.setObject(image, forKey: key)
        return image
    }

    /// AppKit adds roughly six points of horizontal breathing room on each
    /// side of a MenuBarExtra label. The panel positioner uses this complete
    /// status-item width to recover the clicked icon's visual center.
    static func estimatedStatusItemWidth(
        icon: MenuBarIconChoice,
        volume: Double,
        muted: Bool,
        showsVolume: Bool,
        volumeStyle: MenuBarVolumeStyle
    ) -> CGFloat {
        make(
            icon: icon,
            volume: volume,
            muted: muted,
            showsVolume: showsVolume,
            volumeStyle: volumeStyle
        ).size.width + 12
    }

    private static func width(for style: MenuBarVolumeStyle, percentage: Int) -> CGFloat {
        switch style {
        case .percentage:
            return ceil(textSize("\(percentage)%").width)
        case .compactNumber:
            return ceil(textSize("\(percentage)").width)
        case .segments:
            return 17
        case .progress:
            return 24
        case .gauge:
            return 15
        }
    }

    private static func drawIndicator(
        _ style: MenuBarVolumeStyle,
        percentage: Int,
        in rect: NSRect
    ) {
        switch style {
        case .percentage:
            drawText("\(percentage)%", in: rect)
        case .compactNumber:
            drawText("\(percentage)", in: rect)
        case .segments:
            drawSegments(percentage: percentage, in: rect)
        case .progress:
            drawProgress(percentage: percentage, in: rect)
        case .gauge:
            drawSymbol(gaugeSymbol(for: percentage), in: rect, pointSize: 13)
        }
    }

    private static func textAttributes() -> [NSAttributedString.Key: Any] {
        [
            // Use Apple's status-bar text metric directly, so the readout has
            // the same size and regular weight as nearby battery/date items.
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.black
        ]
    }

    private static func textSize(_ text: String) -> NSSize {
        (text as NSString).size(withAttributes: textAttributes())
    }

    private static func drawText(_ text: String, in rect: NSRect) {
        let size = textSize(text)
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: drawRect, withAttributes: textAttributes())
    }

    private static func drawSegments(percentage: Int, in rect: NSRect) {
        let activeCount = percentage == 0 ? 0 : min(4, max(1, Int(ceil(Double(percentage) / 25))))
        let heights: [CGFloat] = [5, 8, 11, 14]
        let barWidth: CGFloat = 3
        let gap: CGFloat = 1.5
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        let originX = rect.midX - totalWidth / 2

        for (index, height) in heights.enumerated() {
            NSColor.black.withAlphaComponent(index < activeCount ? 1 : 0.22).setFill()
            let barRect = NSRect(
                x: originX + CGFloat(index) * (barWidth + gap),
                y: rect.midY - 7,
                width: barWidth,
                height: height
            )
            NSBezierPath(roundedRect: barRect, xRadius: 1.2, yRadius: 1.2).fill()
        }
    }

    private static func drawProgress(percentage: Int, in rect: NSRect) {
        let trackRect = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor.black.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2).fill()

        guard percentage > 0 else { return }
        let fillWidth = max(1.5, rect.width * CGFloat(percentage) / 100)
        NSColor.black.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX, y: rect.midY - 2, width: fillWidth, height: 4),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    private static func gaugeSymbol(for percentage: Int) -> String {
        switch percentage {
        case ..<1: "gauge.with.dots.needle.0percent"
        case ..<42: "gauge.with.dots.needle.33percent"
        case ..<59: "gauge.with.dots.needle.50percent"
        case ..<84: "gauge.with.dots.needle.67percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }

    private static func drawSymbol(
        _ symbolName: String,
        in rect: NSRect,
        pointSize: CGFloat
    ) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        symbol.draw(in: centeredRect(for: symbol.size, inside: rect))
    }

    private static func centeredRect(for imageSize: NSSize, inside rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
