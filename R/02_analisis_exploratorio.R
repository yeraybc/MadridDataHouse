# 02_analisis_exploratorio.R

library(tidyverse)
library(sf)
library(spdep)
library(gstat)
library(tmap)

tmap_mode("plot")

source("R/utils_pipeline.R")
require_artifacts("train_sf.rds", "test_sf.rds", "W_listw.rds", "nb_w.rds",
                  "barrios_sf.rds", "distritos_sf.rds")

# Carga de datos preparados
train_sf <- readRDS("data/processed/train_sf.rds")
test_sf <- readRDS("data/processed/test_sf.rds")
W_listw <- readRDS("data/processed/W_listw.rds")
nb_w <- readRDS("data/processed/nb_w.rds")

# Imputación de valores ausentes (ZZZ)
# Se asume que ZZZ equivale a la ausencia del extra o categoría base
imputar_zzz <- function(data) {
  data |> mutate(
    type.house    = factor(ifelse(type.house == "ZZZ", "piso", as.character(type.house))),
    floor         = factor(ifelse(floor == "ZZZ", "bajo", as.character(floor))),
    good.cond     = factor(ifelse(good.cond == "ZZZ", "a_reformar", as.character(good.cond))),
    garage        = factor(ifelse(garage == "ZZZ", "no", as.character(garage))),
    elevator      = factor(ifelse(elevator == "ZZZ", "no", as.character(elevator))),
    air.cond      = factor(ifelse(air.cond == "ZZZ", "no", as.character(air.cond))),
    swimming.pool = factor(ifelse(swimming.pool == "ZZZ", "no", as.character(swimming.pool)))
  )
}

train_sf <- imputar_zzz(train_sf)
test_sf <- imputar_zzz(test_sf)

# Cálculo del retardo espacial (Lag) del precio
train_sf$log_price_W <- lag.listw(W_listw, train_sf$log_price)

# Análisis de autocorrelación espacial (I de Moran)
moran_result <- moran.test(train_sf$log_price, W_listw, zero.policy = TRUE)
print(moran_result)

# Test de Monte Carlo para validación de Moran
set.seed(1234)
moran_mc <- moran.mc(train_sf$log_price, W_listw, zero.policy = TRUE, nsim = 999, na.action = na.omit)
print(moran_mc)

# Análisis de clusters locales (LISA)
lmoran <- localmoran(train_sf$log_price, listw = W_listw, zero.policy = TRUE)
lmoran_sig <- as.data.frame(attr(lmoran, "quadr"))
lmoran_sig$Pr_z <- lmoran[, 5]

train_sf$lisa_cluster <- lmoran_sig |>
  mutate(quad = case_when(
    Pr_z > 0.05 ~ "No significativo",
    is.na(Pr_z) ~ NA_character_,
    TRUE ~ median
  )) |>
  pull(quad)

# Visualización de clusters LISA
map_lisa <- tm_shape(train_sf) +
  tm_dots(
    fill = "lisa_cluster",
    fill.scale = tm_scale_categorical(
      values = c(
        "High-High" = "#d7191c", "Low-Low" = "#2c7bb6",
        "High-Low" = "#fdae61", "Low-High" = "#abd9e9",
        "No significativo" = "grey85"
      )
    ),
    size = 0.05,
    fill.legend = tm_legend(title = "Cluster LISA")
  ) +
  tm_title("Análisis LISA: Clusters espaciales de precio") +
  tm_layout(legend.outside = TRUE)

# Detección de tendencia macro-espacial (Deriva)
trend_lm <- lm(log_price ~ x_utm + y_utm, data = train_sf)
coefs <- summary(trend_lm)$coefficients

# Selección de fórmula para Kriging (Universal vs Ordinario)
formula_kriging <- if (any(coefs[-1, "Pr(>|t|)"] < 0.05)) {
  log_price ~ x_utm + y_utm # Universal
} else {
  log_price ~ 1 # Ordinario
}

# Cálculo del semivariograma empírico (continuidad espacial)
vario_emp <- variogram(formula_kriging, data = train_sf, cressie = TRUE)
plot(vario_emp, main = "Semivariograma Empírico", xlab = "Distancia (m)", ylab = "Semivarianza")

# Agregación de estadísticas por barrio para el Dashboard
barrios_sf <- readRDS("data/processed/barrios_sf.rds")
distritos_sf <- readRDS("data/processed/distritos_sf.rds")

train_barrios <- train_sf |>
  st_drop_geometry() |>
  group_by(barrio) |>
  summarise(
    log_price_medio = mean(log_price, na.rm = TRUE),
    built.area_med  = mean(built.area, na.rm = TRUE),
    age_med         = mean(age, na.rm = TRUE),
    baths_med       = mean(baths, na.rm = TRUE),
    crime_med       = mean(crime, na.rm = TRUE),
    immigrants_med  = mean(immigrants, na.rm = TRUE),
    children_med    = mean(children, na.rm = TRUE),
    retired_med     = mean(retired, na.rm = TRUE),
    n_viviendas     = n()
  ) |>
  right_join(barrios_sf, by = c("barrio" = "NOMBRE")) |>
  st_as_sf()

# Guardado de resultados de la Fase II
saveRDS(vario_emp, "data/processed/variograma_empirico.rds")

# Sin vaciar su environment, la fórmula arrastra el dataset entero: 2.2 MB -> <1 KB
environment(formula_kriging) <- baseenv()
saveRDS(formula_kriging, "data/processed/formula_kriging.rds")
saveRDS(train_sf, "data/processed/train_sf_fase2.rds")
saveRDS(test_sf, "data/processed/test_sf_fase2.rds")
saveRDS(train_barrios, "data/processed/estadisticas_barrios.rds")


# Tests de calidad
stopifnot(moran_result$p.value < 0.05)
stopifnot(nrow(vario_emp) > 5)
cat("OK.\n")
