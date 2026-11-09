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
