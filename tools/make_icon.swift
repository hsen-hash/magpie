// Generate a 1024×1024 Magpie app icon as PNG.
// Run with: swift tools/make_icon.swift
import AppKit
import Foundation

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

// 1. Background — soft gradient squircle (navy → deep navy)
let corner = size * 0.225
let bgPath = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: corner, yRadius: corner
)
let gradient = NSGradient(colors: [
    NSColor(red: 0.18, green: 0.21, blue: 0.36, alpha: 1),
    NSColor(red: 0.08, green: 0.10, blue: 0.20, alpha: 1)
])
gradient?.draw(in: bgPath, angle: 90)

// 2. Magpie silhouette (SF Symbol bird.fill, tinted white)
let birdCfg = NSImage.SymbolConfiguration(pointSize: size * 0.62, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let bird = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(birdCfg) {
    let s = bird.size
    let dx = (size - s.width) / 2
    let dy = (size - s.height) / 2 - size * 0.03
    bird.draw(in: NSRect(x: dx, y: dy, width: s.width, height: s.height))
}

// 3. Small "stolen" folder accent in lower-right (gold)
let folderCfg = NSImage.SymbolConfiguration(pointSize: size * 0.22, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [
        NSColor(red: 0.97, green: 0.78, blue: 0.30, alpha: 1)
    ]))
if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(folderCfg) {
    let s = folder.size
    let dx = size * 0.66
    let dy = size * 0.16
    folder.draw(in: NSRect(x: dx, y: dy, width: s.width, height: s.height))
}

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bmp = NSBitmapImageRep(data: tiff),
      let pngData = bmp.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("PNG conversion failed\n".utf8))
    exit(1)
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let out = scriptDir.appendingPathComponent("Magpie-1024.png")
try pngData.write(to: out)
print("→ \(out.path)")
