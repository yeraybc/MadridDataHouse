#!/usr/bin/env Rscript
# run_all.R — Ejecuta el pipeline completo de MadridDataHouse
#
# Uso (desde la raíz del proyecto):  Rscript R/run_all.R
#
# Los scripts se ejecutan en orden y se comunican a través de artefactos .rds/.tif
# en data/. Aborta en el primer error, indicando qué paso falló.

if (!dir.exists("R") || !dir.exists("data")) {
  stop("Ejecuta este script desde la raíz del proyecto:  Rscript R/run_all.R",
       "\n  Directorio de trabajo actual: ", getwd(), call. = FALSE)
}

PASOS <- c(
  "R/01_preparacion_datos.R",
  "R/02_analisis_exploratorio.R",
  "R/03A_kriging.R",
  "R/03B_ml_espacial.R",
  "R/04_validacion.R",
  "R/05_actualizacion_precios.R"
)

faltan <- PASOS[!file.exists(PASOS)]
if (length(faltan)) {
  stop("No se encuentran estos scripts: ", paste(faltan, collapse = ", "), call. = FALSE)
}

cat("\nPipeline MadridDataHouse —", length(PASOS), "pasos\n")
cat(strrep("=", 60), "\n", sep = "")

inicio_total <- Sys.time()

for (i in seq_along(PASOS)) {
  paso <- PASOS[i]
  cat(sprintf("\n[%d/%d] %s\n", i, length(PASOS), paso))

  inicio <- Sys.time()
  resultado <- tryCatch({
    # Cada paso en su propio entorno: evita que un objeto quede colgando de un
    # script al siguiente y enmascare una dependencia no declarada.
    sys.source(paso, envir = new.env(parent = globalenv()))
    NULL
  }, error = function(e) e)

  if (!is.null(resultado)) {
    cat("\n", strrep("=", 60), "\n", sep = "")
    cat("FALLO en ", paso, "\n\n", sep = "")
    cat(conditionMessage(resultado), "\n\n")
    cat("El pipeline se ha detenido. Los pasos anteriores sí se completaron,\n")
    cat("así que puedes reanudar desde este script una vez resuelto el problema.\n\n")
    quit(status = 1)
  }

  cat(sprintf("      ok (%.1f s)\n", as.numeric(difftime(Sys.time(), inicio, units = "secs"))))
}

cat("\n", strrep("=", 60), "\n", sep = "")
cat(sprintf("Pipeline completado en %.1f min\n",
            as.numeric(difftime(Sys.time(), inicio_total, units = "mins"))))

if (file.exists("data/processed/metricas_finales.rds")) {
  cat("\nMétricas finales:\n\n")
  print(as.data.frame(readRDS("data/processed/metricas_finales.rds")))
}

cat("\nSiguiente paso — levanta la aplicación:\n\n")
cat("    shiny::runApp(\"apps/app_ml\")\n\n")
