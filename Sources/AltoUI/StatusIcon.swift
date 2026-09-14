import AppKit
import AltoCore

/// The menu-bar glyph: sound waves around a dot, drawn from its SVG strokes
/// as a template image so macOS tints it for light and dark menu bars.
@MainActor enum StatusIcon {
    static let designSize = NSSize(width: 25, height: 15)
    /// Round caps on the outer arcs reach the design's edges; keep a point clear on each side.
    static let margin: CGFloat = 1
    static let strokeWidth: CGFloat = 2.625
    static let arcs = [
        "M16.313 11.3125C18.9022 9.16759 18.9022 5.45741 16.313 3.3125",
        "M21.3135 13.3125C21.9476 12.5246 22.4505 11.5892 22.7937 10.5597C23.1369 9.53019 23.3135 8.4268 23.3135 7.3125C23.3135 6.1982 23.1369 5.09481 22.7937 4.06532C22.4505 3.03584 21.9476 2.10043 21.3135 1.3125",
        "M8.31294 11.3125C5.72381 9.16759 5.72381 5.45741 8.31294 3.3125",
        "M3.3125 13.3125C2.67842 12.5246 2.17544 11.5892 1.83228 10.5597C1.48912 9.53019 1.3125 8.4268 1.3125 7.3125C1.3125 6.1982 1.48912 5.09481 1.83228 4.06532C2.17544 3.03584 2.67842 2.10043 3.3125 1.3125"
    ]
    static let dot = (center: CGPoint(x: 12.3125, y: 7.3125), radius: CGFloat(1))
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: designSize.width + margin * 2, height: designSize.height), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: margin, y: 0)
            context.setStrokeColor(.black)
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)
            for arc in arcs {
                context.addPath(SVGPath.cgPath(arc))
                context.strokePath()
            }
            // A stroke wider than the circle's diameter leaves a hole in Core
            // Graphics; the design wants a solid dot, so fill to the stroke's outer edge.
            let radius = dot.radius + strokeWidth / 2
            context.setFillColor(.black)
            context.fillEllipse(in: CGRect(x: dot.center.x - radius, y: dot.center.y - radius, width: radius * 2, height: radius * 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Alto — Read aloud"
        return image
    }
}
