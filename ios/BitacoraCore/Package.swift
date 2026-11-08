// swift-tools-version: 5.9
import PackageDescription

// Núcleo portable de la bitácora.
//
// Regla de este paquete: SOLO Foundation. Nada de SwiftUI, Speech, AVFoundation,
// SwiftData ni UIKit. Todo lo que entra acá tiene que compilar tal cual con el
// Swift Android SDK. Si un archivo necesita un framework de Apple, no va acá:
// va en el target iOS, en /ios/Bitacora.
let package = Package(
    name: "BitacoraCore",
    // macOS está sólo para poder correr `swift test` desde la terminal sin
    // levantar el simulador. La app es iOS 17+.
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "BitacoraCore", targets: ["BitacoraCore"])
    ],
    targets: [
        .target(name: "BitacoraCore"),
        .testTarget(name: "BitacoraCoreTests", dependencies: ["BitacoraCore"])
    ]
)
