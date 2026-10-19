#!/usr/bin/env swift
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha])!
}
func render(_ size: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let square = CGMutablePath()
    // A smooth superellipse: continuous curvature instead of four circular corners.
    for step in 0...720 {
        let angle = CGFloat(step) / 720 * .pi * 2
        func curve(_ value: CGFloat) -> CGFloat { (value < 0 ? -1 : 1) * pow(abs(value), 2 / 4.2) }
        let point = CGPoint(x: 512 + 414 * curve(cos(angle)), y: 518 + 414 * curve(sin(angle)))
        if step == 0 { square.move(to: point) } else { square.addLine(to: point) }
    }
    square.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: color(0, 0, 0, 0.32))
    context.addPath(square); context.setFillColor(color(0.035, 0.043, 0.07)); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(square); context.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0.095, 0.11, 0.16), color(0.025, 0.03, 0.055)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 200, y: 960), end: CGPoint(x: 800, y: 80), options: [])
    let haze = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0.15, 0.35, 0.8, 0.15), color(0.08, 0.1, 0.2, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(haze, startCenter: CGPoint(x: 330, y: 760), startRadius: 0, endCenter: CGPoint(x: 330, y: 760), endRadius: 650, options: [])
    context.restoreGState()
    context.addPath(square); context.setStrokeColor(color(0.65, 0.72, 0.9, 0.13)); context.setLineWidth(2); context.strokePath()
    let center = CGPoint(x: 512, y: 532)
    func ring(radius: CGFloat, width: CGFloat, start: CGFloat, end: CGFloat, colors: [CGColor]) {
        context.setLineWidth(width); context.setStrokeColor(colors[0].copy(alpha: 0.13)!)
        context.strokeEllipse(in: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2))
        let arc = CGMutablePath(); arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.saveGState(); context.setShadow(offset: .zero, blur: 22, color: colors[0].copy(alpha: 0.6)); context.setStrokeColor(colors[0]); context.setLineCap(.round); context.addPath(arc); context.strokePath(); context.restoreGState()
        context.saveGState(); context.addPath(arc.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 0)); context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 250, y: 800), end: CGPoint(x: 780, y: 250), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); context.restoreGState()
    }
    ring(radius: 279, width: 48, start: .pi * 0.73, end: .pi * 2.45, colors: [color(0.12, 0.48, 1), color(0.2, 0.89, 1)])
    ring(radius: 208, width: 44, start: .pi * 0.52, end: .pi * 2.02, colors: [color(0.48, 0.3, 1), color(0.88, 0.37, 1)])
    // Two restrained server bays; a bright pulse forms the app's central signature.
    context.setLineWidth(7); context.setStrokeColor(color(0.67, 0.74, 0.88, 0.65))
    for y in [CGFloat(472), CGFloat(554)] {
        context.addPath(CGPath(roundedRect: CGRect(x: 423, y: y, width: 178, height: 58), cornerWidth: 15, cornerHeight: 15, transform: nil)); context.strokePath()
        context.setFillColor(color(0.36, 0.75, 1)); context.fillEllipse(in: CGRect(x: 445, y: y+24, width: 10, height: 10))
    }
    let pulse = CGMutablePath(); pulse.move(to: CGPoint(x: 363, y: 532))
    for point in [CGPoint(x: 455,y: 532), CGPoint(x: 482,y: 562), CGPoint(x: 510,y: 494), CGPoint(x: 540,y: 550), CGPoint(x: 562,y: 532), CGPoint(x: 660,y: 532)] { pulse.addLine(to: point) }
    context.saveGState(); context.setShadow(offset: .zero, blur: 13, color: color(0.3, 0.75, 1, 0.6)); context.setLineWidth(10); context.setLineCap(.round); context.setLineJoin(.round); context.setStrokeColor(color(0.84, 0.96, 1)); context.addPath(pulse); context.strokePath(); context.restoreGState()
    return bitmap
}
let master = render(1024)
try master.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
for (name, size) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    try render(size).representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_" + name + ".png"))
}
print("Generated 1024px master and complete macOS iconset")
