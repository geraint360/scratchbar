// Draws Scratchbar's icon artwork: a note (lines of text and a cursor) on terracotta.
// Usage: swift scripts/make-icon.swift <out-folder>
// Writes note.png: the note alone on a transparent 1024×1024 canvas, the
// foreground layer of Resources/AppIcon.icon (the terracotta is that icon's fill).
// scripts/make-icon.sh then compiles the .icon with actool.
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
// The app's Theme colours.
let paper = color(0xfaf9f5), paperShade = color(0xf1ece4), rule = color(0xcfc5b8), accent = color(0xbc6a3a)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The note, in the icon's 1024-point canvas (the whole canvas is the tile).
let sheet = NSRect(x: 162, y: 112, width: 700, height: 808)
let sheetPath = NSBezierPath(roundedRect: sheet, xRadius: 57, yRadius: 57)
NSGraphicsContext.saveGraphicsState()
sheetPath.addClip()
NSGradient(starting: paper, ending: paperShade)!.draw(in: sheet, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Lines of text, with a cursor after the last one.
let height: CGFloat = 45, gap: CGFloat = 62
var top: CGFloat = 795
let widths: [CGFloat] = [472, 522, 373, 497, 273]
for (i, width) in widths.enumerated() {
    rule.setFill()
    NSBezierPath(roundedRect: NSRect(x: 249, y: top - height, width: width, height: height),
                 xRadius: height / 2, yRadius: height / 2).fill()
    if i == widths.count - 1 {
        accent.setFill()
        NSRect(x: 249 + width + height * 0.7, y: top - height * 1.5, width: height * 0.5, height: height * 2).fill()
    }
    top -= height + gap
}

let out = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("note.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
