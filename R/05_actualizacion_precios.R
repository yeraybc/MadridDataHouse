# 05_actualizacion_precios.R

library(dplyr)

# Matriz de indexación histórica por distrito (compilado de informes de mercado)
# El índice representa el multiplicador de crecimiento desde 2010
indices_madrid <- data.frame(
  distrito = c(
    "Salamanca", "Centro", "Chamberí", "Retiro", "Chamartín",
    "Tetuán", "Arganzuela", "Hortaleza", "Moncloa - Aravaca",
    "Fuencarral - El Pardo", "Ciudad Lineal", "Barajas",
    "San Blas - Canillejas", "Latina", "Moratalaz", "Carabanchel",
    "Usera", "Villa de Vallecas", "Vicálvaro", "Villaverde",
    "Puente de Vallecas"
  ),
  indice_revalorizacion = c(
    1.58, 1.55, 1.55, 1.52, 1.46,
    1.50, 1.47, 1.40, 1.37,
    1.41, 1.38, 1.40,
    1.43, 1.40, 1.45, 1.37,
    1.33, 1.35, 1.39, 1.31,
    1.28
  )
)

# Guardar artefacto para uso en la aplicación Shiny
ruta_salida <- "data/processed/indice_precios_actuales.rds"
saveRDS(indices_madrid, ruta_salida)
