package ar.dusan.bitacora.datos

import ar.dusan.bitacora.nucleo.json
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * Una lista guardada en un archivo JSON del teléfono, que la pantalla puede mirar.
 *
 * Archivos y no una base: es una sola persona, con decenas de cosas y no
 * millones, y un archivo por tipo es lo mismo que hace el iPhone (un almacén
 * para las charlas, otro para las sesiones, otro para las notas): si uno se
 * rompe, los demás siguen.
 *
 * Se escribe entero en cada cambio, primero a un temporal y después se
 * renombra: si la app muere en el medio, queda el archivo anterior, no uno
 * cortado. Y si al abrir un archivo no se puede leer, se aparta con otro nombre
 * en vez de pisarlo con una lista vacía: un archivo roto se puede rescatar a
 * mano, uno pisado no.
 */
class Almacen<T>(private val archivo: File, serializador: KSerializer<T>) {
    private val lista = ListSerializer(serializador)
    private val _todo = MutableStateFlow(leer())
    val todo: StateFlow<List<T>> = _todo

    val valor: List<T> get() = _todo.value

    @Synchronized
    fun cambiar(f: (List<T>) -> List<T>) {
        val nuevo = f(_todo.value)
        _todo.value = nuevo
        val temporal = File(archivo.path + ".tmp")
        temporal.writeText(json.encodeToString(lista, nuevo))
        temporal.renameTo(archivo)
    }

    private fun leer(): List<T> {
        if (!archivo.exists()) return emptyList()
        return runCatching { json.decodeFromString(lista, archivo.readText()) }.getOrElse {
            archivo.renameTo(File(archivo.path + ".roto-" + System.currentTimeMillis()))
            emptyList()
        }
    }
}
