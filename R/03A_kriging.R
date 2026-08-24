# 03A_kriging.R

library(tidyverse)
library(sf)
library(gstat)
library(automap)
library(terra)
library(tmap)

tmap_mode("plot")

source("R/utils_pipeline.R")
require_artifacts("train_sf_fase2.rds", "test_sf_fase2.rds", "variograma_empirico.rds",
                  "hull_concavo.rds", "formula_kriging.rds")

# Carga de datos de la Fase II
train_sf <- readRDS("data/processed/train_sf_fase2.rds")
test_sf <- readRDS("data/processed/test_sf_fase2.rds")
vario_emp <- readRDS("data/processed/variograma_empirico.rds")
hull_concavo <- readRDS("data/processed/hull_concavo.rds")
formula_kriging <- readRDS("data/processed/formula_kriging.rds")

# Ajuste del semivariograma teórico (Manual vs Automático)
modelos_teoricos <- vgm(psill = NA, range = NA, model = c("Sph", "Exp", "Gau", "Mat", "Ste"))

variograma_manual <- fit.variogram(vario_emp, model = modelos_teoricos, fit.method = 7)
av <- automap::autofitVariogram(formula_kriging, train_sf, model = c("Sph", "Exp", "Gau", "Mat", "Ste"), cressie = TRUE)

# Selección del mejor modelo según el error SSErr
sserr_manual <- attr(variograma_manual, "SSErr")
sserr_automap <- av$sserr
variograma_ajustado <- if (sserr_manual <= sserr_automap) variograma_manual else av$var_model

# Creación de grilla de predicción dentro de la envolvente cóncava
grilla_puntos <- st_make_grid(hull_concavo, n = c(150, 150), what = "centers")
idx_dentro <- st_intersects(grilla_puntos, st_union(hull_concavo), sparse = FALSE)[, 1]
grilla_sf <- st_as_sf(grilla_puntos[idx_dentro]) |> rename(geometry = x)
st_crs(grilla_sf) <- st_crs(train_sf)
grilla_sf$x_utm <- st_coordinates(grilla_sf)[, 1]
grilla_sf$y_utm <- st_coordinates(grilla_sf)[, 2]

# Ejecución del algoritmo Kriging (Interpolación)
kriging_resultado <- krige(formula_kriging, locations = train_sf, newdata = grilla_sf, model = variograma_ajustado)

# Rasterización de resultados (Predicción y Varianza)
extent_rejilla <- st_bbox(grilla_sf)
res_x <- (extent_rejilla$xmax - extent_rejilla$xmin) / sqrt(nrow(grilla_sf))
res_y <- (extent_rejilla$ymax - extent_rejilla$ymin) / sqrt(nrow(grilla_sf))
raster_vacio <- rast(
  extent = c(extent_rejilla["xmin"], extent_rejilla["xmax"], extent_rejilla["ymin"], extent_rejilla["ymax"]),
  resolution = c(res_x, res_y), crs = "EPSG:25830"
)

raster_pred <- rasterize(kriging_resultado, raster_vacio, field = "var1.pred")
raster_var <- rasterize(kriging_resultado, raster_vacio, field = "var1.var")

# Validación externa (Test Set)
test_sf$x_utm <- st_coordinates(test_sf)[, 1]
test_sf$y_utm <- st_coordinates(test_sf)[, 2]
kriging_test <- krige(formula_kriging, locations = train_sf, newdata = test_sf, model = variograma_ajustado)

test_sf$pred_log <- kriging_test$var1.pred
test_sf$pred_price <- exp(test_sf$pred_log)

# Cálculo de métricas de error
rmse_log <- sqrt(mean((test_sf$log_price - test_sf$pred_log)^2, na.rm = TRUE))
mae_log <- mean(abs(test_sf$log_price - test_sf$pred_log), na.rm = TRUE)
r2_log <- cor(test_sf$log_price, test_sf$pred_log, use = "complete.obs")^2
rmse_eur <- sqrt(mean((test_sf$house.price - test_sf$pred_price)^2, na.rm = TRUE))
mape <- mean(abs(test_sf$house.price - test_sf$pred_price) / test_sf$house.price, na.rm = TRUE) * 100

# Validación cruzada por bloques espaciales (5 folds)
bbox_train <- st_bbox(train_sf)
breaks_x <- seq(bbox_train["xmin"], bbox_train["xmax"], length.out = 6)
breaks_y <- seq(bbox_train["ymin"], bbox_train["ymax"], length.out = 6)
bloques <- paste0(
  cut(train_sf$x_utm, breaks_x, labels = F, include.lowest = T), "_",
  cut(train_sf$y_utm, breaks_y, labels = F, include.lowest = T)
)

set.seed(42)
bloques_unicos <- unique(bloques)
fold_map <- setNames(sample(rep(1:5, length.out = length(bloques_unicos))), bloques_unicos)
train_sf$fold_id <- fold_map[bloques]

resultados_cv <- map_df(1:5, function(i) {
  t_f <- train_sf[train_sf$fold_id != i, ]
  v_f <- train_sf[train_sf$fold_id == i, ]
  pr <- krige(formula_kriging, locations = t_f, newdata = v_f, model = variograma_ajustado)
  data.frame(fold = i, rmse = sqrt(mean((v_f$log_price - pr$var1.pred)^2, na.rm = T)))
})

# Guardado de artefactos finales
saveRDS(variograma_ajustado, "data/processed/variograma_ajustado.rds")
saveRDS(kriging_resultado, "data/processed/kriging_resultado.rds")
terra::writeRaster(raster_pred, "data/processed/kriging_raster_pred.tif", overwrite = TRUE)
terra::writeRaster(raster_var, "data/processed/kriging_raster_var.tif", overwrite = TRUE)
saveRDS(resultados_cv, "data/processed/kriging_cv.rds")
saveRDS(test_sf, "data/processed/test_sf_kriging.rds")

metricas_kriging <- data.frame(modelo = "Kriging", rmse_log = rmse_log, mae_log = mae_log, r2_log = r2_log, mape = mape, rmse_cv = mean(resultados_cv$rmse))
saveRDS(metricas_kriging, "data/processed/metricas_kriging.rds")
