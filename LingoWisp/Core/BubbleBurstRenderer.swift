import CoreGraphics
import Foundation

/// Port of the approved circular dust preview. Preparation happens once per
/// dismissal; the image and sampling buffer contain only this app's bubble.
final class BubbleBurstRenderer {
    static let duration: TimeInterval = 1.4
    static let margin: CGFloat = 240
    private let image: CGImage
    private let card: CGRect
    private let material: CGContext
    private let scale: CGFloat = 2
    private var grains: [Grain] = []
    private var particles: [Particle] = []

    private struct Grain {
        let x, y, birth, radius: CGFloat
    }
    private struct Particle {
        let x, y, birth, life, vx, vy, swirl, phase, size, alpha: CGFloat
        let color: CGColor
    }

    init?(image: CGImage, card: CGRect) {
        guard card.width > 0, card.height > 0 else { return nil }
        self.image = image; self.card = card
        let width = Int(ceil(card.width * 2)), height = Int(ceil(card.height * 2))
        guard let source = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let material = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        self.material = material
        source.scaleBy(x: scale, y: scale)
        source.draw(image, in: CGRect(origin: .zero, size: card.size))
        material.scaleBy(x: scale, y: scale)
        guard let raw = source.data else { return nil }
        let pixels = raw.assumingMemoryBound(to: UInt8.self)
        var row = 0
        var gy: CGFloat = -2
        while gy <= card.height + 3 {
            var gx: CGFloat = -3
            while gx <= card.width + 3 {
                let x = gx + CGFloat(row % 2) * 1.5 + (Self.noise(gx + 4, gy + 7) - 0.5) * 0.35
                let y = gy + (Self.noise(gy + 5, gx + 9) - 0.5) * 0.35
                let n = Self.noise(x, y), n2 = Self.noise(y + 9, x + 17), n3 = Self.noise(x + 84, y + 51)
                let rough = sin(y * 0.087 + x * 0.035) * 0.07 + sin(y * 0.23 - x * 0.10) * 0.035 + (n - 0.5) * 0.14
                let birth = Self.clamp(0.055 + (1 - x / card.width) * 1.42 + rough, 0.07, 1.52)
                grains.append(Grain(x: x, y: y, birth: birth, radius: 2.4 + n2 * 0.15))
                if x >= 0, y >= 0, x < card.width, y < card.height {
                    let sx = min(width - 1, Int(x * scale)), sy = min(height - 1, Int(y * scale))
                    let i = (sy * width + sx) * 4
                    let alpha = CGFloat(pixels[i + 3]) / 255
                    if alpha >= 24.0 / 255 {
                        // Unpremultiply before applying the preview's subtle ash tint.
                        func channel(_ offset: Int) -> CGFloat {
                            Self.clamp((CGFloat(pixels[i + offset]) / max(alpha, 0.001) * 0.76 + 22) / 255, 0, 1)
                        }
                        particles.append(Particle(x: x, y: y, birth: birth, life: 0.47 + n * 0.38,
                            vx: 65 + n2 * 170, vy: (n3 - 0.62) * 55, swirl: 4 + n2 * 14,
                            phase: n * .pi * 2, size: 1.1 + n3 * 2.1, alpha: alpha,
                            color: CGColor(red: channel(0), green: channel(1), blue: channel(2), alpha: 1)))
                    }
                }
                gx += 3
            }
            gy += 2.6; row += 1
        }
    }

    func draw(in context: CGContext, time: TimeInterval) {
        guard time >= 0, time < Self.duration else { return }
        // Preserve the approved preview's trajectories, compressed to 1.4 s.
        let t = CGFloat(time / Self.duration * 2.4)
        let bounds = CGRect(origin: .zero, size: card.size)
        material.clear(bounds)
        material.setBlendMode(.normal)
        material.setFillColor(CGColor(gray: 1, alpha: 1))
        // Interior discs are fully overlapped. Fill that known-solid area once,
        // then draw the exact circular union only near the eroding edge.
        let solidWidth = card.width * (1 - Self.clamp((t + 0.165) / 1.42, 0, 1))
        if solidWidth > 0 { material.fill(CGRect(x: 0, y: 0, width: solidWidth, height: card.height)) }
        material.beginPath()
        for grain in grains where grain.x + grain.radius >= solidWidth {
            let alive = Self.clamp((grain.birth - t) / 0.045, 0, 1)
            guard alive > 0 else { continue }
            let radius = grain.radius * sqrt(alive)
            material.addEllipse(in: CGRect(x: grain.x - radius, y: grain.y - radius, width: radius * 2, height: radius * 2))
        }
        material.fillPath()
        material.setBlendMode(.sourceIn)
        material.draw(image, in: bounds)
        material.setBlendMode(.normal)
        if let remainder = material.makeImage() { context.draw(remainder, in: card) }

        context.saveGState()
        for p in particles {
            let age = t - p.birth
            guard age >= 0, age <= p.life else { continue }
            let progress = age / p.life
            let drift = p.vx * age * (0.4 + progress * 0.85)
            let wave = sin(age * 9 + p.phase) - sin(p.phase)
            let x = card.minX + p.x + drift
            // Canvas y points down; CoreGraphics y points up.
            let y = card.minY + p.y - p.vy * age - wave * p.swirl * progress
            let diameter = p.size * (1 - progress * 0.4)
            context.setAlpha(pow(1 - progress, 0.8) * p.alpha)
            context.setFillColor(p.color)
            context.fillEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
        }
        context.restoreGState()
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(upper, max(lower, value))
    }
    private static func noise(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let value = sin(x * 127.1 + y * 311.7 + 18.3) * 43758.5453123
        return value - floor(value)
    }
}
