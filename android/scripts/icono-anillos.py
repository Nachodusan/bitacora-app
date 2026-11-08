"""El ícono de Android: los anillos de la marca, como ícono adaptativo.

El mismo cálculo que ios/scripts/icono-anillos.swift (siete anillos tranquilos,
congelados en t=4), para que el ícono sea la misma figura en los dos teléfonos.

Es ADAPTATIVO, y no un vector suelto: con un vector suelto el launcher lo trata
como ícono viejo y lo achica dentro de un círculo blanco (visto en el emulador el
26/10/2026). Son dos capas: el fondo oscuro (`icono_fondo`) y los anillos al
frente (`icono_frente`), que van dentro de la zona segura —66 de los 108 dp—
porque cada launcher recorta con su forma.

    python3 android/scripts/icono-anillos.py android/app/src/main/res
"""
import os
import sys
import math

t = 4.0
lado = 108.0
c = lado / 2
# Dentro de la zona segura (radio 33), contando lo que salen las ondas.
radio_max = 29.0
radio_min = radio_max * 0.26
cantidad = 7

caminos = []
for i in range(cantidad):
    f = i / (cantidad - 1)
    r = radio_min + (radio_max - radio_min) * f
    puntos = []
    for k in range(180):
        a = k / 180 * 2 * math.pi
        onda = math.sin(3 * a + t * 0.18 + i * 0.5) * 0.045 + math.sin(2 * a - t * 0.11 + 1.3) * 0.03
        rr = r * (1 + onda * (0.75 + 0.35 * f))
        # En Android la y crece hacia abajo: se invierte para que coincida con iOS.
        puntos.append((c + rr * math.cos(a), c - rr * math.sin(a)))
    d = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in puntos) + " Z"
    alfa = int(round((0.85 - 0.25 * f) * 255))
    caminos.append(f'    <path android:strokeColor="#{alfa:02X}DBD4B3" android:strokeWidth="0.9" android:strokeLineJoin="round"\n'
                   f'        android:pathData="{d}" />')

pr = radio_min * 0.55
punto = (f'    <path android:fillColor="#EDA680" android:pathData="M{c - pr:.2f},{c:.2f}'
         f'a{pr:.2f},{pr:.2f} 0 1,0 {2 * pr:.2f},0a{pr:.2f},{pr:.2f} 0 1,0 -{2 * pr:.2f},0" />')

res = sys.argv[1] if len(sys.argv) > 1 else "."
cabecera = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generado por android/scripts/icono-anillos.py: la marca de Bitácora (docs/arquitectura.md,
     «La marca: los anillos»). Si cambia la animación, se regenera. -->
"""
frente = cabecera + """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
""" + "\n".join(caminos) + "\n" + punto + "\n</vector>\n"
fondo = cabecera + """<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#16180F" />
</shape>
"""
adaptativo = cabecera + """<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/icono_fondo" />
    <foreground android:drawable="@drawable/icono_frente" />
    <monochrome android:drawable="@drawable/icono_frente" />
</adaptive-icon>
"""
os.makedirs(os.path.join(res, "mipmap-anydpi"), exist_ok=True)
for ruta, texto in [("drawable/icono_frente.xml", frente), ("drawable/icono_fondo.xml", fondo),
                    ("mipmap-anydpi/icono.xml", adaptativo)]:
    with open(os.path.join(res, ruta), "w") as f:
        f.write(texto)
    print(ruta)
