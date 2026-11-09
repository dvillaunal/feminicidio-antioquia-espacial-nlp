#!/usr/bin/env python3
"""Búsqueda sistemática de literatura en OpenAlex con conteos tipo PRISMA (reproducible y auditable).

Qué hace:
  1. Identificación: lanza una cadena booleana por pregunta de revisión (RQ1, RQ2, RQ3) contra
     https://api.openalex.org/works con el filtro title_and_abstract.search y publication_year:2015-2026.
     Guarda el conteo total que reporta la API y descarga como máximo TOPE registros por cadena,
     ordenados por relevancia (regla del proyecto: pedir lo necesario, no bases completas).
  2. Duplicados: elimina registros repetidos entre cadenas (mismo id de OpenAlex o mismo DOI).
     Un registro repetido se cuenta en la primera cadena donde aparece y se anotan todas sus cadenas.
  3. Cribado automático por título y resumen con los criterios de CRITERIOS (escritos abajo).
  4. Candidatos para lectura a texto completo. La elegibilidad a texto completo y la inclusión
     final quedan PENDIENTES: este script no declara ningún estudio como incluido.

Escribe en 03_Fuentes_y_Datos/datos/rsl/:
  rsl_protocolo.json   preguntas, cadenas, filtros, criterios, tope y fecha de ejecución
  rsl_conteos.csv      etapa x cadena (conteos PRISMA)
  rsl_candidatos.csv   un registro único por fila, con pasa_cribado y motivo
No guarda resúmenes (solo metadatos).

Uso:  .venv/bin/python scripts/rsl_openalex.py
Requiere internet. Opcional en .env: SCRAPING_USER_AGENT, SCRAPING_DELAY_SECONDS (por defecto 1 s).
Cada ejecución hace pocas peticiones (una por cada 200 registros). En la consulta del 2026-11-08 la API
sin clave informó un cupo diario de 1000 créditos y un costo de 10 créditos por página de resultados.

Cómo escalar:
  * Subir TOPE o quitarlo (paginar con cursor) cuando se quiera el conjunto completo de una cadena.
  * Repetir las mismas cadenas en Scopus (TITLE-ABS-KEY(...)) y Web of Science (TS=(...)) cuando haya
    acceso institucional; unir por DOI con la misma etapa de duplicados.
  * Agregar búsqueda hacia atrás y hacia adelante (bola de nieve) con los campos referenced_works y
    cited_by_api_url de OpenAlex sobre los candidatos que pasen la lectura a texto completo.
  * Sustituir el cribado automático por doble revisión humana y registrar el acuerdo entre revisores.
"""
from __future__ import annotations

import csv
import json
import re
import sys
import time
import unicodedata
from datetime import datetime, timezone

import httpx

from _entorno import RAIZ, avisar_si_fuera_de_venv, cargar_env

API = "https://api.openalex.org/works"
SALIDA = RAIZ / "03_Fuentes_y_Datos" / "datos" / "rsl"
TOPE = 400          # registros descargados por cadena, como máximo (ordenados por relevancia)
POR_PAGINA = 200    # máximo que permite OpenAlex
ANIOS = (2015, 2026)
# conference-paper: OpenAlex separa hoy las ponencias de "article"; en informática son la vía principal de publicación.
TIPOS = {"article", "review", "dissertation", "preprint", "book-chapter", "conference-paper"}
CAMPOS = "id,doi,display_name,publication_year,type,cited_by_count,primary_location,abstract_inverted_index,relevance_score"

# Un término es una frase (str) o una tupla (término, [alternativas]) que significa término AND (alt1 OR alt2...).
RQ = {
    "RQ1": {
        "pregunta": ("¿Qué métodos computacionales (minería de texto, PLN, extracción de entidades, LLM, RAG) se han usado "
                     "para extraer o clasificar información de casos de feminicidio, homicidio de mujeres o violencia "
                     "contra las mujeres a partir de texto (prensa, expedientes, redes)?"),
        "grupo_a": ["femicide", "feminicide", "feminicidio", "femicidio", "intimate partner homicide", "homicide of women",
                    "female homicide", "homicidio de mujeres", "violence against women", "violencia contra las mujeres",
                    "violencia contra la mujer", "gender-based violence", "violencia de género", "intimate partner violence"],
        "grupo_b": ["text mining", "minería de texto", "natural language processing", "procesamiento de lenguaje natural",
                    "named entity recognition", "reconocimiento de entidades", "information extraction",
                    "extracción de información", "topic modeling", "topic model", "text classification",
                    "clasificación de textos", "large language model", "modelos de lenguaje",
                    "retrieval-augmented generation", "BERT"],
    },
    "RQ2": {
        "pregunta": ("¿Qué modelos espaciales (GWR, GWPR, MGWR, modelos bayesianos espaciales, autocorrelación espacial) se "
                     "han usado para explicar la variación territorial del feminicidio u homicidio de mujeres?"),
        "grupo_a": ["femicide", "feminicide", "feminicidio", "femicidio", "homicide of women", "female homicide",
                    "women homicide", "homicidio de mujeres", "intimate partner homicide", "killing of women",
                    ("homicide", ["women", "female", "gender"]), ("homicidio", ["mujeres"])],
        "grupo_b": ["geographically weighted regression", "regresión geográficamente ponderada", "GWR", "GWPR", "MGWR",
                    "spatial autocorrelation", "autocorrelación espacial", "Moran", "spatial regression",
                    "spatial analysis", "análisis espacial", "spatial econometrics", "Bayesian spatial",
                    "conditional autoregressive", "spatial model", "spatial pattern", "spatial distribution",
                    "hot spot", "hotspot"],
    },
    "RQ3": {
        "pregunta": ("¿Qué aplicaciones de LLM o RAG existen para clasificar, categorizar o extraer información de textos "
                     "de delitos, policiales o judiciales?"),
        "grupo_a": ["large language model", "large language models", "LLM", "retrieval-augmented generation",
                    "retrieval augmented generation", "RAG", "GPT-4", "GPT-3", "generative pre-trained transformer",
                    "modelos de lenguaje", "generación aumentada por recuperación"],
        "grupo_b": ["crime", "criminal", "police", "policing", "police reports", "judicial", "court", "case law",
                    "homicide", "delito", "delitos", "policial", "sentencias judiciales"],
    },
}

AJUSTES = [
    ("RQ2: la primera versión (solo frases como 'homicide of women' o 'female homicide') devolvió 42 registros en "
     "OpenAlex el 2026-11-08; se agregaron (homicide AND (women OR female OR gender)) y (homicidio AND mujeres) "
     "para no perder estudios que nombran el homicidio y a las mujeres por separado: 76 registros ese día."),
    ("RQ3: la cadena devuelve miles de registros (3174 el 2026-11-08), sobre todo por 'court' (1226) y por términos "
     "de delito (1290). No se recortaron términos porque los textos judiciales son parte de la pregunta; se aplica "
     "el tope de descarga por relevancia y el cribado local exige un término de cada grupo."),
    ("Tipos: además de artículo, revisión, tesis, preprint y capítulo se admite 'conference-paper'. OpenAlex "
     "clasifica hoy las ponencias aparte de 'article' (el 2026-11-08 eran 138 registros únicos; al admitirlas, los "
     "candidatos pasaron de 385 a 498) y en "
     "informática son la vía principal de publicación (por ejemplo, el artículo original de RAG es una ponencia)."),
    ("RQ3: no se usó el nombre comercial del asistente conversacional más conocido como término de búsqueda; "
     "los términos 'large language model', 'LLM' y 'GPT-4' lo cubren solo en parte."),
]

CRITERIOS = {
    "periodo": f"año de publicación entre {ANIOS[0]} y {ANIOS[1]}",
    "resumen": "el registro tiene resumen en OpenAlex (abstract_inverted_index no vacío)",
    "tipo": "tipo de OpenAlex en: " + ", ".join(sorted(TIPOS)),
    "conceptos": ("al menos un término del grupo A y uno del grupo B de su cadena aparecen en el título o el resumen "
                  "(comparación sin tildes ni mayúsculas; cada palabra admite sufijos, p. ej. femicide -> femicides; "
                  "las siglas en mayúsculas solo admiten la 's' final)"),
    "texto_completo": "pendiente: elegibilidad e inclusión final requieren lectura humana del texto completo",
}


def normalizar(texto: str) -> str:
    t = "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")
    return t.lower()


def clave_titulo(titulo: str) -> str:
    """Título sin tildes, mayúsculas, espacios ni signos: identifica versiones del mismo trabajo."""
    return re.sub(r"[^a-z0-9]", "", normalizar(titulo))


def frase(t: str) -> str:
    return t if re.fullmatch(r"\w+", t) else f'"{t}"'


def a_consulta(grupo: list) -> str:
    partes = [frase(t) if isinstance(t, str) else f"({frase(t[0])} AND ({' OR '.join(map(frase, t[1]))}))" for t in grupo]
    return "(" + " OR ".join(partes) + ")"


def patron(t: str) -> str:
    palabras = re.split(r"[\s-]+", normalizar(t))
    if t.isupper():  # sigla: GWR, LLM, RAG, GPT-4
        return r"(?<!\w)" + r"[\s-]*".join(map(re.escape, palabras)) + r"s?\b"
    return r"(?<!\w)" + r"[\s-]+".join(re.escape(p) + r"\w*" for p in palabras)


def presente(grupo: list, texto: str) -> bool:
    for t in grupo:
        if isinstance(t, str):
            if re.search(patron(t), texto):
                return True
        elif re.search(patron(t[0]), texto) and any(re.search(patron(a), texto) for a in t[1]):
            return True
    return False


def resumen(indice: dict | None) -> str:
    if not indice:
        return ""
    pos = {p: w for w, ps in indice.items() for p in ps}
    return " ".join(pos[i] for i in sorted(pos))


def cribar(reg: dict, rq: str) -> list[str]:
    """Devuelve la lista de motivos de exclusión (vacía si pasa) para el registro según la cadena rq."""
    motivos = []
    if not (ANIOS[0] <= (reg.get("publication_year") or 0) <= ANIOS[1]):
        motivos.append("fuera del periodo")
    if reg.get("type") not in TIPOS:
        motivos.append(f"tipo no admitido ({reg.get('type')})")
    abst = resumen(reg.get("abstract_inverted_index"))
    if not abst:
        motivos.append("sin resumen")
    texto = normalizar(f"{reg.get('display_name') or ''} {abst}")
    if not presente(RQ[rq]["grupo_a"], texto):
        motivos.append("falta concepto del grupo A")
    if not presente(RQ[rq]["grupo_b"], texto):
        motivos.append("falta concepto del grupo B")
    return motivos


def _autoprueba() -> None:
    assert resumen({"b": [1], "a": [0]}) == "a b"
    t = normalizar("Femicides in Colombia: a Geographically-Weighted Regression with LLMs")
    assert presente(["femicide"], t) and presente(["geographically weighted regression"], t) and presente(["LLM"], t)
    assert not presente(["BERT"], normalizar("Bertrand Russell")) and not presente(["RAG"], normalizar("ragged"))
    assert presente([("homicide", ["women"])], normalizar("Homicides of young women")) is True
    assert a_consulta(["GWR", "hot spot", ("homicidio", ["mujeres"])]) == '(GWR OR "hot spot" OR (homicidio AND (mujeres)))'
    assert cribar({"publication_year": 2014, "type": "letter", "display_name": "x"}, "RQ1") == [
        "fuera del periodo", "tipo no admitido (letter)", "sin resumen", "falta concepto del grupo A", "falta concepto del grupo B"]


def filtro(rq: str) -> str:
    cadena = f"{a_consulta(RQ[rq]['grupo_a'])} AND {a_consulta(RQ[rq]['grupo_b'])}"
    return f"title_and_abstract.search:{cadena},publication_year:{ANIOS[0]}-{ANIOS[1]}"


def buscar(cliente: httpx.Client, rq: str, pausa: float) -> tuple[int, list[dict]]:
    """Devuelve (conteo total en OpenAlex, hasta TOPE registros ordenados por relevancia)."""
    total, registros, pagina = None, [], 1
    while total is None or (len(registros) < min(total, TOPE)):
        r = cliente.get(API, params={"filter": filtro(rq), "sort": "relevance_score:desc", "per_page": POR_PAGINA,
                                     "page": pagina, "select": CAMPOS})
        if r.status_code != 200:
            sys.exit(f"OpenAlex respondió {r.status_code} en {rq}: {r.text[:300]}")
        datos = r.json()
        total = datos["meta"]["count"]
        if not datos["results"]:
            break
        registros += datos["results"]
        pagina += 1
        time.sleep(pausa)
    return total, registros[:TOPE]


def main() -> list[dict]:
    avisar_si_fuera_de_venv()
    _autoprueba()
    env = cargar_env()
    pausa = float(env.get("SCRAPING_DELAY_SECONDS") or 1)
    ua = env.get("SCRAPING_USER_AGENT") or "investigacion-academica-rsl/1.0"
    ejecucion = datetime.now(timezone.utc).isoformat(timespec="seconds")
    SALIDA.mkdir(parents=True, exist_ok=True)

    conteos = {e: {} for e in ("identificados", "descargados", "no_descargados_por_tope", "duplicados_eliminados",
                                "unicos_cribados", "excl_fuera_del_periodo", "excl_tipo_no_admitido", "excl_sin_resumen",
                                "excl_falta_grupo_a", "excl_falta_grupo_b", "excluidos_cribado",
                                "candidatos_texto_completo")}
    unicos: dict[str, dict] = {}   # clave: id de OpenAlex
    por_doi: dict[str, str] = {}
    por_titulo: dict[str, str] = {}  # versiones del mismo trabajo (preprint y publicado, v1 y v2) con otro id y otro DOI
    with httpx.Client(headers={"User-Agent": ua}, timeout=60) as cliente:
        for rq in RQ:
            total, regs = buscar(cliente, rq, pausa)
            conteos["identificados"][rq] = total
            conteos["descargados"][rq] = len(regs)
            conteos["no_descargados_por_tope"][rq] = total - len(regs)
            dup = 0
            for reg in regs:
                doi = (reg.get("doi") or "").lower()
                tit = clave_titulo(reg.get("display_name") or "")
                clave = reg["id"] if reg["id"] in unicos else por_doi.get(doi) or por_titulo.get(tit) or reg["id"]
                if clave in unicos:
                    if rq not in unicos[clave]["cadenas"]:  # repetido entre cadenas
                        dup += 1
                        unicos[clave]["cadenas"].append(rq)
                        unicos[clave]["motivos"][rq] = cribar(reg, rq)
                    else:                                    # mismo DOI o mismo título con otro id dentro de la cadena
                        dup += 1
                    continue
                unicos[clave] = {"reg": reg, "cadenas": [rq], "motivos": {rq: cribar(reg, rq)}}
                if doi:
                    por_doi[doi] = clave
                if tit:
                    por_titulo[tit] = clave
            conteos["duplicados_eliminados"][rq] = dup

    filas = []
    for u in unicos.values():
        reg, rq0 = u["reg"], u["cadenas"][0]
        pasa = [rq for rq in u["cadenas"] if not u["motivos"][rq]]
        motivo = ("cumple criterios en " + ";".join(pasa)) if pasa else " | ".join(
            f"{rq}: {'; '.join(u['motivos'][rq])}" for rq in u["cadenas"])
        u["pasa"] = bool(pasa)
        u["resumen"] = resumen(reg.get("abstract_inverted_index"))
        c = conteos
        c["unicos_cribados"][rq0] = c["unicos_cribados"].get(rq0, 0) + 1
        if pasa:
            c["candidatos_texto_completo"][rq0] = c["candidatos_texto_completo"].get(rq0, 0) + 1
        else:
            c["excluidos_cribado"][rq0] = c["excluidos_cribado"].get(rq0, 0) + 1
            m = u["motivos"][rq0]  # motivos de la primera cadena (puede tener varios)
            for clave, txt in (("excl_fuera_del_periodo", "fuera del periodo"), ("excl_tipo_no_admitido", "tipo no admitido"),
                               ("excl_sin_resumen", "sin resumen"), ("excl_falta_grupo_a", "grupo A"),
                               ("excl_falta_grupo_b", "grupo B")):
                if any(txt in x for x in m):
                    c[clave][rq0] = c[clave].get(rq0, 0) + 1
        fuente = ((reg.get("primary_location") or {}).get("source") or {}).get("display_name") or ""
        filas.append({"openalex_id": reg["id"].rsplit("/", 1)[-1], "doi": (reg.get("doi") or "").replace("https://doi.org/", ""),
                      "anio": reg.get("publication_year"), "titulo": " ".join((reg.get("display_name") or "").split()),
                      "fuente": fuente, "tipo": reg.get("type"), "citas": reg.get("cited_by_count"),
                      "cadenas": ";".join(u["cadenas"]), "pasa_cribado": "si" if pasa else "no", "motivo": motivo})

    with open(SALIDA / "rsl_candidatos.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0]))
        w.writeheader()
        w.writerows(filas)
    with open(SALIDA / "rsl_conteos.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["etapa", *RQ, "total"])
        for etapa, val in conteos.items():
            w.writerow([etapa, *(val.get(rq, 0) for rq in RQ), sum(val.values())])
        w.writerow(["incluidos_tras_texto_completo", *("pendiente" for _ in RQ), "pendiente"])

    protocolo = {
        "fecha_ejecucion_utc": ejecucion,
        "base": "OpenAlex", "endpoint": API,
        "filtros_comunes": {"campo": "title_and_abstract.search", "publication_year": f"{ANIOS[0]}-{ANIOS[1]}",
                            "orden": "relevance_score:desc", "tope_descarga_por_cadena": TOPE},
        "preguntas": {rq: {"pregunta": d["pregunta"], "grupo_a": d["grupo_a"], "grupo_b": d["grupo_b"],
                           "filtro_openalex": filtro(rq), "conteo_api": conteos["identificados"][rq]}
                      for rq, d in RQ.items()},
        "duplicados": ("por id de OpenAlex, por DOI y por título normalizado (sin tildes, mayúsculas ni signos; une preprint y "
                       "versión publicada); cada repetido se cuenta en la primera cadena (orden RQ1, RQ2, RQ3)"),
        "criterios_cribado": CRITERIOS,
        "ajustes_de_cadenas": AJUSTES,
        "inclusion_final": "pendiente (lectura a texto completo)",
    }
    (SALIDA / "rsl_protocolo.json").write_text(json.dumps(protocolo, ensure_ascii=False, indent=2), encoding="utf-8")

    for etapa, val in conteos.items():
        print(f"{etapa:28s}", *(f"{rq}={val.get(rq, 0):<5}" for rq in RQ), f"total={sum(val.values())}")
    print("Archivos en", SALIDA.relative_to(RAIZ))
    return list(unicos.values())


if __name__ == "__main__":
    main()
