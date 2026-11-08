import SwiftUI

/// El diseño de la app: paleta y composición, en un solo lugar.
///
/// Salió de comparar cinco estéticas en una galería y quedarse con una. Las
/// otras cuatro están en el historial de git si alguna vez hay que volver a
/// mirarlas; acá quedó sólo la elegida, sin la maquinaria de temas, porque un
/// selector con una opción es peso muerto.
///
/// Dos ideas la ordenan:
///
/// - **Un color para vos, otro para Bitácora.** El mismo par dice quién habla en los
///   globos y qué se pinta en el calendario. No hace falta leer para saber qué
///   está pasando. La luz de la voz quedó afuera de esa regla: es azul siempre,
///   porque cambiar de color con cada turno parecía una luz de fiesta.
/// - **Se usa de noche.** Media bitácora se dicta a las dos de la mañana, así
///   que el modo oscuro no es una variante: es el caso principal.
enum Paleta {

    struct Tono {
        let claro: UInt32
        let oscuro: UInt32
    }

    // MARK: - Color

    // PAPEL Y TINTA, NO PANTALLA. Hasta el 01/10/2026 esto era grafito frío con
    // azul marino y dorado: una app de tecnología. Dusan pidió que se pareciera
    // a Claude o a ChatGPT, y lo que define ese aspecto no es el color sino la
    // estructura — la IA habla plano a todo el ancho, sin globo— más una regla
    // de color: neutros CÁLIDOS, nunca grises azulados.
    //
    // El acento es verde musgo y no el terracota de Claude. Fue a propósito:
    // crema con serif y acento terracota es un cliché con nombre propio, y
    // copiarlo entero era quedarse sin cara. El papel tira apenas a verde para
    // acompañarlo.
    static let fondoAltoT  = Tono(claro: 0xF4F4ED, oscuro: 0x16180F)
    static let fondoBajoT  = Tono(claro: 0xEFEFE6, oscuro: 0x121409)
    static let tintaT      = Tono(claro: 0x1F1E1B, oscuro: 0xEDEBE4)
    static let tintaSuaveT = Tono(claro: 0x63605A, oscuro: 0xA29D92)
    static let tintaTenueT = Tono(claro: 0x96928A, oscuro: 0x6F6B62)
    /// Tu globo: el papel, un punto más oscuro. Nunca un color.
    static let globoVosT   = Tono(claro: 0xE8E9DE, oscuro: 0x23261C)
    /// El acento: el durazno de la marca, el color de Bitácora (26/10/2026;
    /// hasta ese día era un verde musgo, 4F6029 / A8C070). Los nombres quedaron
    /// por historia: `musgo` y `vos` hoy son durazno en toda la app.
    ///
    /// En modo oscuro es el durazno de la marca (`Marca.durazno`, EDA680). En
    /// claro va más oscuro, B8603A: el de la marca sobre fondo claro casi no se
    /// lee como texto, y con letra blanca encima no alcanza el contraste.
    static let musgoT      = Tono(claro: 0xB8603A, oscuro: 0xEDA680)
    static let musgoSuaveT = Tono(claro: 0xC77A55, oscuro: 0xD9946F)
    static let vosT        = Tono(claro: 0xB8603A, oscuro: 0xEDA680)
    static let vosClaroT   = Tono(claro: 0xC77A55, oscuro: 0xD9946F)
    static let bitacoraT       = Tono(claro: 0x8A6A1E, oscuro: 0xC9A340)
    static let bitacoraClaroT  = Tono(claro: 0xA3822F, oscuro: 0xDCBB63)
    static let globoBitacoraT  = Tono(claro: 0xFFFFFF, oscuro: 0x1D2016)
    static let cartaT      = Tono(claro: 0xFFFFFF, oscuro: 0x1D2016)
    static let cartaBordeT = Tono(claro: 0xE2E3D8, oscuro: 0x2A2E20)

    // Estados: cumplido / no cumplido / sin datos.
    //
    // Salieron del validador de paletas, no de elegirlos a ojo. Verdemar y
    // óxido se separan a ΔE 10.3 en claro y 9.2 en oscuro. El dorado de Bitácora
    // existe en esta versión justamente porque el bronce que probé primero
    // quedaba a ΔE 4.9 del óxido, y los dos conviven en Hábitos.
    //
    // Aun así, estos tres nunca viajan solos: siempre con ícono y etiqueta.
    // El color confirma, no informa.
    static let verdeT = Tono(claro: 0x0F7A70, oscuro: 0x2FA294)
    static let rojoT  = Tono(claro: 0xA93226, oscuro: 0xCE6152)
    static let grisT  = Tono(claro: 0x7F8A8F, oscuro: 0x78878E)

    // El color de las notas sueltas en el calendario.
    //
    // Celeste, y es el único azul de la app a propósito: Dusan pidió que las
    // notas se distingan de las conversaciones a simple vista («con un azul, un
    // celeste»). Todo lo demás es musgo y neutros cálidos, así que un frío se
    // reconoce sin leer nada. Igual va siempre con su ícono y la palabra «Nota»:
    // el color confirma, no informa.
    static let notaT  = Tono(claro: 0x2B6F9E, oscuro: 0x7EC3EA)

    /// Un color que cambia con el modo del sistema.
    static func adaptativo(_ t: Tono) -> Color {
        Color(uiColor: UIColor { rasgos in
            rasgos.userInterfaceStyle == .dark ? UIColor(hex: t.oscuro) : UIColor(hex: t.claro)
        })
    }

    static var fondoAlto: Color  { adaptativo(fondoAltoT) }
    static var fondoBajo: Color  { adaptativo(fondoBajoT) }
    static var tinta: Color      { adaptativo(tintaT) }
    static var tintaSuave: Color { adaptativo(tintaSuaveT) }
    static var tintaTenue: Color { adaptativo(tintaTenueT) }
    static var globoVos: Color   { adaptativo(globoVosT) }
    static var musgo: Color      { adaptativo(musgoT) }
    static var musgoSuave: Color { adaptativo(musgoSuaveT) }
    static var vos: Color        { adaptativo(vosT) }
    static var vosClaro: Color   { adaptativo(vosClaroT) }
    static var bitacora: Color       { adaptativo(bitacoraT) }
    static var bitacoraClaro: Color  { adaptativo(bitacoraClaroT) }
    static var globoBitacora: Color  { adaptativo(globoBitacoraT) }
    static var verde: Color      { adaptativo(verdeT) }
    static var rojo: Color       { adaptativo(rojoT) }
    static var gris: Color       { adaptativo(grisT) }
    static var nota: Color       { adaptativo(notaT) }
    static var carta: Color      { adaptativo(cartaT) }
    static var cartaBorde: Color { adaptativo(cartaBordeT) }

    static var degradadoVos: LinearGradient {
        LinearGradient(colors: [vosClaro, vos], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var degradadoBitacora: LinearGradient {
        LinearGradient(colors: [bitacoraClaro, bitacora], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// El fondo de toda la app: un degradado liso.
///
/// Sin manchas de color difuminadas, a propósito. Este diseño ordena por
/// espacio, y un fondo tranquilo es lo que deja que el aire haga su trabajo.
struct Fondo: View {
    var body: some View {
        LinearGradient(colors: [Paleta.fondoAlto, Paleta.fondoBajo],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    /// Un bloque de contenido: tarjeta muy redondeada, con sombra suave.
    func carta(radio: CGFloat? = nil) -> some View {
        let r = radio ?? 24
        return self.background {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Paleta.carta)
                .overlay {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Paleta.cartaBorde, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }
}

extension Font {
    /// Tipografía redondeada en toda la app.
    static func redonda(_ estilo: Font.TextStyle, _ peso: Font.Weight = .regular) -> Font {
        .system(estilo, design: .rounded, weight: peso)
    }

    /// La letra de lo que dice Bitácora.
    ///
    /// Serifa, y es la decisión más propia de este diseño: las dos voces se
    /// distinguen por la LETRA y no sólo por el lugar en la pantalla. Vos
    /// hablás en palo seco adentro de un globo; ella contesta en serifa, a todo
    /// el ancho, como un texto para leer.
    ///
    /// Es `.serif` del sistema —New York, la cara con la que Apple compone sus
    /// libros y los transcripts de Podcasts— y no una fuente descargada: viene
    /// con el teléfono, acompaña Dynamic Type sin trabajo y no suma un archivo
    /// al bundle. Si alguna vez hace falta una con más carácter, el cambio es
    /// en esta función y en ningún otro lado.
    static func dicha(_ estilo: Font.TextStyle, _ peso: Font.Weight = .regular) -> Font {
        .system(estilo, design: .serif, weight: peso)
    }

    /// Para las cifras grandes, que no siguen la escala de estilos.
    static func cifra(_ tamano: CGFloat, _ peso: Font.Weight = .bold) -> Font {
        .system(size: tamano, weight: peso, design: .rounded)
    }
}


/// La cápsula clara que se repite en los botones secundarios.
struct CapsulaTenue: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.redonda(.footnote, .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Paleta.carta))
            .overlay { Capsule().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
            .foregroundStyle(Paleta.tinta)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == CapsulaTenue {
    static var capsulaTenue: CapsulaTenue { CapsulaTenue() }
}
