// Simple numbering for non-book documents
#let equation-numbering = "(1)"
#let callout-numbering = "1"
#let subfloat-numbering(n-super, subfloat-idx) = {
  numbering("1a", n-super, subfloat-idx)
}

// Theorem configuration for theorion
// Simple numbering for non-book documents (no heading inheritance)
#let theorem-inherited-levels = 0

// Theorem numbering format (can be overridden by extensions for appendix support)
// This function returns the numbering pattern to use
#let theorem-numbering(loc) = "1.1"

// Default theorem render function
#let theorem-render(prefix: none, title: "", full-title: auto, body) = {
  if full-title != "" and full-title != auto and full-title != none {
    strong[#full-title.]
    h(0.5em)
  }
  body
}
// Some definitions presupposed by pandoc's typst output.
#let content-to-string(content) = {
  if content.has("text") {
    content.text
  } else if content.has("children") {
    content.children.map(content-to-string).join("")
  } else if content.has("body") {
    content-to-string(content.body)
  } else if content == [ ] {
    " "
  }
}

#let horizontalrule = line(start: (25%,0%), end: (75%,0%))

#let endnote(num, contents) = [
  #stack(dir: ltr, spacing: 3pt, super[#num], contents)
]

#show terms.item: it => block(breakable: false)[
  #text(weight: "bold")[#it.term]
  #block(inset: (left: 1.5em, top: -0.4em))[#it.description]
]

// Some quarto-specific definitions.

#show raw.where(block: true): set block(
    fill: luma(230),
    width: 100%,
    inset: 8pt,
    radius: 2pt
  )

#let block_with_new_content(old_block, new_content) = {
  let fields = old_block.fields()
  let _ = fields.remove("body")
  if fields.at("below", default: none) != none {
    // TODO: this is a hack because below is a "synthesized element"
    // according to the experts in the typst discord...
    fields.below = fields.below.abs
  }
  block.with(..fields)(new_content)
}

#let empty(v) = {
  if type(v) == str {
    // two dollar signs here because we're technically inside
    // a Pandoc template :grimace:
    v.matches(regex("^\\s*$")).at(0, default: none) != none
  } else if type(v) == content {
    if v.at("text", default: none) != none {
      return empty(v.text)
    }
    for child in v.at("children", default: ()) {
      if not empty(child) {
        return false
      }
    }
    return true
  }

}

// Subfloats
// This is a technique that we adapted from https://github.com/tingerrr/subpar/
#let quartosubfloatcounter = counter("quartosubfloatcounter")

#let quarto_super(
  kind: str,
  caption: none,
  label: none,
  supplement: str,
  position: none,
  subcapnumbering: "(a)",
  body,
) = {
  context {
    let figcounter = counter(figure.where(kind: kind))
    let n-super = figcounter.get().first() + 1
    set figure.caption(position: position)
    [#figure(
      kind: kind,
      supplement: supplement,
      caption: caption,
      {
        show figure.where(kind: kind): set figure(numbering: _ => {
          let subfloat-idx = quartosubfloatcounter.get().first() + 1
          subfloat-numbering(n-super, subfloat-idx)
        })
        show figure.where(kind: kind): set figure.caption(position: position)

        show figure: it => {
          let num = numbering(subcapnumbering, n-super, quartosubfloatcounter.get().first() + 1)
          show figure.caption: it => block({
            num.slice(2) // I don't understand why the numbering contains output that it really shouldn't, but this fixes it shrug?
            [ ]
            it.body
          })

          quartosubfloatcounter.step()
          it
          counter(figure.where(kind: it.kind)).update(n => n - 1)
        }

        quartosubfloatcounter.update(0)
        body
      }
    )#label]
  }
}

// callout rendering
// this is a figure show rule because callouts are crossreferenceable
#show figure: it => {
  if type(it.kind) != str {
    return it
  }
  let kind_match = it.kind.matches(regex("^quarto-callout-(.*)")).at(0, default: none)
  if kind_match == none {
    return it
  }
  let kind = kind_match.captures.at(0, default: "other")
  kind = upper(kind.first()) + kind.slice(1)
  // now we pull apart the callout and reassemble it with the crossref name and counter

  // when we cleanup pandoc's emitted code to avoid spaces this will have to change
  let old_callout = it.body.children.at(1).body.children.at(1)
  let old_title_block = old_callout.body.children.at(0)
  let children = old_title_block.body.body.children
  let old_title = if children.len() == 1 {
    children.at(0)  // no icon: title at index 0
  } else {
    children.at(1)  // with icon: title at index 1
  }

  // TODO use custom separator if available
  // Use the figure's counter display which handles chapter-based numbering
  // (when numbering is a function that includes the heading counter)
  let callout_num = it.counter.display(it.numbering)
  let new_title = if empty(old_title) {
    [#kind #callout_num]
  } else {
    [#kind #callout_num: #old_title]
  }

  let new_title_block = block_with_new_content(
    old_title_block,
    block_with_new_content(
      old_title_block.body,
      if children.len() == 1 {
        new_title  // no icon: just the title
      } else {
        children.at(0) + new_title  // with icon: preserve icon block + new title
      }))

  align(left, block_with_new_content(old_callout,
    block(below: 0pt, new_title_block) +
    old_callout.body.children.at(1)))
}

// 2023-10-09: #fa-icon("fa-info") is not working, so we'll eval "#fa-info()" instead
#let callout(body: [], title: "Callout", background_color: rgb("#dddddd"), icon: none, icon_color: black, body_background_color: white) = {
  block(
    breakable: false, 
    fill: background_color, 
    stroke: (paint: icon_color, thickness: 0.5pt, cap: "round"), 
    width: 100%, 
    radius: 2pt,
    block(
      inset: 1pt,
      width: 100%, 
      below: 0pt, 
      block(
        fill: background_color,
        width: 100%,
        inset: 8pt)[#if icon != none [#text(icon_color, weight: 900)[#icon] ]#title]) +
      if(body != []){
        block(
          inset: 1pt, 
          width: 100%, 
          block(fill: body_background_color, width: 100%, inset: 8pt, body))
      }
    )
}



// Póster académico UNAL, Segunda Entrega.
// Lienzo 120 x 90 cm horizontal. Jerarquía tipográfica de la plantilla:
// título 66 pt, secciones 50 pt, texto 32 pt, referencias y pies 24 pt.
// Tipografía institucional: Ancízar Sans (texto) y Ancízar Serif (referencias).

#let verde-osc = rgb("#456A3E")
#let verde = rgb("#94B43B")
#let gris = rgb("#55595B")
#let fondo = rgb("#F3F4F1")

#let ancho-col = 37.6cm
#let alto-fila = 27.0cm

// Tarjeta de sección numerada.
#let seccion(num, titulo, subtitulo: none, cuerpo) = block(
  width: 100%, height: alto-fila, fill: white, inset: (x: 1.3cm, top: 1.0cm, bottom: 0.8cm),
  stroke: (top: 8pt + verde),
)[
  #text(size: 50pt, weight: "bold", fill: verde-osc)[#num. #titulo]
  #if subtitulo != none { h(0.4em); text(size: 32pt, fill: gris)[(#subtitulo)] }
  #v(0.5cm)
  #cuerpo
]

// Figura con pie de texto a 24 pt.
#let figura(ruta, pie, ancho: 100%) = block(width: 100%, breakable: false)[
  #align(center, image(ruta, width: ancho))
  #v(0.15cm)
  #text(size: 24pt, fill: gris)[#pie]
]

// Cifra destacada.
#let cifra(valor, etiqueta) = box(width: 100%, inset: (y: 0.3cm))[
  #text(size: 60pt, weight: "bold", fill: verde-osc)[#valor] \
  #text(size: 24pt, fill: gris)[#etiqueta]
]

// Recuadro de énfasis.
#let destacado(cuerpo) = block(width: 100%, fill: verde.lighten(80%), inset: 0.8cm, stroke: (left: 10pt + verde))[#cuerpo]

#let poster-unal(
  titulo: none, subtitulo: none, estudiante: none, programa: none, facultad: none, grupo: none, correo: none,
  logo-izq: none, body,
) = {
  set page(width: 120cm, height: 90cm, margin: 2cm, fill: fondo, numbering: none, header: none, footer: none)
  set text(font: ("Ancizar Sans", "Helvetica Neue"), size: 32pt, fill: rgb("#222222"), lang: "es")
  set par(justify: false, leading: 0.55em, spacing: 0.75em)
  set list(indent: 0.4em, body-indent: 0.5em, spacing: 0.6em, marker: text(fill: verde)[■])
  set enum(indent: 0.4em, body-indent: 0.5em, spacing: 0.6em)
  show strong: set text(fill: verde-osc)

  // Encabezado: logo | título | datos del estudiante.
  grid(
    columns: (12cm, 1fr, 27cm), column-gutter: 1.5cm, align: (center + horizon, center + horizon, left + horizon),
    if logo-izq != none { image(logo-izq, height: 11.5cm) },
    [
      #text(size: 66pt, weight: "bold", fill: verde-osc, hyphenate: false)[#titulo]
      #if subtitulo != none { v(0.3cm); text(size: 36pt, style: "italic", fill: gris)[#subtitulo] }
    ],
    [
      #text(size: 40pt, weight: "bold", fill: verde-osc)[#estudiante] \
      #v(0.2cm)
      #text(size: 30pt)[#programa] \
      #text(size: 28pt, fill: gris)[#facultad] \
      #text(size: 28pt, fill: gris)[#grupo]
      #if correo != none { linebreak(); text(size: 28pt, fill: verde-osc, correo.replace("\\", "")) }
    ],
  )
  v(0.4cm)
  line(length: 100%, stroke: 6pt + verde)
  v(0.5cm)
  body
}
#let brand-color = (:)
#let brand-color-background = (:)
#let brand-logo = (:)

#set page(
  paper: "us-letter",
  margin: (x: 1.25in, y: 1.25in),
  numbering: "1",
  columns: 1,
)

#show: doc => poster-unal(
   titulo: [Modelos de lenguaje con generación aumentada por recuperación y análisis espacial para la catalogación de presuntos feminicidios y la construcción de indicadores territoriales en Antioquia], 
   subtitulo: [\(Formato Segunda Entrega Póster)], 
   estudiante: [Daniel Felipe Villa Rengifo], 
   programa: [Maestría en Ingeniería -- Analítica], 
   facultad: [Facultad de Minas · Universidad Nacional de Colombia, Sede Medellín], 
   grupo: [Departamento de Ciencias de la Computación y la Decisión], 
   correo: "dvilla\@unal.edu.co", 
   logo-izq: "logos/escudo-unal-2016.svg", 
  doc,
)


#let paso(n, t, d) = block(width: 100%, height: 5.0cm, fill: verde.lighten(82%), inset: (x: 0.45cm, y: 0.4cm), radius: 0.3cm)[
  #set align(top + left)
  #text(size: 25pt, weight: "bold", fill: verde-osc)[#n. #t]
  #v(0.1cm)
  #set text(size: 22pt)
  #set par(leading: 0.3em)
  #d
]
#let flecha = text(size: 30pt, fill: verde)[→]
#let literal(l, t) = (text(weight: "bold", fill: verde-osc)[#l], t)

#grid(
  columns: (1fr, 1fr, 1fr), column-gutter: 1.2cm, row-gutter: 1.0cm,

  seccion(1, [Motivación], subtitulo: [Contexto / Propósito · Cómo])[
    #figura("figuras/f1_tasas.svg")[*Figura 1.* Presuntos homicidios de mujeres por cada 100.000 mujeres. Fuentes: Medicina Legal (2025\* preliminar) y DANE.]
    - Medicina Legal registró *110* presuntos homicidios de mujeres en Antioquia en 2024; la tasa bajó de 5,4 a 3,1 entre 2018 y 2024.
    #destacado[*Propósito:* catalogar cada nuevo registro según el art. 104A, con evidencia de casos validados, y resumir los resultados en indicadores territoriales.]
    #v(0.05cm)
    #block(below: 0.25cm, text(size: 34pt, weight: "bold", fill: verde-osc)[Cómo])
    #grid(columns: (1fr, auto, 1fr, auto, 1fr, auto, 1fr), column-gutter: 0.15cm, align: horizon,
      paso(1, [Base validada], [Registros oficiales y su noticia de prensa, con confiabilidad A1–F6]), flecha,
      paso(2, [Recuperación], [Busca los casos validados más parecidos (RAG)]), flecha,
      paso(3, [Catalogación], [Un LLM propone literales del art. 104A con su evidencia; revisión humana]), flecha,
      paso(4, [Indicadores], [Cifras agregadas por subregión o municipio]),
    )
  ],

  seccion(2, [Marco teórico], subtitulo: [De referencia])[
    *Feminicidio (art. 104A, Ley 1761 de 2015):* causar la muerte a una mujer por su condición de ser mujer o por motivos de su identidad de género, o cuando concurra o anteceda alguna de estas circunstancias:
    #v(0.1cm)
    #set text(size: 26pt)
    #table(columns: (2.2cm, 1fr), stroke: none, inset: (x: 0.3cm, y: 0.2cm), fill: (_, y) => if calc.odd(y) { verde.lighten(85%) },
      ..literal([a)], [Relación actual o pasada (familiar, íntima, de convivencia, amistad, compañerismo o trabajo) y ciclo de violencia previo del autor]),
      ..literal([b)], [Instrumentalización de género o sexual; opresión y dominio sobre sus decisiones]),
      ..literal([c)], [Aprovechamiento de relaciones de poder]),
      ..literal([d)], [Generar terror o humillación a quien se considere enemigo]),
      ..literal([e)], [Antecedentes o indicios de violencia o amenaza del autor contra la víctima, denunciados o no]),
      ..literal([f)], [Incomunicación o privación de la libertad]),
    )
    #set text(size: 32pt)
    - *Presunto:* sin decisión judicial, todo registro se trata como presunto.
    - *RAG (generación aumentada por recuperación):* un modelo de lenguaje grande (LLM) responde con documentos recuperados de una base propia y cita la evidencia (Lewis et al., 2020).
    - *Heterogeneidad espacial:* los factores asociados pueden pesar distinto en cada territorio de Antioquia (Sepúlveda Murillo et al., 2018).
  ],

  seccion(3, [Qué], subtitulo: [Objeto de estudio])[
    - *Objeto:* los registros de presunto feminicidio y de presunto homicidio de mujeres en Antioquia, 2015–2025.
    - *Sistema:* 125 municipios en 9 subregiones (división de la Gobernación).
    - *Variables:* conteos y tasas; literales del art. 104A asignados a cada registro; vínculo con el presunto agresor; zona.
    - *Unidad de análisis:* subregión–año.
    #figura("figuras/f3_viabilidad.svg")[*Figura 2.* Celdas municipio–año y subregión–año según los presuntos homicidios de mujeres registrados (todas las causas), 2015–2025. Fuentes: Policía Nacional; Gobernación de Antioquia.]
    #destacado[Por municipio–año, el 89 % de las celdas tiene menos de 3 registros y el ruido por azar de una tasa anual ronda el 91 %; por subregión–año baja al 25 %.]
  ],

  seccion(4, [Revisión sistemática de la literatura])[
    
- *Protocolo:* PRISMA 2020 (Page et al., 2021) en OpenAlex; título y resumen, 2015–2026; consulta del 2026-11-08. Preguntas de revisión (RQ):
#set text(size: 26pt)
#table(columns: (2.6cm, 1fr), stroke: none, inset: (x: 0.25cm, y: 0.12cm),
  [*RQ1*], [Lenguaje natural, LLM o RAG en textos sobre feminicidio o violencia contra las mujeres],
  [*RQ2*], [Modelos espaciales del feminicidio u homicidio de mujeres],
  [*RQ3*], [LLM o RAG para clasificar textos policiales o judiciales],
)
#set text(size: 32pt)
#grid(columns: (1fr, auto, 1fr, auto, 1fr, auto, 1fr), column-gutter: 0.15cm, align: horizon,
  block(width: 100%, height: 4.3cm, fill: verde.lighten(82%), inset: (x: 0.3cm, y: 0.35cm), radius: 0.3cm)[#set align(center + horizon)
#text(size: 40pt, weight: "bold", fill: verde-osc)[3428] #linebreak() #text(size: 22pt)[identificados]], flecha,
  block(width: 100%, height: 4.3cm, fill: verde.lighten(82%), inset: (x: 0.3cm, y: 0.35cm), radius: 0.3cm)[#set align(center + horizon)
#text(size: 40pt, weight: "bold", fill: verde-osc)[619] #linebreak() #text(size: 22pt)[revisados, sin duplicados (tope: 400 por RQ)]], flecha,
  block(width: 100%, height: 4.3cm, fill: verde.lighten(82%), inset: (x: 0.3cm, y: 0.35cm), radius: 0.3cm)[#set align(center + horizon)
#text(size: 40pt, weight: "bold", fill: verde-osc)[478] #linebreak() #text(size: 22pt)[para texto completo (141 excluidos)]], flecha,
  block(width: 100%, height: 4.3cm, fill: luma(235), inset: (x: 0.3cm, y: 0.35cm), radius: 0.3cm)[#set align(center + horizon)
#text(size: 40pt, weight: "bold", fill: verde-osc)[—] #linebreak() #text(size: 22pt)[incluidos: en lectura]],
)
#v(0.15cm)
*Hallazgos preliminares* (títulos de los candidatos):
#set text(size: 28pt)
- RQ1: 9 de 130 mencionan LLM o GPT y 2 RAG; 3 tratan Colombia y ninguno Antioquia.
- RQ2: 19 de 60 estudian Brasil y 2 Colombia.
- RQ3: 146 de 288 son de textos legales o judiciales; 17 policiales y 4 de género.
#set text(size: 30pt)
#destacado[*Antecedentes:* heterogeneidad espacial del feminicidio en Antioquia (Sepúlveda Murillo et al., 2018); LLM con RAG en casos de Brasil (Martínez de Lucena y Dorneles, 2026). *Brecha:* el cribado no muestra un catalogador según el art. 104A ni indicadores por subregión.]

  ],

  seccion(5, [Problema])[
    - Las fuentes oficiales miden cosas distintas:
    #figura("figuras/f5_registros_oficiales.svg")[*Figura 3.* Antioquia, registros oficiales por año. Fuentes: Medicina Legal y Fiscalía.]
    - En el 62 % de los 618 registros de la Fiscalía (Antioquia, todos los años) la modalidad es «sin información» o «por establecer»; los datos abiertos consultados no indican el literal del art. 104A.
    - Entre el 56 % y el 79 % de los presuntos homicidios de mujeres de cada año (Medicina Legal, 2015–2024) no registran al presunto agresor.
    #destacado[*Pregunta:* ¿cómo catalogar de forma trazable los registros de presunto feminicidio en Antioquia según el art. 104A, y a qué nivel territorial esa catalogación produce indicadores estables?]
  ],

  seccion(6, [Objetivos])[
    #set text(size: 30pt)
    #destacado[*Hipótesis:* es posible catalogar los registros de presunto feminicidio en Antioquia según el art. 104A con un modelo de lenguaje que recupera casos validados, con mayor acuerdo con expertos que el mismo modelo sin recuperación, y obtener indicadores por subregión con menos ruido por azar que por municipio.]
    *General:* desarrollar un catalogador de los registros de presunto feminicidio en Antioquia según el art. 104A, con un modelo de lenguaje que recupera casos validados (RAG), que logre mayor acuerdo con expertos que el mismo modelo sin recuperación y produzca indicadores por subregión con menos ruido por azar que por municipio.
    #v(0.1cm)
    *Específicos:*
    #set text(size: 27pt)
    #set enum(spacing: 0.4em)
    + Identificar los métodos de LLM, RAG y análisis espacial usados para estudiar el feminicidio.
    + Caracterizar las fuentes de Antioquia según su confiabilidad (A1–F6) y su cobertura territorial.
    + Determinar el nivel territorial en que los indicadores tienen menos ruido por azar.
    + Construir la base de casos validados en dos versiones: interna y pública anonimizada.
    + Desarrollar el catalogador RAG que asigna los literales del art. 104A con su evidencia.
    + Evaluar el catalogador frente a expertos y frente al mismo modelo sin recuperación.
  ],
)

#v(1.0cm)

#grid(
  columns: (2fr, 1fr), column-gutter: 1.2cm,
  block(width: 100%, height: 14.4cm, fill: white, inset: (x: 1.3cm, y: 0.8cm), stroke: (top: 8pt + verde))[
    #text(size: 44pt, weight: "bold", fill: verde-osc)[7\. Referencias]
    #v(0.1cm)
    #set text(font: "Ancizar Serif", size: 20pt)
    #set par(hanging-indent: 1.2em, leading: 0.4em, spacing: 0.5em)
    #columns(2, gutter: 1.2cm)[
    Congreso de la República de Colombia. (2015). _Ley 1761 de 2015, por la cual se crea el tipo penal de feminicidio como delito autónomo y se dictan otras disposiciones (Rosa Elvira Cely)_. Diario Oficial 49.565. http://www.secretariasenado.gov.co/senado/basedoc/ley_1761_2015.html

Departamento Administrativo Nacional de Estadística. (s. f.). _Proyecciones de población departamental por área, sexo y edad, 2018–2050_ [Conjunto de datos]. https://www.dane.gov.co/files/censo2018/proyecciones-de-poblacion/Departamental/PPED-AreaSexoEdadDep-2018-2050_VP.xlsx

Fiscalía General de la Nación. (2026). _Víctimas Fiscalía – V3_ [Conjunto de datos]. Datos Abiertos Colombia. https://www.datos.gov.co/d/hr73-zqjf

Gobernación de Antioquia. (s. f.). _Cantidad anual de suicidios reportados en el Departamento de Antioquia desde 2005_ [Conjunto de datos; se usa su tabla de municipios y subregiones]. Datos Abiertos Colombia. https://www.datos.gov.co/d/db67-sbus

Instituto Nacional de Medicina Legal y Ciencias Forenses. (2025). _Presuntos homicidios. Colombia, 2015 a 2024. Cifras definitivas_ [Conjunto de datos]. Datos Abiertos Colombia. https://www.datos.gov.co/d/vtub-3de2

Lewis, P., Perez, E., Piktus, A., Petroni, F., Karpukhin, V., Goyal, N., Küttler, H., Lewis, M., Yih, W.-t., Rocktäschel, T., Riedel, S. y Kiela, D. (2020). Retrieval-augmented generation for knowledge-intensive NLP tasks. _Advances in Neural Information Processing Systems, 33_, 9459–9474.

Martínez de Lucena, B. y Dorneles, C. F. (2026). Extração de informação jurídica com LLMs e RAG: um estudo sobre casos de feminicídio. En _Simpósio Brasileiro de Bancos de Dados (SBBD)_ (pp. 321–327). https://doi.org/10.5753/sbbd_estendido.2026.249677

Page, M. J., McKenzie, J. E., Bossuyt, P. M., Boutron, I., Hoffmann, T. C., Mulrow, C. D., Shamseer, L., Tetzlaff, J. M., Akl, E. A., Brennan, S. E., Chou, R., Glanville, J., Grimshaw, J. M., Hróbjartsson, A., Lalu, M. M., Li, T., Loder, E. W., Mayo-Wilson, E., McDonald, S., … Moher, D. (2021). The PRISMA 2020 statement: An updated guideline for reporting systematic reviews. _BMJ, 372_, n71. https://doi.org/10.1136/bmj.n71

Policía Nacional de Colombia. (s. f.). _Homicidio_ [Conjunto de datos]. Datos Abiertos Colombia. https://www.datos.gov.co/d/m8fd-ahd9

Sepúlveda Murillo, F. H., Chica-Olmo, J. y Rodríguez García de Cortázar, A. (2018). The spatial heterogeneity of factors of feminicide: The case of Antioquia-Colombia. _Applied Geography, 92_, 63–73. https://doi.org/10.1016/j.apgeog.2018.01.006
    ]
  ],
  block(width: 100%, height: 14.4cm, fill: white, inset: (x: 1.3cm, y: 0.8cm), stroke: (top: 8pt + verde))[
    #grid(columns: (8.4cm, 1fr), column-gutter: 0.9cm, align: horizon,
      image("figuras/qr_repositorio.svg", width: 8.4cm),
      [
        #text(size: 36pt, weight: "bold", fill: verde-osc)[Más información]
        #v(0.2cm)
        #text(size: 24pt)[Pósters, datos agregados, búsqueda de literatura y código de cada cifra.]
        #v(0.2cm)
        #text(size: 22pt, fill: gris)[github.com/dvillaunal/MSc-project-Fase1]
      ],
    )
    #v(0.5cm)
    #text(size: 30pt, weight: "bold", fill: verde-osc)[Directores / Asesores]
    #v(0.1cm)
    #text(size: 30pt, weight: "bold")[Fernán Alonso Villa Garzón, Ph.D.] #h(0.4em) #text(size: 26pt, fill: gris)[Tutor]
  ],
)



