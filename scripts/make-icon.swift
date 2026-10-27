// Draws the 1024px app icon: a quarter-circle corner with a progress ring on a dark tile.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let side = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let background = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1).setFill()
background.fill()
background.addClip()

let corner = NSPoint(x: tile.minX, y: tile.maxY)
let radius: CGFloat = 560
let quarter = NSBezierPath()
quarter.move(to: corner)
quarter.line(to: NSPoint(x: corner.x + radius, y: corner.y))
quarter.appendArc(withCenter: corner, radius: radius, startAngle: 0, endAngle: -90, clockwise: true)
quarter.close()
NSColor(calibratedWhite: 1, alpha: 0.13).setFill()
quarter.fill()

func arc(to end: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: corner, radius: radius - 44, startAngle: 0, endAngle: end, clockwise: true)
    path.lineWidth = 38
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}
arc(to: -90, color: NSColor(calibratedWhite: 1, alpha: 0.16))
arc(to: -58, color: NSColor(calibratedRed: 0.27, green: 0.56, blue: 1, alpha: 1))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
