# Datos y cifras del póster (Fase 1). Todo se calcula desde los archivos procesados
# por los scripts de 03_Fuentes_y_Datos; aquí no se escribe ninguna cifra a mano.

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(jsonlite); library(stringr)
})

RAIZ <- normalizePath(file.path("..", ".."))
PROC <- file.path(RAIZ, "03_Fuentes_y_Datos", "datos", "procesados")
CRUD <- file.path(RAIZ, "03_Fuentes_y_Datos", "datos", "crudos")
leer <- function(nombre) read_csv(file.path(PROC, nombre), show_col_types = FALSE)

# Norma RAE: sin separador de miles en números de cuatro cifras; punto desde las cinco.
num <- function(x, d = 0) ifelse(abs(x) < 10000, formatC(x, format = "f", digits = d, decimal.mark = ","),
                                 formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","))
pct <- function(x, d = 0) paste0(num(100 * x, d), " %")

pob <- leer("dane_mujeres_depto_anio.csv")
pob_col <- pob |> group_by(anio) |> summarise(mujeres = sum(mujeres), .groups = "drop")

por_anio <- function(df) df |> group_by(departamento, anio) |> summarise(n = sum(n), .groups = "drop")
ml  <- por_anio(leer("ml_homicidio_mujeres_depto_anio.csv"))
pol <- por_anio(leer("policia_homicidio_mujeres_depto_anio.csv"))
fis <- por_anio(leer("fiscalia_feminicidio_depto_anio.csv"))

antioquia <- function(df) df |> filter(departamento == "ANTIOQUIA") |> select(anio, n)
nacional  <- function(df) df |> group_by(anio) |> summarise(n = sum(n), .groups = "drop")

# Tasas por 100.000 mujeres (Medicina Legal + DANE)
tasas <- bind_rows(
  antioquia(ml) |> left_join(filter(pob, departamento == "ANTIOQUIA") |> select(anio, mujeres), by = "anio") |> mutate(serie = "Antioquia"),
  nacional(ml) |> left_join(pob_col, by = "anio") |> mutate(serie = "Colombia")
) |> filter(anio >= 2018, anio <= 2025) |> mutate(tasa = n / mujeres * 1e5, preliminar = anio >= 2025)

t_ant <- function(a) tasas$tasa[tasas$serie == "Antioquia" & tasas$anio == a]
t_col <- function(a) tasas$tasa[tasas$serie == "Colombia" & tasas$anio == a]

# Cifras para el texto
c_ml23  <- antioquia(ml)$n[antioquia(ml)$anio == 2023]
c_ml24  <- antioquia(ml)$n[antioquia(ml)$anio == 2024]
c_pol23 <- antioquia(pol)$n[antioquia(pol)$anio == 2023]
c_t18 <- t_ant(2018); c_t24 <- t_ant(2024); c_tc24 <- t_col(2024)

zona <- leer("antioquia_zona_anio.csv") |> filter(anio >= 2019, anio <= 2025)
c_rural <- sum(zona$n[zona$zona == "RURAL"]) / sum(zona$n)

muni <- leer("antioquia_municipio_2018_hoy.csv") |> mutate(p = n / sum(n))
c_medellin <- muni$p[muni$municipio == "MEDELLIN"]

agr <- leer("antioquia_agresor_anio.csv") |> filter(anio <= 2024) |>
  group_by(anio) |>
  summarise(desc = sum(n[str_detect(agresor, regex("sin informaci|desconocido", ignore_case = TRUE))]) / sum(n), .groups = "drop")
c_desc_min <- min(agr$desc); c_desc_max <- max(agr$desc)

tip <- antioquia(fis) |> rename(fis = n) |> inner_join(antioquia(ml) |> rename(ml = n), by = "anio")
c_tip23 <- with(tip, fis[anio == 2023] / ml[anio == 2023])
c_tip24 <- with(tip, fis[anio == 2024] / ml[anio == 2024])

corr <- antioquia(pol) |> rename(pol = n) |> inner_join(antioquia(ml) |> rename(ml = n), by = "anio") |>
  mutate(dif = abs(pol - ml) / pmax(pol, ml))
c_corr_ok <- sum(corr$dif <= 0.10); c_corr_n <- nrow(corr)

obs <- leer("observatorio_cifras.csv") |> filter(medida == "Antioquia, anual") |>
  transmute(anio = as.integer(periodo), obs = valor)

# Datos reunidos en la Fase 1
inv <- leer("observatorio_inventario.csv")
c_boletines <- n_distinct(inv$pagina[!is.na(inv$archivo) & inv$archivo != ""])
c_ocr <- sum(!is.na(inv$chars) & inv$chars < 500)
# Noticias y redes: se cuentan desde los archivos completos (solo en el repositorio de trabajo) y el conteo
# queda en conteos_redes_noticias.csv, que es lo único que viaja al repositorio público.
ult_noticias <- sort(list.files(file.path(CRUD, "noticias"), "google_news_.*\\.json$", full.names = TRUE), decreasing = TRUE)[1]
ruta_conteos <- file.path(PROC, "conteos_redes_noticias.csv")
if (!is.na(ult_noticias) && file.exists(file.path(PROC, "x_publicaciones.csv"))) {
  conteos <- tibble(
    medida = c("noticias_antioquia", "publicaciones_x", "comentarios_facebook"),
    valor = c(sum(fromJSON(ult_noticias)$items$antioquia), nrow(leer("x_publicaciones.csv")),
              nrow(leer("facebook_comentarios.csv"))))
  write_csv(conteos, ruta_conteos)
} else {
  conteos <- read_csv(ruta_conteos, show_col_types = FALSE)
}
c_noticias <- conteos$valor[conteos$medida == "noticias_antioquia"]
c_x  <- conteos$valor[conteos$medida == "publicaciones_x"]
c_fb <- conteos$valor[conteos$medida == "comentarios_facebook"]

# Registro de fuentes (tipo y letra de fiabilidad)
reg <- fromJSON(file.path(RAIZ, "03_Fuentes_y_Datos", "datos", "validacion_fuentes.json"))$fuentes
fuentes <- reg |> filter(!startsWith(uso, "Datos descargados")) |> mutate(letra = substr(clasif, 1, 1))
c_fuentes <- nrow(fuentes)
c_conjuntos <- sum(reg$uso == "Datos descargados (Fase 1)")

# ---------------------------------------------------------------- Entregas 2 y 3
# Viabilidad del nivel territorial (scripts/viabilidad_nivel_territorial.py)
viab <- leer("viabilidad_nivel_territorial.csv")
v_nivel <- function(nivel, campo) getElement(viab, campo)[viab$nivel == nivel]
c_mun_cero  <- v_nivel("Municipio–año", "pct_celdas_cero") / 100
c_mun_men3  <- v_nivel("Municipio–año", "pct_celdas_menos_3") / 100
c_mun_cv    <- 1 / sqrt(v_nivel("Municipio–año", "media_por_celda"))
c_sub_cero  <- v_nivel("Subregión–año", "pct_celdas_cero") / 100
c_sub_men3  <- v_nivel("Subregión–año", "pct_celdas_menos_3") / 100
c_sub_cv    <- 1 / sqrt(v_nivel("Subregión–año", "media_por_celda"))  # se redondea una sola vez, al imprimir
c_sub_media <- v_nivel("Subregión–año", "media_por_celda")
c_mun_media <- v_nivel("Municipio–año", "media_por_celda")
c_mun_acum_cv <- v_nivel("Municipio, años acumulados", "cv_azar_pct") / 100
# El póster usa solo la capa pública: conteos de 1 y 2 por municipio vienen como «<3».
celda <- function(v) {
  n <- suppressWarnings(as.integer(v))
  factor(case_when(v == "<3" ~ "1–2", n == 0 ~ "0 casos", n <= 9 ~ "3–9", TRUE ~ "10 o más"),
         levels = c("0 casos", "1–2", "3–9", "10 o más"))
}
leer_pub <- function(nombre) read_csv(file.path(PROC, nombre), show_col_types = FALSE, col_types = cols(.default = "c"))
muni_anio <- leer_pub("indicadores_publicos_municipio_anio.csv") |> mutate(k = celda(homicidios_mujeres))
sub_anio  <- leer_pub("indicadores_publicos_subregion_anio.csv") |> mutate(k = celda(homicidios_mujeres))
c_municipios  <- n_distinct(muni_anio$cod_muni)
c_subregiones <- n_distinct(muni_anio$subregion)
c_anio_ini <- min(as.integer(muni_anio$anio)); c_anio_fin <- max(as.integer(muni_anio$anio))

# Modalidad en los registros de feminicidio de la Fiscalía (scripts/extraer_modalidad_fiscalia.py)
moda <- leer("fiscalia_antioquia_modalidad.csv") |> filter(campo == "modalidad_homicidio_femi")
c_fis_total <- sum(moda$n)
c_fis_sin_modalidad <- sum(moda$n[moda$valor %in% c("Sin Información", "Por Establecer")]) / c_fis_total
