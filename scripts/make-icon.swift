import AppKit
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.56, blue: 0.99, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.85, alpha: 1))!.draw(in: tile, angle: -70)
let bubble = NSBezierPath(roundedRect: NSRect(x: 214, y: 302, width: 596, height: 470), xRadius: 92, yRadius: 92)
NSColor.white.setFill(); bubble.fill()
let tail = NSBezierPath(); tail.move(to: NSPoint(x: 320, y: 330)); tail.line(to: NSPoint(x: 320, y: 217)); tail.line(to: NSPoint(x: 450, y: 330)); tail.close(); tail.fill()
let text = "译" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 326, weight: .medium), .foregroundColor: NSColor(calibratedRed: 0.17, green: 0.42, blue: 0.93, alpha: 1)]
let textSize = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (1024 - textSize.width) / 2, y: 330), withAttributes: attributes)
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
