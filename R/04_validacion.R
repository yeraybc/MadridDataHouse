# 04_validacion.R — Validación

library(sf)
library(tidyverse)
library(spdep)
library(spatialreg)
library(gstat)
library(tidymodels)
library(yardstick)
library(tmap)

tmap_mode("plot")

# Carga de modelos y datos de fases anteriores
train_sf            <- readRDS("datos/train_sf_fase2.rds")
test_sf             <- readRDS("datos/test_sf_fase2.rds")
W                   <- readRDS("datos/W_listw.rds")
ols_model           <- readRDS("datos/ols_model.rds")
sar_model           <- readRDS("datos/sar_model.rds")
rf_fit              <- readRDS("datos/rf_model.rds")
xgb_fit             <- readRDS("datos/xgb_model.rds")
variograma_ajustado <- readRDS("datos/variograma_ajustado.rds")
formula_kriging     <- readRDS("datos/formula_kriging.rds")

# Preparación del Test Set (Caja Fuerte)
test_sf$x_utm <- st_coordinates(test_sf)[, 1]
test_sf$y_utm <- st_coordinates(test_sf)[, 2]

# Matriz de pesos y retardos espaciales para el test set
W_test <- nb2listw(knn2nb(knearneigh(st_coordinates(test_sf), k = 8)), style = "W")
test_sf$Wy           <- lag.listw(W_test, test_sf$log_price,   zero.policy = TRUE)
test_sf$W_crime      <- lag.listw(W_test, test_sf$crime,       zero.policy = TRUE)
test_sf$W_RP         <- lag.listw(W_test, test_sf$RP,          zero.policy = TRUE)
test_sf$W_immigrants <- lag.listw(W_test, test_sf$immigrants,  zero.policy = TRUE)

# Preparación de datos para modelos ML
test_df <- st_drop_geometry(test_sf) |>
  mutate(log_built_area = log(built.area), log_age1 = log(age + 1)) |>
  select(-any_of(c("built.area", "age", "house.price", "x_utm", "y_utm", "barrio", "distrito", 
                   "cod_barrio", "cod_distrito", "longitude", "latitude", "...1")))

# Generación de predicciones comparativas
results <- tibble(
  log_price_obs = test_sf$log_price,
  pred_ols      = predict(ols_model, newdata = st_drop_geometry(test_sf)),
  pred_sar      = as.numeric(predict(sar_model, newdata = test_sf, listw = W_test, pred.type = "TS")),
  pred_rf       = predict(rf_fit,  new_data = test_df)$.pred,
  pred_xgb      = predict(xgb_fit, new_data = test_df)$.pred
)

# Test de Moran sobre residuos (Verificación de ruido blanco)
evaluar_moran <- function(nombre, residuos, listw) {
  m <- moran.mc(residuos, listw = listw, nsim = 499, zero.policy = TRUE)
  cat(sprintf("%-10s | I = %6.4f | p = %.4f\n", nombre, m$statistic, m$p.value))
}

cat("Test de Moran sobre residuos:\n")
evaluar_moran("OLS", resid(ols_model), W)
evaluar_moran("XGBoost", results$log_price_obs - results$pred_xgb, W_test)

# Validación cruzada de Kriging (10-fold)
if (file.exists("datos/kriging_cv_gstat.rds")) {
  krig_cv <- readRDS("datos/kriging_cv_gstat.rds")
} else {
  krig_cv <- gstat::krige.cv(formula_kriging, train_sf, variograma_ajustado, nfold = 10)
  saveRDS(krig_cv, "datos/kriging_cv_gstat.rds")
}

# Consolidación de métricas finales (€/m²)
met <- metric_set(rmse, mae, rsq)
results_euro <- results |> mutate(across(starts_with("pred"), exp), obs = exp(log_price_obs))

metricas_finales <- bind_rows(
  met(results_euro, truth = obs, estimate = pred_ols) |> mutate(modelo = "OLS"),
  met(results_euro, truth = obs, estimate = pred_xgb) |> mutate(modelo = "XGBoost")
) |> pivot_wider(names_from = .metric, values_from = .estimate)

# Guardado de resultados de validación
saveRDS(metricas_finales, "datos/metricas_finales.rds")
saveRDS(test_sf,          "datos/test_sf_resultados.rds")
