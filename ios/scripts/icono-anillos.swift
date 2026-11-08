// El ícono de la app: los anillos de `Anillos.swift` en su estado tranquilo,
// quietos en un instante elegido, sobre el fondo de la app.
//
// Usa la misma fórmula que la animación para que el ícono y la marca que se
// mueve en la pantalla sean la misma figura. Si cambia una, se regenera la otra:
//
//     swift ios/scripts/icono-anillos.swift ios/Bitacora/Assets.xcassets/AppIcon.appiconset/icono.png
import AppKit
import CoreGraphics
import Foundation

let lado = 1024
let salida = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icono.png"

// El instante que se congela. Elegido a ojo: las ondas quedan repartidas, sin
// un lado más aplastado que el otro.
let t = 4.0

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let espacio = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: 0,
                    space: espacio, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// El fondo: los dos tonos de `Fondo()` en modo oscuro, de arriba hacia abajo.
let degradado = CGGradient(colorsSpace: espacio, colors: [rgb(0x16180F), rgb(0x121409)] as CFArray,
                           locations: [0, 1])!
ctx.drawLinearGradient(degradado, start: CGPoint(x: 0, y: CGFloat(lado)), end: .zero, options: [])

let c = CGPoint(x: CGFloat(lado) / 2, y: CGFloat(lado) / 2)
// Más chico que en la app: iOS recorta las esquinas, y la figura tiene que
// respirar dentro del cuadrado redondeado.
let radioMax = CGFloat(lado) / 2 * 0.70
let radioMin = radioMax * 0.26
let cantidad = 7
let crema = (r: 0.86, g: 0.83, b: 0.70)

ctx.setLineWidth(9)
ctx.setLineJoin(.round)
for i in 0..<cantidad {
    let f = Double(i) / Double(cantidad - 1)
    let fi = Double(i)
    let r = Double(radioMin + (radioMax - radioMin) * CGFloat(f))
    let camino = CGMutablePath()
    let pasos = 360
    for k in 0...pasos {
        let a = Double(k) / Double(pasos) * 2 * .pi
        // La onda tranquila de `Anillos`.
        let onda = sin(3 * a + t * 0.18 + fi * 0.5) * 0.045 + sin(2 * a - t * 0.11 + 1.3) * 0.03
        let rr = r * (1 + onda * (0.75 + 0.35 * f))
        let p = CGPoint(x: c.x + CGFloat(rr * cos(a)), y: c.y + CGFloat(rr * sin(a)))
        if k == 0 { camino.move(to: p) } else { camino.addLine(to: p) }
    }
    camino.closeSubpath()
    ctx.addPath(camino)
    ctx.setStrokeColor(CGColor(srgbRed: crema.r, green: crema.g, blue: crema.b, alpha: 0.85 - 0.25 * f))
    ctx.strokePath()
}

let pr = radioMin * 0.55
ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.65, blue: 0.50, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2))

let imagen = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: imagen)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: salida))
print("listo: \(salida)")
