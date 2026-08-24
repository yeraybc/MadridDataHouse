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

Esto obliga a plantear el problema de otra manera. El precio de una vivienda no es independiente del de sus vecinas, así que el supuesto de independencia entre observaciones que sostiene un OLS no se cumple aquí. Ignorarlo no solo desaprovecha información: deja estructura sistemática en los residuos y vuelve poco fiable la inferencia.

Así pues, la localización se trata como señal y NO como ruido: 
- Se construye una matriz de pesos espaciales por KNN (k=8) que define quién es vecino de quién, y los **retardos de vecindario entran como predictores explícitos**: el precio del entorno, pero también su criminalidad, renta e inmigración.
- Por otro lado, se contrastan cuatro familias: OLS como referencia, SAR para modelar la dependencia de forma paramétrica, y Random Forest y XGBoost para la no-linealidad. Un Kriging Universal sirve de contraste geoestadístico independiente.

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

La separación `raw/` / `processed/` es la línea entre lo que es fuente y lo que es derivado: `data/raw/` solo contiene entradas añadidas, y todo lo que escribe el pipeline va a `data/processed/`.

Los scripts se pasan el trabajo unos a otros mediante ficheros `.rds`: el `02` lee lo que dejó el `01`, y así hasta el final. Añadirlos todos habría inflado el repositorio con datos regenerables, por otro lado, no añadir ninguno obliga a esperar media hora antes de poder abrir la app. Así pues, me decanté por añadir al repositorio los que las apps necesitan para arrancar, dejando fuera los intermedios (ver [.gitignore](.gitignore)).

Si ejecutases un script suelto sin haber corrido los anteriores, [utils_pipeline.R](R/utils_pipeline.R) corta antes de empezar y te dice qué artefacto falta y cómo generarlo.

## Fuente de datos

Datos de viviendas en Madrid con variables estructurales, socioeconómicas y de localización:
- Variables de vivienda: superficie, antigüedad, baños, estado, garaje, ascensor, aire acondicionado, piscina, tipo
- Variables de entorno: tasa de criminalidad, inmigración, población infantil, jubilados, proximidad a zonas comerciales e históricas
- Cartografía: shapefile de barrios y distritos de Madrid, del [Geoportal del Ayuntamiento de Madrid](https://geoportal.madrid.es/)

Los `.zip` originales del Geoportal están versionados en [data/raw/cartography/](data/raw/cartography/), así que el proyecto no depende de que esa URL siga viva: el script `01` usa los shapefiles si están, los descomprime del repositorio si no, y solo sale a la red como último recurso. Cada `.zip` se contrasta además con su SHA-256 en [checksums.txt](data/raw/cartography/checksums.txt), por lo que si el Ayuntamiento redibujara un límite administrativo, el script avisaría del cambio.

## Metodología

1. **Preparación y análisis espacial:** imputación de valores ausentes, construcción del objeto espacial (`sf`), matriz de pesos espaciales por KNN (k=8).
2. **EDA espacial:** test I de Moran (estadístico = 0.50, p < 0.001), análisis de clusters LISA (High-High / Low-Low) y semivariograma empírico.
3. **Modelado con cuatro familias:** OLS, SAR (Spatial Autoregressive), Random Forest y XGBoost, todos con features espaciales explícitos (retardos de vecindario).
4. **Kriging Universal** como modelo geoestadístico de referencia con validación cruzada 10-fold.
5. **Selección del modelo final** por RMSE, R² y ausencia de autocorrelación espacial en residuos.
6. **App Shiny en producción** con predicción en tiempo real, mapa de comparables y experiencia sin fricciones para el usuario.

## Resultados

| Modelo | RMSE (€/m²) | MAE (€/m²) | R² |
|--------|-------------|------------|----|
| OLS *(baseline)* | 907 | 674 | 0.43 |
| **XGBoost + features espaciales** | **745** | **529** | **0.62** |

Evaluado sobre 5.229 viviendas que ningún modelo vio durante el entrenamiento. El error baja un **17,8 % en RMSE** y un **21,5 % en MAE**, y la varianza explicada pasa del 43 % al 62 %.

### Qué significa esto en tasación

La mediana del conjunto usado es una vivienda de 80 m² a 3.548 €/m², unos **284.000 €**. Traducido a esa vivienda tipo:

| | OLS | XGBoost | |
|---|---|---|---|
| Error medio de tasación | 53.900 € | 42.300 € | **−11.600 €** |
| Sobre el valor del inmueble | 19,0 % | 14,9 % | −4,1 pp |

Once mil euros menos de error por tasación es la diferencia entre una cifra que es orientativa y una cifra sobre la que alguien puede negociar con fundamento.

### Por qué es la decisión correcta

El argumento de fondo no es el RMSE, sino **dónde** se equivoca cada modelo. El test de Moran sobre los residuos lo deja claro:

| Residuos del modelo | I de Moran | p |
|---|---|---|
| OLS | 0.2095 | 0.0020 |
| XGBoost | −0.0327 | 0.9980 |

El OLS deja autocorrelación espacial significativa en sus errores. En una tasación automática eso NO es ruido aleatorio: es un **sesgo geográfico sistemático**. Un modelo así puede llegar a infravalorar barrios enteros y sobrevalorar otros de forma consistente, y al perjudicado le toca vivir siempre en el mismo sitio. Da igual que el error medio sea aceptable: está mal repartido.

El modelo final no tiene ese problema: sus errores están geográficamente dispersos (I ≈ 0, p = 0.998). Se paga un precio por ello, porque un modelo no lineal es más difícil de interpretar que unos coeficientes de regresión, pero para un producto que le pone precio a la casa de alguien, que el error no dependa del barrio importa más que poder leer un coeficiente de regresión.

## Stack técnico

- **Lenguaje:** R
- **Econometría:** `spdep`, `spatialreg`, `gstat`
- **ML:** `tidymodels`, `ranger`, `xgboost`
- **Visualización:** `tmap`, `ggplot2`
- **App:** `shiny`

## Limitaciones reconocidas

- El modelo fue entrenado con datos de un mercado y período concreto. Fuera de ese contexto geográfico o temporal, la predicción pierde fiabilidad.
- La matriz de pesos espaciales del test set se construye con KNN interno, lo que introduce una aproximación respecto al entrenamiento.
- El modelo no incorpora variables temporales ni ciclos de mercado inmobiliario.
- En un futuro, se irá incluyendo información de más variables disponibles en el portal del ayuntamiento, así como actualizar los datos de los que se compone.

## Cómo ejecutar el proyecto en local

1. **Clona el repositorio**:
   ```bash
   git clone https://github.com/yeraybc/MadridDataHouse.git
   ```

2. **Abre `MadridDataHouse.Rproj`** en RStudio. Conviene fijar el directorio de trabajo en la raíz del proyecto, y todas las rutas de los scripts son relativas a ella.

3. **Prepara el entorno**:
   ```bash
   Rscript setup.R
   ```
   Comprueba la versión de R, verifica que GDAL/GEOS/PROJ estén disponibles (`sf` y `terra` los necesitan) e instala los paquetes de [requirements.txt](requirements.txt) que falten. No reinstala nada que ya cumpla la versión mínima.

4. **Levanta la aplicación**: los artefactos que necesita vienen en el repositorio, por lo que esto funciona sobre un clon recién hecho:
   ```r
   shiny::runApp("apps/app_ml")        # app principal
   shiny::runApp("apps/app_kriging")   # visualización geoestadística
   ```

5. **Reproduce el análisis completo** (opcional). Regenera desde cero los ~28 artefactos, incluidos los intermedios que no se versionan:
   ```bash
   Rscript R/run_all.R
   ```
   Corre los seis scripts en orden, informa del tiempo de cada uno y se detiene en el primer error indicando qué paso falló. Tarda unos 30 minutos: el kriging y el tuning de RF/XGBoost son las secciones más largas, debido al coste computacional.

6. **Despliegue** (opcional):
   ```bash
   Rscript deploy.R --dry-run    # muestra qué se subiría, sin publicar
   Rscript deploy.R              # publica ambas apps
   Rscript deploy.R app_ml       # publica solo una
   ```
   [deploy.R](deploy.R) copia a `apps/<app>/data/` los artefactos que ese `app.R` carga y sube un bundle acotado a lo que la app usa de verdad.

## Autor

**Yeray Benito Calviño**
Data Science student, Universidad Complutense de Madrid
[LinkedIn](https://www.linkedin.com/in/yeraybenit0) · [GitHub](https://github.com/yeraybc)

## Licencia

Distribuido bajo licencia MIT. Consulta el archivo [LICENSE](LICENSE) para más detalles.
