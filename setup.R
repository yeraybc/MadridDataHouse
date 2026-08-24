#!/usr/bin/env Rscript
# Prepara el entorno: verifica R, GDAL/GEOS/PROJ e instala requirements.txt
# Uso:  Rscript setup.R

R_MINIMA  <- "4.5.0"
REQUIREMENTS <- "requirements.txt"

titulo <- function(x) cat("\n", x, "\n", strrep("-", nchar(x)), "\n", sep = "")
ok     <- function(...) cat("  [ok]   ", ..., "\n", sep = "")
aviso  <- function(...) cat("  [aviso]", ..., "\n", sep = "")
fallo  <- function(...) cat("  [FALLO]", ..., "\n", sep = "")

version_instalada <- function(pkg) {
  tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NA_character_)
}

titulo("1. Versión de R")
if (getRversion() < R_MINIMA) {
  fallo("R ", as.character(getRversion()), " es anterior a la mínima requerida (", R_MINIMA, ").")
  cat("\n  Actualiza R desde https://cran.r-project.org/ y vuelve a ejecutar este script.\n")
  quit(status = 1)
}
ok("R ", as.character(getRversion()), " (mínima: ", R_MINIMA, ")")

# Comprobar antes de instalar: sin GDAL/GEOS/PROJ, sf y terra fallan al compilar
titulo("2. Librerías del sistema (GDAL / GEOS / PROJ)")

instrucciones_sistema <- function() {
  so <- Sys.info()[["sysname"]]
  if (identical(so, "Darwin")) {
    "  macOS:  brew install gdal geos proj udunits"
  } else if (identical(so, "Linux")) {
    "  Debian/Ubuntu:  sudo apt-get install libgdal-dev libgeos-dev libproj-dev libudunits2-dev"
  } else {
    "  Windows: los binarios de CRAN ya incluyen GDAL/GEOS/PROJ; no hace falta nada extra."
  }
}

if (is.na(version_instalada("sf"))) {
  aviso("sf aún no está instalado; no se puede comprobar GDAL/GEOS/PROJ todavía.")
  cat("        Si la instalación de sf falla más abajo, instala primero:\n")
  cat(instrucciones_sistema(), "\n")
} else {
  geo <- tryCatch(sf::sf_extSoftVersion(), error = function(e) NULL)
  if (is.null(geo)) {
    fallo("sf está instalado pero no carga: probablemente faltan GDAL/GEOS/PROJ.")
    cat(instrucciones_sistema(), "\n")
  } else {
    ok("GDAL ", geo[["GDAL"]], " | GEOS ", geo[["GEOS"]], " | PROJ ", geo[["PROJ"]])
  }
}

titulo("3. Dependencias de R")

if (!file.exists(REQUIREMENTS)) {
  fallo("No se encuentra '", REQUIREMENTS, "'.")
  cat("\n  Ejecuta este script desde la raíz del proyecto:  Rscript setup.R\n")
  quit(status = 1)
}

lineas <- readLines(REQUIREMENTS, warn = FALSE)
lineas <- trimws(lineas)
lineas <- lineas[nzchar(lineas) & !startsWith(lineas, "#")]

partes <- strsplit(lineas, ">=", fixed = TRUE)
requisitos <- data.frame(
  paquete  = trimws(vapply(partes, `[`, character(1), 1)),
  minima   = trimws(vapply(partes, function(p) if (length(p) > 1) p[2] else NA_character_, character(1))),
  stringsAsFactors = FALSE
)

cat("  ", nrow(requisitos), " paquetes declarados en ", REQUIREMENTS, "\n", sep = "")

faltantes <- requisitos$paquete[is.na(vapply(requisitos$paquete, version_instalada, character(1)))]

if (length(faltantes)) {
  cat("\n  Instalando ", length(faltantes), " paquete(s) que faltan: ",
      paste(faltantes, collapse = ", "), "\n\n", sep = "")
  install.packages(faltantes, repos = "https://cloud.r-project.org")
} else {
  ok("Todos los paquetes están ya instalados; no hay nada que descargar.")
}

titulo("4. Informe")

requisitos$instalada <- vapply(requisitos$paquete, version_instalada, character(1))
requisitos$estado <- mapply(function(min_v, inst_v) {
  if (is.na(inst_v))                                   return("NO INSTALADO")
  if (is.na(min_v))                                    return("ok")
  if (package_version(inst_v) < package_version(min_v)) return("DESACTUALIZADO")
  "ok"
}, requisitos$minima, requisitos$instalada)

ancho <- max(nchar(requisitos$paquete))
cat(sprintf("  %-*s  %-10s  %-10s  %s\n", ancho, "PAQUETE", "REQUERIDA", "INSTALADA", "ESTADO"))
for (i in seq_len(nrow(requisitos))) {
  cat(sprintf("  %-*s  %-10s  %-10s  %s\n", ancho,
              requisitos$paquete[i],
              ifelse(is.na(requisitos$minima[i]), "-", paste0(">=", requisitos$minima[i])),
              ifelse(is.na(requisitos$instalada[i]), "-", requisitos$instalada[i]),
              requisitos$estado[i]))
}

problemas <- requisitos[requisitos$estado != "ok", ]

cat("\n")
if (nrow(problemas) == 0) {
  ok("Entorno listo.")
  cat("\n  Siguiente paso — ejecuta el pipeline completo:\n\n      Rscript R/run_all.R\n\n")
  quit(status = 0)
}

fallo(nrow(problemas), " paquete(s) sin resolver:")
for (i in seq_len(nrow(problemas))) {
  cat("        ", problemas$paquete[i], " (", problemas$estado[i], ")\n", sep = "")
}
cat("\n  Los desactualizados suelen resolverse con:\n")
cat("      install.packages(c(", paste0('"', problemas$paquete, '"', collapse = ", "), "))\n\n")
cat("  Si el fallo es de compilación en sf/terra/raster, instala antes:\n")
cat(instrucciones_sistema(), "\n\n")
quit(status = 1)
