#!/usr/bin/env swift
// tools/make-app-icon.swift
//
// Genera un PNG 1024×1024 con un reloj blanco sobre llamas naranjas
// para usar como ícono de la app (.app bundle).  Lo invoca
// `make-app-icon.sh` para luego empaquetarlo en un `.icns`.
//
// Uso: swift tools/make-app-icon.swift OUTPUT_PATH

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let canvas: CGFloat = 1024

let img = NSImage(size: NSSize(width: canvas, height: canvas))
img.lockFocus()

let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let corner: CGFloat = canvas * 0.18

// 1) Fondo: rounded-rect con gradiente azul oscuro → casi negro.
NSGraphicsContext.saveGraphicsState()
let bgPath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
bgPath.setClip()
if let gradient = NSGradient(
    starting: NSColor(red: 0.13, green: 0.16, blue: 0.30, alpha: 1),
    ending:   NSColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)
) {
    gradient.draw(in: rect, angle: -90)
}
NSGraphicsContext.restoreGraphicsState()

/// Dibuja un SF Symbol tinteado con `color` centrado en `center`.
func drawSymbol(_ name: String, pointSize: CGFloat, color: NSColor, at center: NSPoint) {
    let palette = NSImage.SymbolConfiguration(paletteColors: [color])
    let conf = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        .applying(palette)
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(conf) else { return }
    let r = NSRect(x: center.x - sym.size.width / 2,
                   y: center.y - sym.size.height / 2,
                   width: sym.size.width, height: sym.size.height)
    sym.draw(in: r)
}

// 2) Llama grande, naranja-cálido, ligeramente abajo del centro.
drawSymbol("flame.fill",
           pointSize: canvas * 0.85,
           color: NSColor(red: 1.0, green: 0.50, blue: 0.05, alpha: 1),
           at: NSPoint(x: canvas * 0.50, y: canvas * 0.42))

// 3) Reloj blanco arriba — un poco arriba del centro para que se vea
//    "saliendo" de las llamas.
drawSymbol("clock",
           pointSize: canvas * 0.50,
           color: NSColor.white,
           at: NSPoint(x: canvas * 0.50, y: canvas * 0.58))

img.unlockFocus()

// 4) Volcar a PNG.
guard let tiff = img.tiffRepresentation,
      let bm = NSBitmapImageRep(data: tiff),
      let png = bm.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("ERROR: no pude generar el PNG\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath) (\(png.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("ERROR writing \(outputPath): \(error)\n".utf8))
    exit(1)
}
