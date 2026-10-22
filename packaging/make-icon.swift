import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let shape = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: 230,
    yRadius: 230
)
shape.addClip()

let backdrop = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.40, blue: 0.48, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1),
])
backdrop?.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 90)

let deck = NSBezierPath(
    roundedRect: NSRect(x: 156, y: 332, width: 712, height: 360),
    xRadius: 72,
    yRadius: 72
)
NSColor(white: 0, alpha: 0.34).setFill()
deck.fill()

func drawKey(x: CGFloat, y: CGFloat, pinned: Bool) {
    let width: CGFloat = 176
    let height: CGFloat = 176
    let lip = NSBezierPath(
        roundedRect: NSRect(x: x, y: y, width: width, height: height),
        xRadius: 40,
        yRadius: 40
    )
    let lift: CGFloat = pinned ? 30 : 14
    let faceRect = NSRect(x: x + 12, y: y + lift, width: width - 24, height: height - 28)
    let face = NSBezierPath(roundedRect: faceRect, xRadius: 30, yRadius: 30)

    if pinned {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 0.55, green: 0.32, blue: 0.05, alpha: 0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 18
        shadow.set()
    }
    let lipColor = pinned
        ? NSColor(srgbRed: 0.72, green: 0.46, blue: 0.14, alpha: 1)
        : NSColor(srgbRed: 0.28, green: 0.31, blue: 0.36, alpha: 1)
    lipColor.setFill()
    lip.fill()
    NSShadow().set()

    let faceColor = pinned
        ? NSColor(srgbRed: 0.96, green: 0.76, blue: 0.38, alpha: 1)
        : NSColor(srgbRed: 0.62, green: 0.66, blue: 0.72, alpha: 1)
    faceColor.setFill()
    face.fill()

    // 键帽上沿一条高光，小尺寸也会保留成一条亮边。
    let gloss = NSBezierPath(
        roundedRect: NSRect(x: faceRect.minX + 16, y: faceRect.maxY - 28, width: faceRect.width - 32, height: 10),
        xRadius: 5,
        yRadius: 5
    )
    NSColor(white: 1, alpha: pinned ? 0.55 : 0.28).setFill()
    gloss.fill()
}

let rowY: CGFloat = 424
drawKey(x: 214, y: rowY, pinned: false)
drawKey(x: 424, y: rowY, pinned: true)
drawKey(x: 634, y: rowY, pinned: false)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("icon render failed\n", stderr)
    exit(1)
}

let master = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keypin-icon.png")
try png.write(to: master)
try png.write(to: URL(fileURLWithPath: "/tmp/keypin-icon-1024.png"))

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keypin.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in sizes {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(pixels)", "\(pixels)", master.path, "--out", iconset.appendingPathComponent(name).path]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 { exit(task.terminationStatus) }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
