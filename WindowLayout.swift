import AppKit

enum WidgetSizeMode: String {
    case compact, normal
    case fullHeight = "full-height"

    var next: Self {
        switch self {
        case .compact: return .normal
        case .normal: return .fullHeight
        case .fullHeight: return .compact
        }
    }
    var icon: String {
        switch self {
        case .compact: return "chevron.down"
        case .normal: return "arrow.up.and.down"
        case .fullHeight: return "chevron.up"
        }
    }
    var nextAction: String {
        switch self {
        case .compact: return "Desplegar atajos"
        case .normal: return "Ocupar todo el alto disponible"
        case .fullHeight: return "Compactar atajos"
        }
    }
}

struct WidgetLayout {
    static let width: CGFloat = 330
    static let compactHeight: CGFloat = 58
    var normalFrame: NSRect

    static func defaultFrame(in screen: NSRect) -> NSRect {
        let height = min(620, screen.height - 48)
        return NSRect(x: screen.maxX - width - 24, y: screen.maxY - height - 24, width: width, height: height)
    }
    func fittedNormalFrame(in screen: NSRect) -> NSRect {
        let height = min(normalFrame.height, screen.height)
        return NSRect(x: min(max(normalFrame.minX, screen.minX), screen.maxX - Self.width),
                      y: min(max(normalFrame.minY, screen.minY), screen.maxY - height),
                      width: Self.width, height: height)
    }
    func frame(for mode: WidgetSizeMode, in screen: NSRect) -> NSRect {
        let normal = fittedNormalFrame(in: screen)
        switch mode {
        case .normal: return normal
        case .compact:
            return NSRect(x: normal.minX, y: normal.maxY - Self.compactHeight, width: Self.width, height: Self.compactHeight)
        case .fullHeight:
            return NSRect(x: normal.minX, y: screen.minY, width: Self.width, height: screen.height)
        }
    }
    mutating func rememberPosition(of frame: NSRect, mode: WidgetSizeMode) {
        normalFrame.origin.x = frame.minX
        if mode != .fullHeight { normalFrame.origin.y = frame.maxY - normalFrame.height }
    }
}
