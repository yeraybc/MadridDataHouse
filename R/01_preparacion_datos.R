# 01_preparacion_datos.R — Preparación de Datos Espaciales

library(tidyverse)
library(sf)
library(spdep)
library(concaveman)
library(tmap)

tmap_mode("plot")

# Carga de datos
df <- read_csv("datos/Data_Housing_Madrid.csv", show_col_types = FALSE)
df <- df |> select(-1) # Eliminar índice H1

cat("Dimensiones:", nrow(df), "x", ncol(df), "\n")

# Limpieza de outliers (IQR*3 para preservar segmento de lujo)
stats   <- quantile(df$house.price, probs = c(0.25, 0.75), na.rm = TRUE)
iqr_val <- diff(stats)
q_low   <- stats[1] - 3 * iqr_val
q_high  <- stats[2] + 3 * iqr_val

df <- df |> filter(between(house.price, q_low, q_high))
cat("Viviendas restantes tras outliers:", nrow(df), "\n")

# Transformación logarítmica (normalización y estabilización)
df <- df |> mutate(log_price = log(house.price))

# Conversión de variables categóricas a factores
cat_vars <- c("type.house", "floor", "good.cond", "garage", "elevator", "air.cond", "swimming.pool")
df <- df |> mutate(across(all_of(cat_vars), ~ factor(.x)))

# Conversión a objeto espacial (WGS84 -> UTM30N)
df_sf <- st_as_sf(df, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
df_sf <- st_transform(df_sf, crs = 25830)

df_sf$x_utm <- st_coordinates(df_sf)[, 1]
df_sf$y_utm <- st_coordinates(df_sf)[, 2]

# Carga de cartografía oficial
if (!dir.exists("datos/cartografia")) dir.create("datos/cartografia", recursive = TRUE)

# Descarga de distritos
if (!file.exists("datos/cartografia/DISTRITOS.shp")) {
  download.file("https://geoportal.madrid.es/fsdescargas/IDEAM_WBGEOPORTAL/LIMITES_ADMINISTRATIVOS/Distritos/Distritos.zip",
                destfile = "datos/cartografia/Distritos.zip", mode = "wb")
  unzip("datos/cartografia/Distritos.zip", exdir = "datos/cartografia")
}

# Descarga de barrios
if (!file.exists("datos/cartografia/BARRIOS.shp")) {
  download.file("https://geoportal.madrid.es/fsdescargas/IDEAM_WBGEOPORTAL/LIMITES_ADMINISTRATIVOS/Barrios/Barrios.zip",
                destfile = "datos/cartografia/Barrios.zip", mode = "wb")
  unzip("datos/cartografia/Barrios.zip", exdir = "datos/cartografia")
}

distritos_sf <- st_read("datos/cartografia/DISTRITOS.shp", quiet = TRUE) |> st_transform(25830)
barrios_sf <- st_read("datos/cartografia/BARRIOS.shp", quiet = TRUE) |> st_transform(25830)

# Asignación espacial de barrio y distrito
df_sf <- st_join(df_sf, barrios_sf |> select(barrio = NOMBRE, distrito = NOMDIS), join = st_within)

# Filtro para municipio de Madrid (eliminar extrarradio)
df_sf <- df_sf |> filter(!is.na(barrio))
df_sf <- df_sf |> select(-M.30)
df_sf <- df_sf |> mutate(barrio = factor(barrio), distrito = factor(distrito))

# Partición train/test (50/50)
set.seed(42)
n <- nrow(df_sf)
idx_train <- sample(1:n, size = floor(0.5 * n))
train_sf <- df_sf[idx_train, ]
test_sf  <- df_sf[-idx_train, ]

# Matriz de pesos espaciales (k=8 vecinos más cercanos)
coords_train <- st_coordinates(train_sf)
knn     <- knearneigh(coords_train, k = 8)
nb_w    <- knn2nb(knn)
W_listw <- nb2listw(nb_w, style = "W")

# Envolvente cóncava para límites de predicción
hull_concavo <- concaveman(train_sf)

# Guardado de artefactos
saveRDS(df_sf,        "datos/df_sf_completo.rds")
saveRDS(train_sf,     "datos/train_sf.rds")
saveRDS(test_sf,      "datos/test_sf.rds")
saveRDS(nb_w,         "datos/nb_w.rds")
saveRDS(W_listw,      "datos/W_listw.rds")
saveRDS(hull_concavo, "datos/hull_concavo.rds")
saveRDS(barrios_sf,   "datos/barrios_sf.rds")
saveRDS(distritos_sf, "datos/distritos_sf.rds")

# Tests de calidad
cat("Ejecutando validaciones...\n")
stopifnot(nrow(df_sf) > 5000)
stopifnot(all(!is.na(df_sf$barrio)))
stopifnot(st_crs(df_sf)$epsg == 25830)
cat("OK.\n")
