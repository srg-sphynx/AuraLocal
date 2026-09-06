//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import AppKit
import CoreGraphics

// Renders a 1024×1024 app icon: deep-indigo glass squircle with an "aura" orb.
let size = 1024
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let inset: CGFloat = 80
let body = rect.insetBy(dx: inset, dy: inset)
let corner: CGFloat = 200

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// Background squircle gradient (near-black -> indigo tint).
let path = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.saveGState()
ctx.addPath(path); ctx.clip()
let bgColors = [color(0.07, 0.07, 0.09), color(0.11, 0.10, 0.20)] as CFArray
let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Corner glow (indigo top-left, emerald bottom-right) — mirrors the app ambient.
ctx.setBlendMode(.screen)
let glow1 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [color(0.37, 0.36, 0.90, 0.55), color(0,0,0,0)] as CFArray, locations: [0,1])!
ctx.drawRadialGradient(glow1, startCenter: CGPoint(x: 300, y: 760), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 760), endRadius: 560, options: [])
let glow2 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [color(0.26, 0.89, 0.33, 0.30), color(0,0,0,0)] as CFArray, locations: [0,1])!
ctx.drawRadialGradient(glow2, startCenter: CGPoint(x: 740, y: 260), startRadius: 0,
                       endCenter: CGPoint(x: 740, y: 260), endRadius: 520, options: [])
ctx.setBlendMode(.normal)

// Central orb — concentric rings.
let center = CGPoint(x: size/2, y: size/2)
for (i, radius) in [220.0, 160.0, 100.0].enumerated() {
    let alpha = 0.18 + Double(i) * 0.14
    ctx.setStrokeColor(color(0.76, 0.76, 1.0, alpha))
    ctx.setLineWidth(14 - CGFloat(i) * 2)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
}
// Orb core
let core = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [color(0.82, 0.82, 1.0), color(0.37, 0.36, 0.90)] as CFArray, locations: [0,1])!
ctx.drawRadialGradient(core, startCenter: center, startRadius: 0,
                       endCenter: center, endRadius: 92, options: [])
ctx.restoreGState()

// Glass top highlight + inner stroke.
ctx.addPath(path)
ctx.setStrokeColor(color(1, 1, 1, 0.16)); ctx.setLineWidth(3); ctx.strokePath()

guard let cgImage = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try? png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
