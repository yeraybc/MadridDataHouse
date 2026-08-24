# MadridDataHouse 🏠

[![R](https://img.shields.io/badge/R-4.x-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)
[![Shiny](https://img.shields.io/badge/Shiny-app%20en%20producción-447099?logo=rstudio&logoColor=white)](https://yeraybc.shinyapps.io/MadridDataHouse/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Last commit](https://img.shields.io/github/last-commit/yeraybc/MadridDataHouse)

Aplicación de tasación de viviendas en Madrid basada en ML espacial con componentes de econometría espacial.

## Índice

- [Motivación detrás del proyecto](#motivación-detrás-del-proyecto)
- [App en producción](#app-en-producción)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Fuente de datos](#fuente-de-datos)
- [Metodología](#metodología)
- [Resultados](#resultados)
- [Stack técnico](#stack-técnico)
- [Limitaciones reconocidas](#limitaciones-reconocidas)
- [Cómo ejecutar el proyecto en local](#-cómo-ejecutar-el-proyecto-en-local)
- [Autor](#autor)
- [Licencia](#licencia)

## Motivación detrás del proyecto

Proyecto personal de análisis espacial aplicado al mercado inmobiliario de Madrid. El punto de partida fue un problema real: cualquiera que haya intentado tasar el valor de su vivienda en una página web sabe lo que ocurre: rellenas las características, cedes tus datos, y en lugar de un precio te aparece un anuncio, un formulario de contacto o te piden que pagues un informe.

El objetivo fue resolver eso: construir una plataforma que estimase el precio de cualquier vivienda en Madrid de forma gratuita, instantánea y sin ceder datos personales.

> **💡 Hallazgo principal:** la variable con mayor poder predictivo no es la superficie, ni los baños, ni el ascensor. Es el precio de las viviendas del entorno. Tus vecinos determinan el valor de tu piso más que las características de tu propia casa.

## App en producción

👉 **[Prueba la aplicación MadridDataHouse aquí](https://yeraybc.shinyapps.io/MadridDataHouse/)**

![Demo MadridDataHouse](assets/demo_app.png)

## Estructura del proyecto

```
MadridDataHouse/
├── R/                                  # Pipeline de análisis, en orden de ejecución
│   ├── 01_preparacion_datos.R          # Limpieza, imputación y construcción del objeto sf
│   ├── 02_analisis_exploratorio.R      # EDA, I de Moran, clusters LISA, semivariograma
│   ├── 03A_kriging.R                   # Kriging Universal: ajuste y validación cruzada
│   ├── 03B_ml_espacial.R               # SAR, Random Forest y XGBoost con features espaciales
│   ├── 04_validacion.R                 # Comparativa de modelos y métricas finales
│   ├── 05_actualizacion_precios.R      # Actualización del índice de precios por distrito
│   ├── run_all.R                       # Ejecuta el pipeline completo en orden
│   └── utils_pipeline.R                # Guardas de artefactos compartidas por los scripts
├── apps/
│   ├── app_ml/                         # App Shiny principal (la que está en producción)
│   └── app_kriging/                    # App Shiny de visualización geoestadística
├── data/
│   ├── raw/                            # Entradas versionadas
│   │   ├── Data_Housing_Madrid.csv
│   │   ├── variables_dictionary.txt    # Diccionario de variables
│   │   └── cartography/                # Shapefiles de barrios y distritos (Geoportal de Madrid)
│   └── processed/                      # Artefactos que genera el pipeline
├── assets/                             # Imágenes del README
├── requirements.txt                    # Dependencias de R con versiones mínimas
├── setup.R                             # Prepara el entorno (verifica e instala dependencias)
├── deploy.R                            # Publica las apps en shinyapps.io
├── LICENSE
├── MadridDataHouse.Rproj
└── README.md
```

La separación `raw/` / `processed/` es la línea entre lo que es fuente y lo que es derivado: `data/raw/` solo contiene entradas versionadas, y todo lo que escribe el pipeline va a `data/processed/`.

De esos artefactos **se versionan únicamente los que cargan las apps**, para que un clon pueda levantarlas sin ejecutar el pipeline entero. Los intermedios quedan fuera (ver [.gitignore](.gitignore)). Si ejecutas un script sin haber corrido los anteriores, la guarda de [utils_pipeline.R](R/utils_pipeline.R) aborta indicando qué artefactos faltan en vez de dar un error de fichero no encontrado.

## Fuente de datos

Datos de viviendas en Madrid con variables estructurales, socioeconómicas y de localización:
- Variables de vivienda: superficie, antigüedad, baños, estado, garaje, ascensor, aire acondicionado, piscina, tipo
- Variables de entorno: tasa de criminalidad, inmigración, población infantil, jubilados, proximidad a zonas comerciales e históricas
- Cartografía: shapefile de barrios y distritos de Madrid, del [Geoportal del Ayuntamiento de Madrid](https://geoportal.madrid.es/)

Los `.zip` originales del Geoportal están versionados en [data/raw/cartography/](data/raw/cartography/), así que el proyecto no depende de que esa URL siga viva. El script `01` los resuelve en este orden: usa los `.shp` si están, si no descomprime los `.zip` del repositorio (sin red), y solo descarga del Geoportal si tampoco están. Si eso falla, el error indica cómo restaurarlos.

Cada `.zip` se verifica contra los SHA-256 de [checksums.txt](data/raw/cartography/checksums.txt). Si una descarga futura devolviese datos distintos — el Ayuntamiento redibuja un límite administrativo, por ejemplo — el script avisa de que los resultados pueden diferir de los publicados aquí, en lugar de cambiarlos en silencio.

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

1. **Clona el repositorio**:
   ```bash
   git clone https://github.com/yeraybc/MadridDataHouse.git
   ```

2. **Abre `MadridDataHouse.Rproj`** en RStudio. Es el paso importante: fija el directorio de trabajo en la raíz del proyecto, y todas las rutas de los scripts son relativas a ella.

3. **Prepara el entorno**:
   ```bash
   Rscript setup.R
   ```
   Comprueba la versión de R, verifica que GDAL/GEOS/PROJ estén disponibles (`sf` y `terra` los necesitan) e instala los paquetes de [requirements.txt](requirements.txt) que falten. No reinstala nada que ya cumpla la versión mínima.

4. **Levanta la aplicación** — los artefactos que necesita vienen en el repositorio, así que esto funciona sobre un clon recién hecho:
   ```r
   shiny::runApp("apps/app_ml")        # app principal
   shiny::runApp("apps/app_kriging")   # visualización geoestadística
   ```

5. **Reproduce el análisis completo** (opcional). Regenera desde cero los ~28 artefactos, incluidos los intermedios que no se versionan:
   ```bash
   Rscript R/run_all.R
   ```
   Corre los seis scripts en orden, informa del tiempo de cada uno y se detiene en el primer error indicando qué paso falló. Tarda unos 30 minutos: el kriging y el tuning de RF/XGBoost son los tramos largos.

6. **Despliegue** (opcional):
   ```bash
   Rscript deploy.R --dry-run    # muestra qué se subiría, sin publicar
   Rscript deploy.R              # publica ambas apps
   Rscript deploy.R app_ml       # publica solo una
   ```
   [deploy.R](deploy.R) copia a `apps/<app>/data/` exactamente los artefactos que ese `app.R` carga y sube un bundle acotado a lo que la app usa de verdad.

   > **Nota para el mantenedor:** el despliegue **actualiza** las apps ya publicadas en su misma URL. Eso depende de `apps/<app>/rsconnect/`, que está gitignorado y solo existe en la máquina desde la que se desplegó por primera vez. Si borras esa carpeta, el siguiente despliegue creará apps nuevas en URLs distintas en lugar de actualizar las existentes.

## Autor

**Yeray Benito Calviño**
Data Science — Universidad Complutense de Madrid
[LinkedIn](https://www.linkedin.com/in/yeraybenit0) · [GitHub](https://github.com/yeraybc)

## Licencia

Distribuido bajo licencia MIT. Consulta el archivo [LICENSE](LICENSE) para más detalles.
