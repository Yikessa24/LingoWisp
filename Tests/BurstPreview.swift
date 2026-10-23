// Preview frames use the exact production renderer with the fixed synthetic
// translation fixture. No user content or desktop screenshot is captured.
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

@main enum BurstPreview {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let input = root.appendingPathComponent("docs/screenshots/translation-light.png")
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing synthetic bubble fixture") }
        let margin = BubbleBurstRenderer.margin
        let card = CGRect(x: margin, y: margin, width: 358, height: CGFloat(image.height) / CGFloat(image.width) * 358)
        let width = Int(card.width + margin * 2), height = Int(card.height + margin * 2)
        let renderer = BubbleBurstRenderer(image: image, card: card)!
        func context(_ w: Int, _ h: Int) -> CGContext {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        func frame(_ time: Double) -> CGImage {
            let ctx = context(width, height)
            ctx.setFillColor(CGColor(red: 0.718, green: 0.761, blue: 0.816, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            renderer.draw(in: ctx, time: time)
            return ctx.makeImage()!
        }
        let gifURL = root.appendingPathComponent("docs/screenshots/bubble-burst.gif")
        let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 66, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<66 {
            let time = max(0, Double(index - 18) / 25)
            CGImageDestinationAddImage(gif, frame(time), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 25]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { fatalError("GIF export failed") }
        let sheet = context(width * 3, height * 2)
        for (index, time) in [0.0, 0.22, 0.44, 0.66, 0.95, 1.2].enumerated() {
            sheet.draw(frame(time), in: CGRect(x: index % 3 * width, y: (1 - index / 3) * height, width: width, height: height))
        }
        let png = CGImageDestinationCreateWithURL(root.appendingPathComponent("docs/screenshots/bubble-burst-frames.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(png, sheet.makeImage()!, nil)
        guard CGImageDestinationFinalize(png) else { fatalError("PNG export failed") }
        print("Production burst renderer: GIF and six frame preview exported")
    }
}
