#!/usr/bin/env python3
"""¿A qué nivel territorial se pueden construir indicadores estables? Municipio–año frente a subregión–año.

Antioquia tiene 125 municipios y pocos homicidios de mujeres por municipio y año. Con conteos tan bajos
una tasa municipal cambia mucho de un año a otro solo por azar. Este script mide qué tan escasos son los
datos en cada nivel (municipio, subregión, departamento) y deja una capa pública con supresión de cifras
pequeñas, como base de la versión anonimizada de los indicadores.

Fuentes (datos.gov.co, consultas agregadas; no se descargan registros individuales):
  * Policía Nacional / MinDefensa – Homicidio (m8fd-ahd9): homicidios de mujeres por municipio y año.
  * Gobernación de Antioquia – Suicidios por municipio (db67-sbus): solo se usa su tabla de municipios
    con código DANE y subregión (125 municipios, 9 subregiones). Es la división oficial del departamento.

Salidas (03_Fuentes_y_Datos/datos/procesados/):
  * antioquia_municipio_subregion.csv   código DANE, municipio y subregión.
  * antioquia_municipio_anio.csv        homicidios de mujeres por municipio y año, con ceros (cuadrícula completa).
  * viabilidad_nivel_territorial.csv    por nivel: celdas, % de celdas en cero, % con menos de 3 casos,
                                        media por celda y coeficiente de variación esperado por azar.
  * indicadores_publicos_municipio_anio.csv   capa pública: conteos de 1 y 2 se publican como «<3».
  * indicadores_publicos_subregion_anio.csv   capa pública por subregión (sin supresión si todas las celdas ≥ 3).

Coeficiente de variación por azar: si los casos de una celda siguen un proceso de Poisson con media m,
la desviación relativa esperada es 1/√m. Con m = 1 el ruido es del 100 %; con m = 25, del 20 %.

Uso:   .venv/bin/python scripts/viabilidad_nivel_territorial.py            (usa internet: datos.gov.co)
       .venv/bin/python scripts/viabilidad_nivel_territorial.py --local    (recalcula con los JSON ya descargados)
Cómo escalar: agregar la población municipal de mujeres (DANE) para tasas y suavizado bayesiano, y repetir
con Medicina Legal y Fiscalía cuando se consulten por municipio.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date
from pathlib import Path

from _entorno import RAIZ, avisar_si_fuera_de_venv, cargar_env, sin_acentos

API = "https://www.datos.gov.co/resource/{}.json"
CRUDOS = RAIZ / "03_Fuentes_y_Datos" / "datos" / "crudos"
PROC = RAIZ / "03_Fuentes_y_Datos" / "datos" / "procesados"
ANIOS = range(2015, 2026)  # 2015–2025: años completos
UMBRAL_PUBLICO = 3          # conteos de 1 y 2 se suprimen en la capa municipal pública

SUBREGION_NOMBRE = {
    "BAJO CAUCA": "Bajo Cauca", "MAGDALENA MEDIO": "Magdalena Medio", "NORDESTE": "Nordeste", "NORTE": "Norte",
    "OCCIDENTE": "Occidente", "ORIENTE": "Oriente", "SUROESTE": "Suroeste", "URABA": "Urabá",
    "VALLE DE ABURRA": "Valle de Aburrá",
}


def consultar(dataset: str, nombre: str, carpeta: str, **soql: str) -> list[dict]:
    """Consulta agregada SoQL; guarda la respuesta cruda con su URL y fecha."""
    env = cargar_env()
    params = {f"${k}": v for k, v in soql.items()}
    params.setdefault("$limit", "50000")
    url = API.format(dataset) + "?" + urllib.parse.urlencode(params)
    cab = {"User-Agent": env.get("SCRAPING_USER_AGENT") or "Mozilla/5.0 (proyecto academico)"}
    if env.get("SOCRATA_APP_TOKEN"):
        cab["X-App-Token"] = env["SOCRATA_APP_TOKEN"]
    tiempo = float(env.get("REQUEST_TIMEOUT_SECONDS") or 120)
    for intento in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=cab), timeout=tiempo) as r:
                filas = json.load(r)
            break
        except OSError as e:
            if intento == 2:
                raise
            print(f"  reintento {intento + 1} ({nombre}): {e}")
            time.sleep(10)
    destino = CRUDOS / carpeta
    destino.mkdir(parents=True, exist_ok=True)
    (destino / f"{nombre}.json").write_text(json.dumps(
        {"dataset": dataset, "url": url, "consultado": date.today().isoformat(), "filas": filas},
        ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  {carpeta}/{nombre}: {len(filas)} filas")
    return filas


def leer_crudo(carpeta: str, nombre: str) -> list[dict]:
    return json.loads((CRUDOS / carpeta / f"{nombre}.json").read_text(encoding="utf-8"))["filas"]


def resumen(conteos: list[int], nivel: str, unidades: int) -> dict:
    media = statistics.fmean(conteos)
    return {
        "nivel": nivel, "unidades": unidades, "anios": f"{ANIOS.start}-{ANIOS.stop - 1}", "celdas": len(conteos),
        "casos": sum(conteos),
        "pct_celdas_cero": round(100 * sum(c == 0 for c in conteos) / len(conteos), 1),
        "pct_celdas_menos_3": round(100 * sum(c < 3 for c in conteos) / len(conteos), 1),
        "media_por_celda": round(media, 2), "mediana_por_celda": statistics.median(conteos),
        "cv_azar_pct": round(100 / math.sqrt(media), 1) if media > 0 else None,
    }


def escribir(nombre: str, filas: list[dict]) -> None:
    PROC.mkdir(parents=True, exist_ok=True)
    with (PROC / nombre).open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0]))
        w.writeheader()
        w.writerows(filas)
    print(f"  procesados/{nombre}: {len(filas)} filas")


def main() -> int:
    avisar_si_fuera_de_venv()
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", action="store_true", help="no consulta la API; usa los JSON ya guardados")
    args = ap.parse_args()

    if args.local:
        muni_reg, pol = leer_crudo("gobernacion", "municipios_subregion"), leer_crudo("policia", "antioquia_municipio_anio")
    else:
        print("Consultando datos.gov.co...")
        muni_reg = consultar("db67-sbus", "municipios_subregion", "gobernacion",
                             select="codigomunicipio, nombremunicipio, nombreregion, count(*) as n",
                             group="codigomunicipio, nombremunicipio, nombreregion")
        pol = consultar("m8fd-ahd9", "antioquia_municipio_anio", "policia",
                        select="cod_muni, municipio, date_extract_y(fecha_hecho) as anio, sum(cantidad) as n",
                        where="sexo='FEMENINO' AND cod_depto='05'", group="cod_muni, municipio, anio")

    # Municipios y subregiones (125 y 9)
    municipios = {r["codigomunicipio"]: (r["nombremunicipio"], SUBREGION_NOMBRE.get(sin_acentos(r["nombreregion"]).upper(), r["nombreregion"]))
                  for r in muni_reg}
    escribir("antioquia_municipio_subregion.csv",
             [{"cod_muni": k, "municipio": v[0], "subregion": v[1]} for k, v in sorted(municipios.items())])

    # Cuadrícula completa municipio × año (los municipios sin registro en un año valen 0)
    n = defaultdict(int)
    sin_codigo = 0
    for r in pol:
        anio = int(r["anio"])
        if anio not in ANIOS:
            continue
        if r["cod_muni"] not in municipios:
            sin_codigo += int(float(r["n"]))
            continue
        n[(r["cod_muni"], anio)] += int(float(r["n"]))
    if sin_codigo:
        print(f"  AVISO: {sin_codigo} casos con código de municipio fuera de la tabla oficial (se excluyen)")
    filas_muni = [{"cod_muni": c, "municipio": municipios[c][0], "subregion": municipios[c][1], "anio": a, "n": n[(c, a)]}
                  for c in sorted(municipios) for a in ANIOS]
    escribir("antioquia_municipio_anio.csv", filas_muni)

    # Agregación jerárquica: municipio → subregión → departamento
    sub = defaultdict(int)
    for f in filas_muni:
        sub[(f["subregion"], f["anio"])] += f["n"]
    dep = defaultdict(int)
    for (s, a), v in sub.items():
        dep[a] += v
    subregiones = sorted({v[1] for v in municipios.values()})
    viab = [
        resumen([f["n"] for f in filas_muni], "Municipio–año", len(municipios)),
        resumen([sub[(s, a)] for s in subregiones for a in ANIOS], "Subregión–año", len(subregiones)),
        resumen([dep[a] for a in ANIOS], "Departamento–año", 1),
    ]
    # Variantes: subregiones sin el Valle de Aburrá (concentra la mayoría de los casos) y municipio con
    # todos los años sumados (gana estabilidad, pierde la evolución en el tiempo)
    viab.append(resumen([sub[(s, a)] for s in subregiones if s != "Valle de Aburrá" for a in ANIOS],
                        "Subregión–año sin Valle de Aburrá", len(subregiones) - 1))
    viab.append(resumen([sum(n[(c, a)] for a in ANIOS) for c in sorted(municipios)],
                        "Municipio, años acumulados", len(municipios)))
    escribir("viabilidad_nivel_territorial.csv", viab)

    # Capa pública anonimizada: supresión de conteos pequeños por municipio
    escribir("indicadores_publicos_municipio_anio.csv",
             [{**{k: f[k] for k in ("cod_muni", "municipio", "subregion", "anio")},
               "homicidios_mujeres": f["n"] if f["n"] == 0 or f["n"] >= UMBRAL_PUBLICO else f"<{UMBRAL_PUBLICO}"}
              for f in filas_muni])
    escribir("indicadores_publicos_subregion_anio.csv",
             [{"subregion": s, "anio": a,
               "homicidios_mujeres": sub[(s, a)] if sub[(s, a)] == 0 or sub[(s, a)] >= UMBRAL_PUBLICO else f"<{UMBRAL_PUBLICO}"}
              for s in subregiones for a in ANIOS])

    for v in viab:
        print(f"  {v['nivel']}: {v['celdas']} celdas, {v['pct_celdas_cero']} % en cero, "
              f"{v['pct_celdas_menos_3']} % < 3, media {v['media_por_celda']}, CV por azar {v['cv_azar_pct']} %")
    return 0


if __name__ == "__main__":
    sys.exit(main())
