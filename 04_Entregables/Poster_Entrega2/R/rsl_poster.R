# Sección de revisión sistemática y referencias (Entregas 2 y 3).
# Los conteos salen de scripts/rsl_openalex.py (03_Fuentes_y_Datos/datos/rsl/); aquí no se escribe ninguna cifra a mano.
# Los hallazgos se cuentan sobre los TÍTULOS de los candidatos (el CSV no guarda resúmenes), así cualquiera los reproduce.
# Cada candidato se cuenta en su primera cadena, igual que en rsl_conteos.csv.

RSL <- file.path(RAIZ, "03_Fuentes_y_Datos", "datos", "rsl")
rsl_n <- read_csv(file.path(RSL, "rsl_conteos.csv"), show_col_types = FALSE, col_types = cols(.default = "c"))
etapa <- function(e) as.integer(rsl_n$total[rsl_n$etapa == e])
c_rsl_ident  <- etapa("identificados")
c_rsl_unicos <- etapa("unicos_cribados")
c_rsl_excl   <- etapa("excluidos_cribado")
c_rsl_cand   <- etapa("candidatos_texto_completo")
c_rsl_fecha  <- format(as.POSIXct(fromJSON(file.path(RSL, "rsl_protocolo.json"))$fecha_ejecucion_utc,
                                  format = "%Y-%m-%dT%H:%M", tz = "UTC"), "%Y-%m-%d", tz = "America/Bogota")

cand <- read_csv(file.path(RSL, "rsl_candidatos.csv"), show_col_types = FALSE) |>
  filter(pasa_cribado == "si") |> mutate(rq = str_extract(cadenas, "^RQ\\d"))
en_rq <- function(r) filter(cand, rq == r)
titulos <- function(r, patron) sum(str_detect(en_rq(r)$titulo, regex(patron, ignore_case = TRUE)))
c_rq1 <- nrow(en_rq("RQ1")); c_rq2 <- nrow(en_rq("RQ2")); c_rq3 <- nrow(en_rq("RQ3"))
c_rq1_llm <- titulos("RQ1", "language model|\\bLLMs?\\b|GPT")
c_rq1_rag <- titulos("RQ1", "retrieval|\\bRAG\\b")
c_rq1_col <- titulos("RQ1", "colombia")
c_rq1_ant <- titulos("RQ1", "antioquia|medell")
c_rq2_bra <- titulos("RQ2", "brazil|brasil|paran|amaz|bahia|minas gerais|pernambuco")
c_rq2_col <- titulos("RQ2", "colombia")
c_rq3_leg <- titulos("RQ3", "legal|court|judicial|\\blaw\\b|juris")
c_rq3_pol <- titulos("RQ3", "police|policial|crime report|incident report")
c_rq3_gen <- titulos("RQ3", "gender|domestic|femin|women")

caja <- function(n, t, fondo = "verde.lighten(82%)") paste0(
  'block(width: 100%, height: 4.3cm, fill: ', fondo, ', inset: (x: 0.3cm, y: 0.35cm), radius: 0.3cm)[',
  '#set align(center + horizon)\n#text(size: 40pt, weight: "bold", fill: verde-osc)[', n, '] #linebreak() ',
  '#text(size: 22pt)[', t, ']]')

rsl_texto <- paste0('
- *Protocolo:* PRISMA 2020 (Page et al., 2021) en OpenAlex; título y resumen, 2015–2026; consulta del ', c_rsl_fecha, '. Preguntas de revisión (RQ):
#set text(size: 26pt)
#table(columns: (2.6cm, 1fr), stroke: none, inset: (x: 0.25cm, y: 0.12cm),
  [*RQ1*], [Lenguaje natural, LLM o RAG en textos sobre feminicidio o violencia contra las mujeres],
  [*RQ2*], [Modelos espaciales del feminicidio u homicidio de mujeres],
  [*RQ3*], [LLM o RAG para clasificar textos policiales o judiciales],
)
#set text(size: 32pt)
#grid(columns: (1fr, auto, 1fr, auto, 1fr, auto, 1fr), column-gutter: 0.15cm, align: horizon,
  ', caja(num(c_rsl_ident), "identificados"), ', flecha,
  ', caja(num(c_rsl_unicos), "revisados, sin duplicados (tope: 400 por RQ)"), ', flecha,
  ', caja(num(c_rsl_cand), paste0("para texto completo (", num(c_rsl_excl), " excluidos)")), ', flecha,
  ', caja("—", "incluidos: en lectura", "luma(235)"), ',
)
#v(0.15cm)
*Hallazgos preliminares* (títulos de los candidatos):
#set text(size: 28pt)
- RQ1: ', c_rq1_llm, ' de ', c_rq1, ' mencionan LLM o GPT y ', c_rq1_rag, ' RAG; ', c_rq1_col, ' tratan Colombia y ', ifelse(c_rq1_ant == 0, "ninguno", c_rq1_ant), ' Antioquia.
- RQ2: ', c_rq2_bra, ' de ', c_rq2, ' estudian Brasil y ', c_rq2_col, ' Colombia.
- RQ3: ', c_rq3_leg, ' de ', c_rq3, ' son de textos legales o judiciales; ', c_rq3_pol, ' policiales y ', c_rq3_gen, ' de género.
#set text(size: 30pt)
#destacado[*Antecedentes:* heterogeneidad espacial del feminicidio en Antioquia (Sepúlveda Murillo et al., 2018); LLM con RAG en casos de Brasil (Martínez de Lucena y Dorneles, 2026). *Brecha:* el cribado no muestra un catalogador según el art. 104A ni indicadores por subregión.]
')

ref_texto <- paste(
  "Congreso de la República de Colombia. (2015). _Ley 1761 de 2015, por la cual se crea el tipo penal de feminicidio como delito autónomo y se dictan otras disposiciones (Rosa Elvira Cely)_. Diario Oficial 49.565. http://www.secretariasenado.gov.co/senado/basedoc/ley_1761_2015.html",
  "Departamento Administrativo Nacional de Estadística. (s. f.). _Proyecciones de población departamental por área, sexo y edad, 2018–2050_ [Conjunto de datos]. https://www.dane.gov.co/files/censo2018/proyecciones-de-poblacion/Departamental/PPED-AreaSexoEdadDep-2018-2050_VP.xlsx",
  "Fiscalía General de la Nación. (2026). _Víctimas Fiscalía – V3_ [Conjunto de datos]. Datos Abiertos Colombia. https://www.datos.gov.co/d/hr73-zqjf",
  "Gobernación de Antioquia. (s. f.). _Cantidad anual de suicidios reportados en el Departamento de Antioquia desde 2005_ [Conjunto de datos; se usa su tabla de municipios y subregiones]. Datos Abiertos Colombia. https://www.datos.gov.co/d/db67-sbus",
  "Instituto Nacional de Medicina Legal y Ciencias Forenses. (2025). _Presuntos homicidios. Colombia, 2015 a 2024. Cifras definitivas_ [Conjunto de datos]. Datos Abiertos Colombia. https://www.datos.gov.co/d/vtub-3de2",
  "Lewis, P., Perez, E., Piktus, A., Petroni, F., Karpukhin, V., Goyal, N., Küttler, H., Lewis, M., Yih, W.-t., Rocktäschel, T., Riedel, S. y Kiela, D. (2020). Retrieval-augmented generation for knowledge-intensive NLP tasks. _Advances in Neural Information Processing Systems, 33_, 9459–9474.",
  "Martínez de Lucena, B. y Dorneles, C. F. (2026). Extração de informação jurídica com LLMs e RAG: um estudo sobre casos de feminicídio. En _Simpósio Brasileiro de Bancos de Dados (SBBD)_ (pp. 321–327). https://doi.org/10.5753/sbbd_estendido.2026.249677",
  "Page, M. J., McKenzie, J. E., Bossuyt, P. M., Boutron, I., Hoffmann, T. C., Mulrow, C. D., Shamseer, L., Tetzlaff, J. M., Akl, E. A., Brennan, S. E., Chou, R., Glanville, J., Grimshaw, J. M., Hróbjartsson, A., Lalu, M. M., Li, T., Loder, E. W., Mayo-Wilson, E., McDonald, S., … Moher, D. (2021). The PRISMA 2020 statement: An updated guideline for reporting systematic reviews. _BMJ, 372_, n71. https://doi.org/10.1136/bmj.n71",
  "Policía Nacional de Colombia. (s. f.). _Homicidio_ [Conjunto de datos]. Datos Abiertos Colombia. https://www.datos.gov.co/d/m8fd-ahd9",
  "Sepúlveda Murillo, F. H., Chica-Olmo, J. y Rodríguez García de Cortázar, A. (2018). The spatial heterogeneity of factors of feminicide: The case of Antioquia-Colombia. _Applied Geography, 92_, 63–73. https://doi.org/10.1016/j.apgeog.2018.01.006",
  sep = "\n\n")
