import AppKit
import AltoCore

/// The menu-bar glyph: a speech bubble with three dots, drawn from its SVG
/// path as a template image so macOS tints it for light and dark menu bars.
@MainActor enum StatusIcon {
    static let designSize = NSSize(width: 18, height: 15)
    static let path = "M11.9775 0C15.3036 0 18 2.69642 18 6.02246C18 7.81362 17.2168 9.42131 15.9756 10.5244C14.3203 11.9955 12.3932 13.3831 10.6191 14.7822C9.96329 15.2995 9 14.8323 9 13.9971V13.0449C9 12.4926 8.55228 12.0449 8 12.0449H6.02246C2.69647 12.0449 7.42189e-05 9.34844 0 6.02246C0 2.69642 2.69642 0 6.02246 0H11.9775ZM4.5 4.5C3.67157 4.5 3 5.17157 3 6C3 6.82843 3.67157 7.5 4.5 7.5C5.32843 7.5 6 6.82843 6 6C6 5.17157 5.32843 4.5 4.5 4.5ZM9 4.5C8.17157 4.5 7.5 5.17157 7.5 6C7.5 6.82843 8.17157 7.5 9 7.5C9.82843 7.5 10.5 6.82843 10.5 6C10.5 5.17157 9.82843 4.5 9 4.5ZM13.5 4.5C12.6716 4.5 12 5.17157 12 6C12 6.82843 12.6716 7.5 13.5 7.5C14.3284 7.5 15 6.82843 15 6C15 5.17157 14.3284 4.5 13.5 4.5Z"
    static func image() -> NSImage {
        let image = NSImage(size: designSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(SVGPath.cgPath(path))
            context.setFillColor(.black)
            // Non-zero, the SVG default: the dots are wound the other way and become holes.
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Alto — Read aloud"
        return image
    }
}
