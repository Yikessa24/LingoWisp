import CoreGraphics
import Foundation

/// One renderer drives the live animation and its deterministic frame previews.
/// The only image is the app's own bubble, never a screen capture.
enum BubbleBurstRenderer {
    static let duration: TimeInterval = 0.62
    static let margin: CGFloat = 110

    static func draw(in context: CGContext, image: CGImage, card: CGRect, time: TimeInterval) {
        guard time >= 0, time < duration else { return }
        let center = CGPoint(x: card.midX, y: card.midY)
        let swell = 1 + 0.035 * sin(min(1, time / 0.13) * .pi)
        let rupture = progress(time, from: 0.065, to: 0.235)
        let radius = hypot(card.width, card.height) * 0.56 * easeOut(rupture)
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: swell, y: swell)
        context.translateBy(x: -center.x, y: -center.y)
        let outline = CGPath(roundedRect: card, cornerWidth: 16, cornerHeight: 16, transform: nil)
        context.addPath(outline)
        context.clip()
        let tear = rupturePath(center: center, radius: radius)
        if rupture > 0 {
            context.addRect(card)
            context.addPath(tear)
            context.clip(using: .evenOdd)
        }
        context.draw(image, in: card)
        // A bright, thin retracting membrane makes the rupture visible before
        // the card has vanished; it is clipped to the remaining film.
        if rupture > 0 {
            context.setStrokeColor(CGColor(red: 0.70, green: 0.87, blue: 1, alpha: 0.95))
            context.setLineWidth(2)
            context.addPath(tear); context.strokePath()
        }
        context.restoreGState()

        guard time >= 0.075 else { return }
        for index in 0..<36 {
            let seed = CGFloat((index * 37 + 11) % 101) / 100
            let birth = 0.085 + Double(index % 4) * 0.009
            let p = progress(time, from: birth, to: duration - Double(index % 3) * 0.025)
            guard p > 0, p < 1 else { continue }
            let start = boundaryPoint(fraction: CGFloat(index) / 36, rect: card)
            let dx = start.x - center.x, dy = start.y - center.y
            let distance = max(1, hypot(dx, dy)), nx = dx / distance, ny = dy / distance
            let travel = (30 + seed * 60) * easeOut(p)
            let curl = sin(p * .pi) * (seed - 0.5) * 22
            let point = CGPoint(x: start.x + nx * travel - ny * curl,
                                y: start.y + ny * travel + nx * curl - 28 * p * p)
            let alpha = min(1, p / 0.08) * pow(1 - p, 1.4)
            let color = index % 3 == 0
                ? CGColor(red: 0.55, green: 0.78, blue: 1, alpha: alpha * 0.85)
                : CGColor(red: 0.96, green: 0.75 + seed * 0.2, blue: 0.96, alpha: alpha * 0.8)
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.rotate(by: atan2(ny, nx) + p * (seed - 0.5) * 4)
            context.setShadow(offset: .zero, blur: 2, color: CGColor(gray: 1, alpha: alpha * 0.35))
            if index % 3 == 0 {
                // Curved strips of the broken rim, rather than square confetti.
                let length = (6 + seed * 12) * (1 - p * 0.65)
                context.move(to: CGPoint(x: 0, y: -length / 2))
                context.addQuadCurve(to: CGPoint(x: 0, y: length / 2), control: CGPoint(x: 4 * (1 - p), y: 0))
                context.setLineWidth(1.1 + seed * 0.6)
                context.setLineCap(.round); context.setStrokeColor(color); context.strokePath()
            } else {
                // Tiny translucent droplets with a white specular highlight.
                let r = (1.5 + seed * 2.7) * (1 - p * 0.75)
                let drop = CGRect(x: -r, y: -r * 0.75, width: r * 2, height: r * 1.5)
                context.setFillColor(CGColor(red: 0.8, green: 0.91, blue: 1, alpha: alpha * 0.24))
                context.fillEllipse(in: drop)
                context.setStrokeColor(color); context.setLineWidth(0.8); context.strokeEllipse(in: drop)
                context.setFillColor(CGColor(gray: 1, alpha: alpha))
                context.fillEllipse(in: CGRect(x: -r * 0.45, y: r * 0.1, width: max(0.7, r * 0.55), height: max(0.7, r * 0.4)))
            }
            context.restoreGState()
        }
    }

    static func progress(_ time: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> CGFloat {
        CGFloat(min(1, max(0, (time - start) / (end - start))))
    }
    private static func easeOut(_ value: CGFloat) -> CGFloat { 1 - pow(1 - value, 2) }

    private static func rupturePath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<72 {
            let angle = CGFloat(index) / 72 * .pi * 2
            let r = radius * (1 + 0.055 * sin(angle * 3 + 0.6) + 0.025 * sin(angle * 7))
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func boundaryPoint(fraction: CGFloat, rect: CGRect) -> CGPoint {
        let r = min(16, min(rect.width, rect.height) / 2)
        let w = max(0, rect.width - r * 2), h = max(0, rect.height - r * 2), arc = .pi * r / 2
        var d = (fraction - floor(fraction)) * (2 * w + 2 * h + 4 * arc)
        let lengths = [w, arc, h, arc, w, arc, h, arc]
        for segment in 0..<8 {
            if d <= lengths[segment] {
                switch segment {
                case 0: return CGPoint(x: rect.minX + r + d, y: rect.minY)
                case 2: return CGPoint(x: rect.maxX, y: rect.minY + r + d)
                case 4: return CGPoint(x: rect.maxX - r - d, y: rect.maxY)
                case 6: return CGPoint(x: rect.minX, y: rect.maxY - r - d)
                default:
                    let centers = [CGPoint(x: rect.maxX - r, y: rect.minY + r), CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                                   CGPoint(x: rect.minX + r, y: rect.maxY - r), CGPoint(x: rect.minX + r, y: rect.minY + r)]
                    let corner = segment / 2
                    let angle = -.pi / 2 + CGFloat(corner) * .pi / 2 + d / max(r, 0.001)
                    return CGPoint(x: centers[corner].x + cos(angle) * r, y: centers[corner].y + sin(angle) * r)
                }
            }
            d -= lengths[segment]
        }
        return CGPoint(x: rect.minX + r, y: rect.minY)
    }
}
