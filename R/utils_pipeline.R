# Utilidades compartidas por los scripts del pipeline.

RAW_DIR  <- "data/raw"
DATA_DIR <- "data/processed"

# Gitignorado y por tanto ausente en un clon nuevo: crearlo antes de escribir
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

# Aborta si falta algún artefacto generado por un script anterior
require_artifacts <- function(...) {
  archivos <- c(...)
  faltan <- archivos[!file.exists(file.path(DATA_DIR, archivos))]

  if (length(faltan)) {
    stop("Faltan artefactos en '", DATA_DIR, "/': ", paste(faltan, collapse = ", "),
         "\n  Estos ficheros los genera un script anterior del pipeline y no se",
         "\n  distribuyen con el repositorio.",
         "\n  Ejecuta el pipeline completo con:  Rscript R/run_all.R",
         call. = FALSE)
  }
  invisible(TRUE)
}

# Aborta si falta un fichero de entrada del repo (working dir o clon incorrecto)
require_inputs <- function(...) {
  rutas <- c(...)
  faltan <- rutas[!file.exists(rutas)]

  if (length(faltan)) {
    stop("No se encuentran ficheros de entrada: ", paste(faltan, collapse = ", "),
         "\n  Las rutas son relativas a la raíz del proyecto. Comprueba que ejecutas",
         "\n  desde ahí (abre MadridDataHouse.Rproj, o usa Rscript desde la raíz).",
         "\n  Directorio de trabajo actual: ", getwd(),
         call. = FALSE)
  }
  invisible(TRUE)
}

CARTO_DIR <- file.path(RAW_DIR, "cartography")

# Avisa (no aborta) si un zip difiere del SHA-256 de checksums.txt
verify_checksum <- function(zip_name) {
  ruta_checksums <- file.path(CARTO_DIR, "checksums.txt")
  ruta_zip <- file.path(CARTO_DIR, zip_name)

  if (!file.exists(ruta_checksums) || !file.exists(ruta_zip)) return(invisible(NA))

  lineas <- readLines(ruta_checksums, warn = FALSE)
  lineas <- trimws(lineas)
  lineas <- lineas[nzchar(lineas) & !startsWith(lineas, "#")]

  esperado <- NA_character_
  for (l in lineas) {
    campos <- strsplit(l, "\\s+")[[1]]
    if (length(campos) >= 2 && campos[length(campos)] == zip_name) esperado <- campos[1]
  }
  if (is.na(esperado)) return(invisible(NA))

  real <- tryCatch(digest_sha256(ruta_zip), error = function(e) NA_character_)
  if (is.na(real)) return(invisible(NA))

  if (!identical(real, esperado)) {
    warning("La cartografía '", zip_name, "' NO coincide con la verificada.",
            "\n  esperado: ", esperado,
            "\n  obtenido: ", real,
            "\n  El Geoportal puede haber actualizado los límites administrativos.",
            "\n  El análisis seguirá, pero los resultados pueden diferir de los",
            "\n  publicados en el README.",
            call. = FALSE, immediate. = TRUE)
    return(invisible(FALSE))
  }
  invisible(TRUE)
}

# tools::sha256sum no existe en todas las versiones de R: respaldo por shell
digest_sha256 <- function(ruta) {
  if (exists("sha256sum", where = asNamespace("tools"), inherits = FALSE)) {
    return(unname(get("sha256sum", envir = asNamespace("tools"))(ruta)))
  }
  cmd <- if (nzchar(Sys.which("shasum"))) {
    paste("shasum -a 256", shQuote(ruta))
  } else if (nzchar(Sys.which("sha256sum"))) {
    paste("sha256sum", shQuote(ruta))
  } else {
    return(NA_character_)
  }
  salida <- suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE))
  if (!length(salida)) return(NA_character_)
  strsplit(trimws(salida[1]), "\\s+")[[1]][1]
}

# Resuelve un shapefile en este orden: .shp existente > .zip del repo > Geoportal
ensure_cartography <- function(shp_name, zip_name, url) {
  ruta_shp <- file.path(CARTO_DIR, shp_name)
  ruta_zip <- file.path(CARTO_DIR, zip_name)

  if (file.exists(ruta_shp)) return(invisible("presente"))

  dir.create(CARTO_DIR, showWarnings = FALSE, recursive = TRUE)

  # El zip está versionado: preferirlo siempre a la red
  if (file.exists(ruta_zip)) {
    message("Cartografía: descomprimiendo ", zip_name, " del repositorio (sin descarga).")
    verify_checksum(zip_name)
    unzip(ruta_zip, exdir = CARTO_DIR)
    if (file.exists(ruta_shp)) return(invisible("zip_local"))
    warning("El zip local no contenía ", shp_name, "; se intentará descargar.",
            call. = FALSE, immediate. = TRUE)
  }

  message("Cartografía: descargando ", zip_name, " del Geoportal de Madrid...")
  descarga_ok <- tryCatch({
    utils::download.file(url, destfile = ruta_zip, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)

  if (descarga_ok && file.exists(ruta_zip)) {
    verify_checksum(zip_name)
    unzip(ruta_zip, exdir = CARTO_DIR)
  }

  if (file.exists(ruta_shp)) return(invisible("descargado"))

  stop("No se ha podido obtener la cartografía '", shp_name, "'.",
       "\n  El repositorio incluye '", zip_name, "' en ", CARTO_DIR, "/;",
       "\n  si lo has borrado, restaúralo con:",
       "\n      git checkout -- ", file.path(CARTO_DIR, zip_name),
       "\n  O descárgalo a mano desde el Geoportal de Madrid:",
       "\n      ", url,
       "\n  y descomprímelo en ", CARTO_DIR, "/",
       call. = FALSE)
}
