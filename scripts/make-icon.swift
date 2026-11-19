// Draws Scratchbar's app icon (a note on terracotta) as a 1024×1024 PNG.
// Usage: swift scripts/make-icon.swift <out.png>   (scripts/make-icon.sh builds the .icns)
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
// The app's Theme colours.
let paper = color(0xfaf9f5), paperShade = color(0xf1ece4), rule = color(0xcfc5b8)
let accent = color(0xbc6a3a), accentLight = color(0xd4885a)

func shadowed(_ alpha: CGFloat, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func pill(_ rect: NSRect, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The tile, on Apple's icon grid: 824 pt inside a 1024 canvas.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)
shadowed(0.3, blur: 24, y: -10) { accent.setFill(); tile.fill() }
NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(starting: accentLight, ending: accent)!.draw(in: tileRect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// The note.
let sheet = NSRect(x: 230, y: 190, width: 564, height: 650)
shadowed(0.22, blur: 30, y: -12) {
    paper.setFill()
    NSBezierPath(roundedRect: sheet, xRadius: 46, yRadius: 46).fill()
}
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: sheet, xRadius: 46, yRadius: 46).addClip()
NSGradient(starting: paper, ending: paperShade)!.draw(in: sheet, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Lines of text, with a cursor after the last one.
let height: CGFloat = 36, gap: CGFloat = 50
var top: CGFloat = 740
let widths: [CGFloat] = [380, 420, 300, 400, 220]
for (i, width) in widths.enumerated() {
    pill(NSRect(x: 300, y: top - height, width: width, height: height), rule)
    if i == widths.count - 1 {
        accent.setFill()
        NSRect(x: 300 + width + height * 0.7, y: top - height * 1.5, width: height * 0.5, height: height * 2).fill()
    }
    top -= height + gap
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try rep.representation(using: .png, properties: [:])!.write(to: out)
