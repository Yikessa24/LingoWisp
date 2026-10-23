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
        let card = CGRect(x: 110, y: 110, width: 358, height: CGFloat(image.height) / CGFloat(image.width) * 358)
        let width = Int(card.width + 220), height = Int(card.height + 220)
        func context(_ w: Int, _ h: Int) -> CGContext {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        func frame(_ time: Double) -> CGImage {
            let ctx = context(width, height)
            ctx.setFillColor(CGColor(red: 0.20, green: 0.23, blue: 0.28, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            BubbleBurstRenderer.draw(in: ctx, image: image, card: card, time: time)
            return ctx.makeImage()!
        }
        let gifURL = root.appendingPathComponent("docs/screenshots/bubble-burst.gif")
        let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 58, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<58 {
            let time = max(0, Double(index - 22) / 30)
            CGImageDestinationAddImage(gif, frame(time), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { fatalError("GIF export failed") }
        let sheet = context(width * 3, height * 2)
        for (index, time) in [0.0, 0.085, 0.13, 0.19, 0.29, 0.43].enumerated() {
            sheet.draw(frame(time), in: CGRect(x: index % 3 * width, y: (1 - index / 3) * height, width: width, height: height))
        }
        let png = CGImageDestinationCreateWithURL(root.appendingPathComponent("docs/screenshots/bubble-burst-frames.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(png, sheet.makeImage()!, nil)
        guard CGImageDestinationFinalize(png) else { fatalError("PNG export failed") }
        print("Production burst renderer: GIF and six frame preview exported")
    }
}
