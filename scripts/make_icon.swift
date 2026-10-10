import AppKit

// Génère l'icône 1024x1024 : tuile sobre, anneau ouvert blanc.
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("Impossible de créer l'image")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.17, green: 0.30, blue: 0.36, alpha: 1),
    ending: NSColor(calibratedRed: 0.07, green: 0.13, blue: 0.17, alpha: 1))
gradient?.draw(in: tilePath, angle: -90)

let center = NSPoint(x: 512, y: 512)
let ring = NSBezierPath()
ring.appendArc(withCenter: center, radius: 220, startAngle: 40, endAngle: 320, clockwise: false)
ring.lineWidth = 58
ring.lineCapStyle = .round
NSColor(calibratedWhite: 0.97, alpha: 1).setStroke()
ring.stroke()

let dot = NSBezierPath(ovalIn: NSRect(x: 512 + 220 * 0.77 - 29, y: 512 + 220 * 0.64 - 29 + 0, width: 58, height: 58))
NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.80, alpha: 1).setFill()
dot.fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("Impossible d'encoder le PNG")
}
try data.write(to: URL(fileURLWithPath: outPath))
