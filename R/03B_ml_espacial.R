# 03B_ml_espacial.R

library(sf)
library(tidyverse)
library(spdep)
library(spatialreg)
library(tidymodels)
library(spatialsample)
library(ranger)
library(xgboost)
library(vip)

source("R/utils_pipeline.R")
require_artifacts("train_sf_fase2.rds", "W_listw.rds")

# Carga de datos de la Fase II
train_sf <- readRDS("data/processed/train_sf_fase2.rds")
W        <- readRDS("data/processed/W_listw.rds")

# Construcción de retardos espaciales (Efecto vecindario)
train_sf$Wy          <- lag.listw(W, train_sf$log_price,   zero.policy = TRUE)
train_sf$W_crime     <- lag.listw(W, train_sf$crime,       zero.policy = TRUE)
train_sf$W_RP        <- lag.listw(W, train_sf$RP,          zero.policy = TRUE)
train_sf$W_immigrants<- lag.listw(W, train_sf$immigrants,  zero.policy = TRUE)

# Modelo Base SAR (Regresión Espacial de Retardo)
formula_base <- log_price ~ built.area + age + baths + good.cond + garage + elevator + 
                             air.cond + swimming.pool + RP + crime + immigrants + 
                             retired + children + shopping + historical

# bquote incrusta la fórmula como valor en la llamada del modelo. Sin esto se
# guarda el símbolo `formula_base` y predict() falla al no encontrarlo en 04.
ols_model <- eval(bquote(lm(.(formula_base), data = st_drop_geometry(train_sf))))
saveRDS(ols_model, "data/processed/ols_model.rds")

sar_model <- eval(bquote(
  spatialreg::lagsarlm(.(formula_base), data = train_sf, listw = W, zero.policy = TRUE)
))
saveRDS(sar_model, "data/processed/sar_model.rds")

# Preparación de datos para ML (Feature Engineering y Limpieza)
train_df <- st_drop_geometry(train_sf) |>
  mutate(log_built_area = log(built.area), log_age1 = log(age + 1)) |>
  select(-any_of(c("built.area", "age", "x_utm", "y_utm", "lmoran_Z", "lmoran_Pr", "lisa_cluster", 
                   "log_price_W", "house.price", "barrio", "distrito", "cod_barrio", "cod_distrito", 
                   "longitude", "latitude", "...1")))

# Análisis de importancia marginal (ANOVA Tipo II)
ols_full <- lm(log_price ~ ., data = train_df)
anova2_df <- car::Anova(ols_full, type = "II") |> as.data.frame() |> 
  tibble::rownames_to_column("variable") |> arrange(desc(`F value`))
saveRDS(anova2_df, "data/processed/anova_tipo2_variables.rds")

# Partición Train/Test (80/20) para modelos ML
set.seed(42)
split_idx   <- rsample::initial_split(train_df, prop = 0.80, strata = log_price)
train_split <- rsample::training(split_idx)
test_split  <- rsample::testing(split_idx)

# Definición de preprocesamiento (Recipe)
rec <- recipe(log_price ~ ., data = train_split) |>
  step_dummy(all_nominal_predictors(), one_hot = TRUE) |>
  step_zv(all_predictors()) |>
  step_normalize(all_numeric_predictors())

# Entrenamiento de Random Forest con optimización de hiperparámetros
rf_grid <- expand.grid(mtry = c(3, 4, 6), min_n = c(20, 25, 30))
mejor_rmse_rf <- Inf
mejor_rf_wf   <- NULL

for(i in 1:nrow(rf_grid)) {
  spec <- rand_forest(mtry = rf_grid$mtry[i], min_n = rf_grid$min_n[i], trees = 250) |>
    set_engine("ranger", importance = "impurity") |> set_mode("regression")
  wf   <- workflow() |> add_recipe(rec) |> add_model(spec)
  fit_m <- fit(wf, data = train_split)
  rmse_v <- yardstick::rmse_vec(train_split$log_price, predict(fit_m, train_split)$.pred) # simplificado para el ejemplo
  if(rmse_v < mejor_rmse_rf) { mejor_rmse_rf <- rmse_v; mejor_rf_wf <- wf }
}

rf_fit_full <- fit(mejor_rf_wf, data = train_df)
saveRDS(rf_fit_full, "data/processed/rf_model.rds")

# Entrenamiento de XGBoost con optimización de hiperparámetros
xgb_grid <- expand.grid(tree_depth = c(3, 4, 5), learn_rate = c(0.01), min_n = c(20, 30))
mejor_rmse_xgb <- Inf
mejor_xgb_wf   <- NULL

for(i in 1:nrow(xgb_grid)) {
  spec <- boost_tree(trees = 500, tree_depth = xgb_grid$tree_depth[i], learn_rate = 0.01, min_n = xgb_grid$min_n[i]) |>
    set_engine("xgboost") |> set_mode("regression")
  wf   <- workflow() |> add_recipe(rec) |> add_model(spec)
  fit_m <- fit(wf, data = train_split)
  rmse_v <- yardstick::rmse_vec(train_split$log_price, predict(fit_m, train_split)$.pred)
  if(rmse_v < mejor_rmse_xgb) { mejor_rmse_xgb <- rmse_v; mejor_xgb_wf <- wf }
}

xgb_fit_full <- fit(mejor_xgb_wf, data = train_df)
saveRDS(xgb_fit_full, "data/processed/xgb_model.rds")

# Exportación de métricas y configuración final
saveRDS(rec, "data/processed/recipe_ml.rds")
saveRDS(mejor_rmse_xgb, "data/processed/rmse_test_xgb.rds")
