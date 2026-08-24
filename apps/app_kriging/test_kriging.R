library(sf)
library(gstat)
library(terra)
library(raster)
library(tidyverse)

cargar_artefacto <- function(archivo) {
  rutas <- c(paste0("../datos/", archivo), paste0("datos/", archivo))
  ruta_real <- rutas[file.exists(rutas)][1]
  if (is.na(ruta_real)) stop(paste("ERROR: No se encuentra", archivo))
  if (grepl("\\.rds$", archivo)) return(readRDS(ruta_real))
  if (grepl("\\.tif$", archivo)) return(terra::rast(ruta_real))
}

train_sf         <- cargar_artefacto("train_sf_fase2.rds")
variograma_ajust <- cargar_artefacto("variograma_ajustado.rds")
formula_krig     <- cargar_artefacto("formula_kriging.rds")
raster_pred      <- cargar_artefacto("kriging_raster_pred.tif")
raster_var       <- cargar_artefacto("kriging_raster_var.tif")
hull_concavo     <- cargar_artefacto("hull_concavo.rds")
metricas         <- cargar_artefacto("metricas_kriging.rds")

raster_pred_wgs84 <- raster::raster(terra::project(raster_pred, "EPSG:4326"))
raster_var_wgs84  <- raster::raster(terra::project(raster_var,  "EPSG:4326"))
hull_wgs84        <- st_transform(hull_concavo, crs = 4326)

pal_pred <- leaflet::colorNumeric("plasma", values(raster_pred_wgs84), na.color = "transparent")
pal_var  <- leaflet::colorNumeric("YlOrRd", values(raster_var_wgs84), na.color = "transparent")
print("SUCCESS!")
