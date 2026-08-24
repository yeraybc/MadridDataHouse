#!/usr/bin/env Rscript
# Verificación ligera para CI. No instala paquetes: parse() valida la sintaxis
# sin evaluar los library(), así que no hacen falta GDAL/GEOS/PROJ.
# Uso:  Rscript .github/scripts/check.R

fallos <- character(0)
seccion <- function(x) cat("\n", x, "\n", strrep("-", nchar(x)), "\n", sep = "")

scripts <- c(
  list.files(c("R", "apps"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE),
  "setup.R", "deploy.R"
)

seccion("1. Sintaxis de los scripts")
for (f in scripts) {
  r <- tryCatch({ parse(f); "OK" }, error = function(e) conditionMessage(e))
  cat(sprintf("  %-42s %s\n", f, r))
  if (r != "OK") fallos <- c(fallos, paste("no parsea:", f))
}

seccion("2. Formato de requirements.txt")
lineas <- trimws(readLines("requirements.txt", warn = FALSE))
lineas <- lineas[nzchar(lineas) & !startsWith(lineas, "#")]
patron <- "^[A-Za-z][A-Za-z0-9.]*(>=[0-9]+([.-][0-9]+)*)?$"
invalidas <- lineas[!grepl(patron, lineas)]
if (length(invalidas)) {
  cat("  líneas inválidas:", paste(invalidas, collapse = ", "), "\n")
  fallos <- c(fallos, "requirements.txt mal formado")
} else {
  cat("  ", length(lineas), " dependencias declaradas\n", sep = "")
}
declaradas <- sub(">=.*", "", lineas)

# Este check existe porque ya falló una vez: car se usa en 03B via car::Anova,
# no viene con tidyverse, y faltaba en la lista de dependencias.
seccion("3. Toda librería usada está declarada")
extraer_librerias <- function(f) {
  ln <- readLines(f, warn = FALSE)
  ln <- ln[grepl("library(", ln, fixed = TRUE)]
  if (!length(ln)) return(character(0))
  tras <- vapply(strsplit(ln, "library(", fixed = TRUE), function(p) p[2], character(1))
  vapply(strsplit(tras, ")", fixed = TRUE), function(p) p[1], character(1))
}

usadas <- sort(unique(unlist(lapply(scripts, extraer_librerias))))
faltan <- setdiff(usadas, declaradas)
if (length(faltan)) {
  cat("  usadas pero NO declaradas:", paste(faltan, collapse = ", "), "\n")
  fallos <- c(fallos, "faltan dependencias en requirements.txt")
} else {
  cat("  ", length(usadas), " librerías usadas, todas declaradas\n", sep = "")
}

cat("\n")
if (length(fallos)) {
  cat("FALLO:\n")
  for (f in fallos) cat("  -", f, "\n")
  quit(status = 1)
}
cat("Todo correcto.\n")
