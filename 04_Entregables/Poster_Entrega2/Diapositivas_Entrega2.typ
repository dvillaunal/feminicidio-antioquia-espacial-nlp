// Diapositivas para la presentación remota de la segunda entrega (5 minutos de exposición).
// Cada diapositiva es una sección del póster (Poster_Entrega2.pdf) recortada a 150 ppp: no hay contenido nuevo.
// Recortes en diapositivas/ (s1 a s8), hechos con pdftocairo desde el PDF del póster; ver el README del repositorio.
// Compilar:  typst compile Diapositivas_Entrega2.typ

#let verde-osc = rgb("#456A3E")
#let verde = rgb("#94B43B")
#let gris = rgb("#55595B")
#let fondo = rgb("#F3F4F1")

#set page(width: 33.867cm, height: 19.05cm, margin: 0cm, fill: fondo)
// Helvetica Neue en la portada: Ancízar solo está instalada como fuente variable y Typst no maneja sus pesos.
#set text(font: ("Helvetica Neue", "Arial"), size: 18pt, fill: rgb("#222222"), lang: "es")

#let pie(n) = place(bottom + left, dx: 0.8cm, dy: -0.45cm,
  text(size: 10pt, fill: gris)[Daniel Felipe Villa Rengifo · Segunda entrega del póster · #n/8])

#let seccion(archivo, n, alto: 18.2cm) = {
  align(center + horizon, image("diapositivas/" + archivo, height: alto))
  pie(n)
}

// 1. Portada
#grid(columns: (8cm, 1fr, 9.5cm), column-gutter: 0.8cm,
  align(center + horizon, box(height: 19.05cm, inset: (left: 1cm), align(horizon, image("logos/escudo-unal-2016.svg", height: 6.5cm)))),
  align(left + horizon)[
    #text(size: 27pt, weight: "bold", fill: verde-osc, hyphenate: false)[Modelos de lenguaje con generación aumentada por recuperación y análisis espacial para la catalogación de presuntos feminicidios y la construcción de indicadores territoriales en Antioquia]
    #v(0.5cm)
    #line(length: 100%, stroke: 3pt + verde)
    #v(0.3cm)
    #text(size: 20pt, weight: "bold")[Daniel Felipe Villa Rengifo] \
    #text(size: 15pt)[Maestría en Ingeniería – Analítica · Facultad de Minas, UNAL Medellín] \
    #text(size: 15pt, fill: verde-osc)[dvilla\@unal.edu.co]
    #v(0.2cm)
    #text(size: 15pt, fill: gris)[Tutor: Fernán Alonso Villa Garzón, Ph.D. \ Seminario de Investigación I · Segunda entrega del póster]
  ],
  align(center + horizon, box(inset: (right: 1cm))[
    #image("figuras/qr_repositorio.svg", width: 6.5cm)
    #v(0.2cm)
    #text(size: 12pt, fill: gris)[github.com/dvillaunal/MSc-project-Fase1]
  ]),
)
#pie(1)

// 2–7. Secciones del póster, en el orden de la plantilla
#pagebreak()
#seccion("s1.png", 2)
#pagebreak()
#seccion("s2.png", 3)
#pagebreak()
#seccion("s3.png", 4)
#pagebreak()
#seccion("s4.png", 5)
#pagebreak()
#seccion("s5.png", 6)
#pagebreak()
#seccion("s6.png", 7)

// 8. Referencias y más información
#pagebreak()
#align(center + horizon, stack(dir: ttb, spacing: 0.5cm,
  image("diapositivas/s7.png", width: 32cm),
  image("diapositivas/s8.png", height: 8.6cm),
))
#pie(8)
