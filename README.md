# MadridDataHouse 🏠
Aplicación de tasación de viviendas en Madrid basada en ML espacial con componentes de econometría espacial.

## Motivación detrás del proyecto

Construido como proyecto personal para la asignatura de Análisis de Datos Espaciales (UCM). El punto de partida fue un problema real: cualquiera que haya intentado tasar el valor de su vivienda en una página web sabe lo que ocurre: rellenas las características, cedes tus datos, y en lugar de un precio te aparece un anuncio, un formulario de contacto o te piden que pagues un informe.

El objetivo fue resolver eso: construir una plataforma que estimase el precio de cualquier vivienda en Madrid de forma gratuita, instantánea y sin ceder datos personales.

> **💡 Hallazgo principal:** la variable con mayor poder predictivo no es la superficie, ni los baños, ni el ascensor. Es el precio de las viviendas del entorno. Tus vecinos determinan el valor de tu piso más que las características de tu propia casa.

## Estructura del proyecto
```
MadridDataHouse/
├── 01_preparacion_datos.R          # Limpieza, imputación y construcción del sf
├── 02_analisis_exploratorio.R      # EDA, I de Moran, clusters LISA, semivariograma
├── 03A_kriging.R                   # Kriging Universal: ajuste y validación cruzada
├── 03B_ml_espacial.R               # SAR, Random Forest y XGBoost con features espaciales
├── 04_validacion.R                 # Comparativa de modelos y métricas finales
├── 07_actualizacion_precios.R      # Actualización del índice de precios
├── 05_app_kriging/                 # Aplicación Shiny para visualización geoestadística
└── 06_app_ml/
    └── app.R                       # Aplicación Shiny principal en producción
```

## Fuente de datos

Datos de viviendas en Madrid con variables estructurales, socioeconómicas y de localización:
- Variables de vivienda: superficie, antigüedad, baños, estado, garaje, ascensor, aire acondicionado, piscina, tipo
- Variables de entorno: tasa de criminalidad, inmigración, población infantil, jubilados, proximidad a zonas comerciales e históricas
- Cartografía: shapefile de barrios y distritos de Madrid

## Metodología

1. **Preparación y análisis espacial:** imputación de valores ausentes, construcción del objeto espacial (`sf`), matriz de pesos espaciales por KNN (k=8).
2. **EDA espacial:** test I de Moran (estadístico = 0.50, p < 0.001), análisis de clusters LISA (High-High / Low-Low) y semivariograma empírico.
3. **Modelado con cuatro familias:** OLS, SAR (Spatial Autoregressive), Random Forest y XGBoost — todos con features espaciales explícitos (retardos de vecindario).
4. **Kriging Universal** como modelo geoestadístico de referencia con validación cruzada 10-fold.
5. **Selección del modelo final** por RMSE, R² y ausencia de autocorrelación espacial en residuos.
6. **App Shiny en producción** con predicción en tiempo real, mapa de comparables y experiencia sin fricciones para el usuario.

## Resultados

| Modelo | RMSE (€/m²) | R² |
|--------|-------------|----|
| OLS | 907 | 0.43 |
| XGBoost | 745 | 0.62 |

*Nota: La métrica de error representa el precio por metro cuadrado. Conseguimos una reducción de más de 160 €/m² respecto al modelo lineal base, capturando exitosamente la no-linealidad de la componente espacial.*

Test I de Moran sobre residuos XGBoost: **-0.03** (sin autocorrelación espacial residual).

## App en producción

👉 **[Prueba la aplicación MadridDataHouse aquí](https://yeraybc.shinyapps.io/MadridDataHouse/)**

<div align="center">
  <img src="assets/app_screenshot.png" alt="Demo MadridDataHouse" width="600">
</div>

## Stack técnico

- **Lenguaje:** R
- **Econometría espacial:** `spdep`, `spatialreg`, `gstat`
- **ML:** `tidymodels`, `ranger`, `xgboost`
- **Visualización:** `tmap`, `ggplot2`
- **App:** `shiny`

## Limitaciones reconocidas

- El modelo fue entrenado con datos de un mercado y período concreto. Fuera de ese contexto geográfico o temporal, la predicción pierde fiabilidad.
- La matriz de pesos espaciales del test set se construye con KNN interno, lo que introduce una aproximación respecto al entrenamiento.
- El modelo no incorpora variables temporales ni ciclos de mercado inmobiliario.

## 🚀 Cómo ejecutar el proyecto en local

1. **Clona el repositorio**: `git clone https://github.com/yeraybc/MadridDataHouse.git`
2. **Dependencias**: El proyecto requiere los siguientes paquetes principales de R: `spdep`, `spatialreg`, `gstat`, `tidymodels`, `ranger`, `xgboost`, `tmap` y `shiny`.
3. **Ejecución**: Corre los scripts en el orden numérico establecido (del `01` al `07`).
4. **App**: Para levantar la aplicación principal, abre el archivo `app.R` ubicado en la carpeta `06_app_ml` y haz click en "Run App".

## Autor

**Yeray Benito Calviño**
Estudiante de 3º Data Science — Universidad Complutense de Madrid
[LinkedIn](https://www.linkedin.com/in/yeraybc) · [GitHub](https://github.com/yeraybc)

## Licencia

Este proyecto se publica con fines educativos y de portafolio.