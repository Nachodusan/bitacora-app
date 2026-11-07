import SwiftUI

/// Un turno de una charla. Las dos voces se dibujan distinto a propósito.
///
/// LO QUE DICE BITÁCORA NO TIENE GLOBO. Va plano, a todo el ancho, en serifa.
/// Es la decisión que más cambia la pantalla: un globo redondeado de color
/// dice "mensajería", y esto es un diario. Los productos de IA que se ven
/// bien hace rato que dejaron de poner a la máquina adentro de una burbuja.
///
/// Lo tuyo sí lleva globo, pero del color del papel —un punto más oscuro—,
/// nunca de color. Alcanza para saber de quién es cada cosa sin que parezca
/// un chat.
///
/// Y hay un motivo técnico encima del estético: con Dynamic Type grande, el
/// texto crece y un globo de radio fijo se deforma. El texto plano no.
///
/// Vive aparte desde el 04/10/2026, cuando el calendario empezó a mostrar las
/// charlas guardadas igual que el chat: un solo dibujo para los dos lugares.
/// `lineas` corta el texto en el adelanto de la tarjeta del calendario.
struct TurnoDibujado: View {
    let turno: Turno
    var tentativo = false
    var lineas: Int? = nil

    var body: some View {
        if turno.de == .bitacora {
            Text(turno.texto)
                .font(.dicha(.body))
                .foregroundStyle(Paleta.tinta)
                .lineSpacing(3)
                .lineLimit(lineas)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(tentativo ? 0.6 : 1)
        } else {
            HStack {
                Spacer(minLength: 44)
                Text(turno.texto)
                    .font(.redonda(.callout))
                    .foregroundStyle(Paleta.tinta)
                    .lineLimit(lineas)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 18, bottomLeading: 18,
                                               bottomTrailing: 5, topTrailing: 18),
                            style: .continuous)
                            .fill(Paleta.globoVos)
                    }
                    // Lo que estás diciendo todavía: entero y con un borde verde
                    // suave, como un mensaje que se está escribiendo. Antes era
                    // el mismo globo a media luz.
                    .overlay {
                        if tentativo {
                            UnevenRoundedRectangle(
                                cornerRadii: .init(topLeading: 18, bottomLeading: 18,
                                                   bottomTrailing: 5, topTrailing: 18),
                                style: .continuous)
                                .strokeBorder(Paleta.musgo.opacity(0.4), lineWidth: 1)
                        }
                    }
            }
        }
    }
}
