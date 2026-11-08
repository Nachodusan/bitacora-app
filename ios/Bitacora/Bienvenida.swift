import SwiftUI

/// Lo primero, antes que nada: qué es Bitácora, cómo se usa, qué queda en el
/// teléfono, y cómo te llama.
///
/// Hasta el 04/10/2026 era una sola pantalla en blanco con la pregunta del
/// nombre, sin nada que explicara la app: nadie le contaba a la persona qué
/// estaba abriendo. Dusan eligió estas tres pantallas en la maqueta, antes del
/// nombre, con el mismo fondo y los mismos botones que el resto de la app (la
/// pantalla blanca, además, en modo oscuro dejaba la letra clara sobre blanco).
///
/// Se pasa con «Siguiente» o deslizando. Los permisos del micrófono no se
/// piden acá: los pide `CapturaDeVoz` la primera vez que se graba o se llama,
/// que es cuando se entiende para qué son.
struct Bienvenida: View {
    @Environment(\.dismiss) private var dismiss
    private var config = Config.shared

    /// 0 a 2, las tres pantallas; 3, el registro (antes, el nombre).
    @State private var paso = 0

    var body: some View {
        ZStack {
            Fondo()
            TabView(selection: $paso) {
                pagina(icono: AnyView(VozViva().frame(width: 40, height: 40)),
                       titulo: "Un diario que te escucha") {
                    parrafo("Le cuentas tu día a Bitácora, hablando o escribiendo, y queda guardado en tu calendario.")
                    parrafo("No es terapia ni la reemplaza: te ayuda a ordenar lo que pasa para llevarlo a tu terapeuta.")
                }
                .tag(0)

                pagina(icono: AnyView(Image(systemName: "bubble.left").font(.system(size: 34, weight: .regular))),
                       titulo: "Tres maneras de contar algo") {
                    manera(AnyView(Image(systemName: "keyboard").font(.system(size: 19))),
                           "Escribe", "Te contesta por escrito.")
                    manera(AnyView(Microfono().frame(width: 20, height: 20)),
                           "Graba un mensaje", "Se transcribe en el teléfono.")
                    manera(AnyView(VozViva().frame(width: 22, height: 22)),
                           "Llama", "Una conversación hablada. La terminas tú.")
                }
                .tag(1)

                pagina(icono: AnyView(Image(systemName: "lock").font(.system(size: 34, weight: .regular))),
                       titulo: "Lo tuyo se queda contigo") {
                    parrafo("Tu voz se transcribe en el teléfono y nunca se sube.")
                    parrafo("Tus sesiones y tus notas quedan sólo aquí.")
                    parrafo("Si estás pasando un momento muy difícil, llama al *4141 (en Chile): es gratis y atiende a toda hora.")
                }
                .tag(2)

                Registro { perfil in empezar(perfil) }.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy(duration: 0.3), value: paso)

            if paso < 3 { puntos }
        }
    }

    // MARK: - Las tres pantallas

    private var puntos: some View {
        VStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == paso ? Paleta.musgo : Paleta.cartaBorde)
                        .frame(width: i == paso ? 22 : 8, height: 8)
                }
            }
            .padding(.top, 14)
            Spacer()
        }
        .animation(.snappy(duration: 0.25), value: paso)
        .accessibilityHidden(true)
    }

    private func pagina<Contenido: View>(icono: AnyView, titulo: String,
                                         @ViewBuilder contenido: () -> Contenido) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            icono
                .foregroundStyle(Paleta.musgo)
                .frame(width: 84, height: 84)
                .background(Circle().fill(Paleta.musgo.opacity(0.14)))
                .padding(.top, 96)
            Text(titulo)
                .font(.redonda(.largeTitle, .bold))
                .foregroundStyle(Paleta.tinta)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
            VStack(alignment: .leading, spacing: 16) { contenido() }
                .padding(.top, 20)
            Spacer(minLength: 0)
            boton("Siguiente") { paso += 1 }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
    }

    private func parrafo(_ texto: String) -> some View {
        Text(texto)
            .font(.redonda(.body))
            .foregroundStyle(Paleta.tintaSuave)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func manera(_ icono: AnyView, _ nombre: String, _ detalle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            icono
                .foregroundStyle(Paleta.musgo)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Paleta.carta))
                .overlay { Circle().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre)
                    .font(.redonda(.body, .semibold))
                    .foregroundStyle(Paleta.tinta)
                Text(detalle)
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func boton(_ texto: String, habilitado: Bool = true, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(texto)
                .font(.redonda(.body, .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(habilitado ? Paleta.musgo : Paleta.tintaSuave.opacity(0.18)))
                .foregroundStyle(habilitado ? Paleta.fondoAlto : Paleta.tintaSuave)
        }
        .disabled(!habilitado)
        .animation(.easeOut(duration: 0.2), value: habilitado)
    }

    /// Al terminar el registro, o al entrar a una cuenta que ya existía.
    private func empezar(_ perfil: PerfilDeCuenta) {
        config.nombre = perfil.nombre ?? ""
        // Se marca aunque lo haya salteado: la pregunta se hizo. Volver a
        // hacerla en cada arranque sería no haber escuchado la respuesta.
        config.nombrePreguntado = true
        dismiss()
        // Sin esperar. Si no hay red, el reintento al volver a primer plano
        // lo cubre.
        Task { await config.aplicar() }
    }
}
