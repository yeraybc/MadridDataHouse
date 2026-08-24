#!/usr/bin/env Rscript
# Publica las apps Shiny en shinyapps.io.
# Uso:  Rscript deploy.R [app_ml|app_kriging] [--dry-run]
#
# appName va fijo al nombre ya publicado para ACTUALIZAR la app en su misma URL.
# Depende de apps/<app>/rsconnect/, gitignorado y local: no lo borres o el
# siguiente despliegue creará apps nuevas en otras URLs.

source("R/utils_pipeline.R")

APPS <- list(
  app_ml = list(
    appName    = "MadridDataHouse",
    url        = "https://yeraybc.shinyapps.io/MadridDataHouse/",
    artefactos = c("train_sf_fase2.rds", "rf_model.rds", "xgb_model.rds",
                   "metricas_finales.rds", "distritos_sf.rds", "barrios_sf.rds",
                   "indice_precios_actuales.rds"),
    extra      = "www"   # el CSS de app.R hace url('bg.png')
  ),
  app_kriging = list(
    appName    = "05_app_kriging",
    url        = "https://yeraybc.shinyapps.io/05_app_kriging/",
    artefactos = c("train_sf_fase2.rds", "variograma_ajustado.rds", "formula_kriging.rds",
                   "kriging_raster_pred.tif", "kriging_raster_var.tif",
                   "hull_concavo.rds", "metricas_kriging.rds"),
    extra      = NULL
  )
)

args    <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args
objetivo <- setdiff(args, "--dry-run")

if (length(objetivo) == 0) {
  objetivo <- names(APPS)
} else if (!all(objetivo %in% names(APPS))) {
  stop("App desconocida: ", paste(setdiff(objetivo, names(APPS)), collapse = ", "),
       "\n  Disponibles: ", paste(names(APPS), collapse = ", "), call. = FALSE)
}

if (!dir.exists("apps") || !dir.exists("data")) {
  stop("Ejecuta este script desde la raíz del proyecto:  Rscript deploy.R",
       "\n  Directorio de trabajo actual: ", getwd(), call. = FALSE)
}

if (!dry_run && !requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Falta el paquete 'rsconnect'. Instálalo con:  Rscript setup.R", call. = FALSE)
}

for (nombre in objetivo) {
  app     <- APPS[[nombre]]
  app_dir <- file.path("apps", nombre)

  cat("\n", strrep("=", 60), "\n", sep = "")
  cat(nombre, " -> ", app$appName, "\n", sep = "")
  cat(strrep("=", 60), "\n", sep = "")

  require_artifacts(app$artefactos)

  # El bundle debe ser autocontenido: copiar los artefactos al dir de la app
  destino <- file.path(app_dir, "data")
  dir.create(destino, showWarnings = FALSE, recursive = TRUE)

  if (!dry_run) {
    copiado <- file.copy(file.path(DATA_DIR, app$artefactos), destino, overwrite = TRUE)
    if (!all(copiado)) {
      stop("No se pudieron copiar: ",
           paste(app$artefactos[!copiado], collapse = ", "), call. = FALSE)
    }
  }
  cat("  ", length(app$artefactos), " artefactos -> ", destino, "\n", sep = "")

  # Solo lo que la app lee: deja fuera el CSV y los shapefiles que nada usa
  app_files <- c("app.R", file.path("data", app$artefactos))
  if (!is.null(app$extra) && dir.exists(file.path(app_dir, app$extra))) {
    # appFiles espera rutas relativas al directorio de la app
    extras <- list.files(file.path(app_dir, app$extra), recursive = TRUE)
    app_files <- c(app_files, file.path(app$extra, extras))
  }

  presentes <- file.exists(file.path(app_dir, app_files))
  if (!all(presentes) && !dry_run) {
    stop("Faltan ficheros del bundle en ", app_dir, ": ",
         paste(app_files[!presentes], collapse = ", "), call. = FALSE)
  }

  tam <- sum(file.size(file.path(app_dir, app_files[presentes])), na.rm = TRUE)
  cat("  bundle: ", length(app_files), " ficheros, ",
      round(tam / 1024^2, 1), " MB\n", sep = "")
  for (f in app_files) cat("      ", f, if (!file.exists(file.path(app_dir, f))) "  (FALTA)" else "", "\n", sep = "")

  if (dry_run) {
    cat("\n  --dry-run: no se publica nada.\n")
    next
  }

  cat("\n  Desplegando en ", app$url, " ...\n\n", sep = "")
  rsconnect::deployApp(
    appDir      = app_dir,
    appName     = app$appName,
    appFiles    = app_files,
    forceUpdate = TRUE,
    launch.browser = FALSE
  )
  cat("\n  Listo: ", app$url, "\n", sep = "")
}

cat("\n")
if (dry_run) cat("Dry run terminado. Quita --dry-run para publicar.\n\n")
