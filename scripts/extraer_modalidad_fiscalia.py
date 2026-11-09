#!/usr/bin/env python3
"""¿Qué dicen los datos abiertos de la Fiscalía sobre la modalidad de cada registro de feminicidio en Antioquia?

Consulta agregada a Fiscalía General de la Nación – Víctimas V3 (hr73-zqjf), delito «Feminicidio Art. 104A»,
departamento del hecho = Antioquia, todos los años. Cuenta registros por los campos `modalidad_homicidio_femi`
y `caracterizacion_homicidio_femi`. El conjunto no tiene un campo con el literal del art. 104A que aplica a
cada registro: esa es la información que el catalogador de la tesis busca reconstruir.

Salida: 03_Fuentes_y_Datos/datos/procesados/fiscalia_antioquia_modalidad.csv (campo, valor, n, pct).
Uso:   .venv/bin/python scripts/extraer_modalidad_fiscalia.py          (usa internet; consulta lenta, ~1-3 min)
       .venv/bin/python scripts/extraer_modalidad_fiscalia.py --local  (recalcula con los JSON guardados)
"""
from __future__ import annotations

import argparse
import sys

from _entorno import avisar_si_fuera_de_venv
from viabilidad_nivel_territorial import consultar, escribir, leer_crudo

CAMPOS = ("modalidad_homicidio_femi", "caracterizacion_homicidio_femi")


def main() -> int:
    avisar_si_fuera_de_venv()
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", action="store_true", help="no consulta la API; usa los JSON ya guardados")
    args = ap.parse_args()
    filas = []
    for campo in CAMPOS:
        nombre = f"antioquia_feminicidio_{campo}"
        datos = leer_crudo("fiscalia", nombre) if args.local else consultar(
            "hr73-zqjf", nombre, "fiscalia", select=f"{campo}, count(*) as n",
            where="delito like 'Feminicidio%' AND departamento_hecho_origen='Antioquia'", group=campo, order="n DESC")
        total = sum(int(d["n"]) for d in datos)
        for d in datos:
            filas.append({"campo": campo, "valor": d.get(campo) or "(vacío)", "n": int(d["n"]),
                          "pct": round(100 * int(d["n"]) / total, 1)})
        print(f"  {campo}: {total} registros")
    escribir("fiscalia_antioquia_modalidad.csv", filas)
    return 0


if __name__ == "__main__":
    sys.exit(main())
