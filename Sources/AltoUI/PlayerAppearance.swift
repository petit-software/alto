import AppKit
import SwiftUI

// Adapted from Clio's OverlayPosition and OverlayController edge placement.
enum PlayerPosition: String, CaseIterable {
    case hidden, topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight, nearCursor
    var label: String {
        switch self {
        case .hidden: return "Hidden"
        case .topLeft: return "Top left"
        case .topCenter: return "Top center"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomCenter: return "Bottom center"
        case .bottomRight: return "Bottom right"
        case .nearCursor: return "Near cursor"
        }
    }
    var isTop: Bool { self == .topLeft || self == .topCenter || self == .topRight }
    func origin(size: NSSize, frame: NSRect, cursor: NSPoint) -> NSPoint {
        let gap: CGFloat = 64 - 14 // Visible pill gap minus shadow padding.
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .topLeft, .bottomLeft: x = frame.minX + gap
        case .topRight, .bottomRight: x = frame.maxX - size.width - gap
        case .nearCursor: x = cursor.x - size.width / 2
        default: x = frame.midX - size.width / 2
        }
        if self == .nearCursor { y = cursor.y - size.height - 24 }
        else { y = isTop ? frame.maxY - size.height - gap : frame.minY + gap }
        return NSPoint(x: min(max(x, frame.minX + 8), max(frame.minX + 8, frame.maxX - size.width - 8)),
                       y: min(max(y, frame.minY + 8), max(frame.minY + 8, frame.maxY - size.height - 8)))
    }
}

// Clio's independent tint-opacity and clear/frosted controls, with Alto's
// Reduce Transparency fallback and borderless embedded-player treatment.
struct PlayerSurface: ViewModifier {
    var opacity: Double
    var clear: Bool
    var embedded: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var dark: Bool { scheme == .dark }
    private var tint: Color { dark ? Color(white: 0.03) : Color(red: 0.98, green: 0.98, blue: 0.97) }
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(tint, in: Capsule())
            } else if #available(macOS 26, *) {
                // Glass must wrap the foreground, not just an empty background
                // shape, for native vibrant labels to adapt to the backdrop.
                content.background(tint.opacity(opacity), in: Capsule())
                    .glassEffect((clear ? Glass.clear : Glass.regular)
                        .tint((dark ? Color.black : Color.white).opacity(opacity)), in: Capsule())
            } else {
                // Older systems have no adaptive Liquid Glass foreground.
                // Keep enough tint to protect system-colored labels instead.
                content.background(tint.opacity(max(0.8, opacity)), in: Capsule())
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .overlay {
            if !embedded { Capsule().strokeBorder(dark ? .white.opacity(0.24) : .black.opacity(0.22), lineWidth: 0.5) }
        }
    }
}
