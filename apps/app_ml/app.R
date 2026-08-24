library(shiny)
library(leaflet)
library(sf)
library(tidymodels)
library(vip)
library(tidyverse)
library(ranger)
library(xgboost)
library(scales)

# Carga de datos
cargar_artefacto <- function(archivo) {
  if (file.exists(paste0("datos/", archivo))) {
    return(readRDS(paste0("datos/", archivo)))
  } else if (file.exists(paste0("../datos/", archivo))) {
    return(readRDS(paste0("../datos/", archivo)))
  } else {
    stop(paste("Error: No se encuentra", archivo))
  }
}

train_sf  <- cargar_artefacto("train_sf_fase2.rds")
rf_model  <- cargar_artefacto("rf_model.rds")
xgb_model <- cargar_artefacto("xgb_model.rds")
metricas  <- cargar_artefacto("metricas_finales.rds")

# Datos geográficos
distritos_sf <- cargar_artefacto("distritos_sf.rds") |> st_transform(4326)
barrios_sf   <- cargar_artefacto("barrios_sf.rds") |> st_transform(4326)
indices_mercado <- cargar_artefacto("indice_precios_actuales.rds")

if (!"x_utm" %in% names(train_sf)) {
  train_sf$x_utm <- st_coordinates(train_sf)[, 1]
  train_sf$y_utm <- st_coordinates(train_sf)[, 2]
}

lvl <- function(var) levels(train_sf[[var]])

format_choices <- function(levels_vec) {
  pretty <- tools::toTitleCase(gsub("_", " ", levels_vec))
  setNames(levels_vec, pretty)
}

# Estilos
custom_css <- "
@import url('https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,600;1,400&family=Inter:wght@300;400;500;600&display=swap');

body {
  font-family: 'Inter', sans-serif;
  margin: 0;
  padding: 0;
  background: url('bg.png') no-repeat center center fixed;
  background-size: cover;
  color: #0A0A0A;
}

.luxury-navbar {
  width: 100%;
  height: 60px;
  background-color: rgba(244, 234, 222, 0.95);
  display: flex;
  align-items: center;
  padding: 0 40px;
  border-bottom: 1px solid #D8CDBF;
  position: absolute;
  top: 0;
  left: 0;
  z-index: 999;
}
.luxury-navbar h1 {
  font-family: 'Playfair Display', serif;
  font-size: 22px;
  letter-spacing: 2px;
  margin: 0;
  font-weight: 600;
}

.luxury-modal-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  padding-top: 80px; 
}

.luxury-modal {
  background: #F4EADE;
  width: 600px;
  max-width: 90%;
  border-radius: 4px;
  box-shadow: 0 20px 40px rgba(0,0,0,0.15);
  padding: 40px 50px;
  position: relative;
  overflow: hidden;
}

.step-indicator {
  font-size: 11px;
  font-weight: 600;
  color: #888;
  text-transform: uppercase;
  letter-spacing: 1px;
  margin-bottom: 20px;
  border-bottom: 2px solid #000;
  display: inline-block;
  padding-bottom: 5px;
}

h2.step-title {
  font-family: 'Playfair Display', serif;
  font-size: 32px;
  font-weight: 400;
  text-align: center;
  margin-top: 0;
  margin-bottom: 40px;
  color: #0A0A0A;
}

label {
  font-weight: 500;
  font-size: 13px;
  color: #555;
  margin-bottom: 8px;
  display: block;
}
.form-control {
  border-radius: 0;
  border: 1px solid #ccc;
  padding: 12px 15px;
  height: auto;
  font-size: 15px;
  box-shadow: none !important;
}
.form-control:focus {
  border-color: #000;
}

.checkbox-block {
  border: 1px solid #e0e0e0;
  padding: 15px 20px;
  margin-bottom: 15px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  cursor: pointer;
  transition: all 0.2s;
}
.checkbox-block:hover {
  border-color: #aaa;
}
.checkbox-block .shiny-input-container {
  margin-bottom: 0 !important;
}
.checkbox-block label {
  cursor: pointer;
  margin: 0;
  font-weight: 500;
  font-size: 16px;
}
.checkbox-block input {
  margin-right: 15px !important;
  transform: scale(1.3);
}

.btn-next, .btn-back, .btn-reset {
  border-radius: 0;
  padding: 12px 25px;
  font-size: 14px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 1px;
  border: none;
  transition: all 0.3s;
}
.btn-next {
  background-color: #0A0A0A;
  color: #F4EADE;
  float: right;
}
.btn-next:hover, .btn-next:focus {
  background-color: #333;
  color: #F4EADE;
}
.btn-next[disabled] {
  background-color: #ccc;
  cursor: not-allowed;
}
.btn-back {
  background-color: transparent;
  color: #0A0A0A;
  border: 1px solid #ccc;
  float: left;
}
.btn-back:hover {
  border-color: #0A0A0A;
}

.btn-reset {
  background-color: #f4f4f4;
  color: #333;
  border: 1px solid #ddd;
  font-size: 11px;
  padding: 6px 12px;
  width: 100%;
  margin-bottom: 15px;
}
.btn-reset:hover {
  background-color: #e0e0e0;
}

.nav-tabs { display: none; }
.tab-content { padding: 0; }

.result-price {
  font-family: 'Playfair Display', serif;
  font-size: 48px;
  font-weight: 600;
  text-align: center;
  color: #0A0A0A;
  margin-bottom: 5px;
}
.result-subtitle {
  text-align: center;
  color: #777;
  font-size: 14px;
  margin-bottom: 30px;
}

@media print {
  body { background: #fff !important; color: #000 !important; }
  .luxury-navbar { display: none !important; }
  .luxury-modal-container { padding-top: 0 !important; }
  .luxury-modal { 
    box-shadow: none !important; 
    border: none !important; 
    padding: 0 !important; 
    width: 100% !important; 
    max-width: 100% !important; 
    background: #fff !important;
  }
  .btn-next, .btn-back, .btn-reset, #btn_imprimir_certificado, #btn_informe_premium, #btn_perfil_inversor { display: none !important; }
  .step-indicator { display: none !important; }
  h2.step-title { margin-bottom: 20px !important; font-size: 24px !important; }
  .result-price { font-size: 64px !important; }
  hr { border-color: #eee !important; }
  .modal-footer { display: none !important; }
}
"

# Interfaz de usuario
ui <- fluidPage(title = "MadridDataHouse",
  tags$head(tags$style(HTML(custom_css))),
  
  div(class = "luxury-navbar", h1("MadridDataHouse")),
  
  div(class = "luxury-modal-container",
      div(class = "luxury-modal",
          tabsetPanel(id = "wizard", type = "tabs",
            
            tabPanel("step1", value = "step1",
              div(class = "step-indicator", "1 / 4  Su valoración digital"),
              h2(class = "step-title", "¿Dónde está ubicada su propiedad?"),
              uiOutput("mapa_instruction"),
              uiOutput("btn_volver_mapa"),
              leafletOutput("mapa", height = "350px"),
              br(),
              uiOutput("btn_siguiente_mapa")
            ),
            
            tabPanel("step2", value = "step2",
              div(class = "step-indicator", "2 / 4  Detalles de la propiedad"),
              h2(class = "step-title", "Introduzca los detalles"),
              selectInput("type_house", "Estado de la propiedad", choices = format_choices(lvl("type.house")), width = "100%"),
              selectInput("good_cond",  "Condición", choices = format_choices(lvl("good.cond")), width = "100%"),
              fluidRow(
                column(6, numericInput("built_area", "Superficie construida (m²)", value = 100, min = 20, max = 500)),
                column(6, numericInput("floor", "Planta (Numérica)", value = 3, min = 0, max = 20))
              ),
              fluidRow(
                column(6, numericInput("baths", "Nº de baños", value = 1, min = 1, max = 6)),
                column(6, numericInput("age", "Antigüedad (años)", value = 20, min = 0, max = 100))
              ),
              br(),
              actionButton("back_step1", "< Volver", class = "btn-back"),
              actionButton("to_step3", "Siguiente >", class = "btn-next")
            ),
            
            tabPanel("step3", value = "step3",
              div(class = "step-indicator", "3 / 4  Características extra"),
              h2(class = "step-title", "Características de su propiedad"),
              div(class = "checkbox-block", checkboxInput("chk_pool", "Piscina", value = FALSE)),
              div(class = "checkbox-block", checkboxInput("chk_garage", "Estacionamiento (Garaje)", value = FALSE)),
              div(class = "checkbox-block", checkboxInput("chk_elevator", "Ascensor", value = FALSE)),
              div(class = "checkbox-block", checkboxInput("chk_aircond", "Aire Acondicionado", value = FALSE)),
              br(),
              actionButton("back_step2", "< Volver", class = "btn-back"),
              actionButton("to_step4", "Valorar >", class = "btn-next")
            ),
            
            tabPanel("step4", value = "step4",
              div(class = "step-indicator", "4 / 4  Resultado de tasación"),
              h2(class = "step-title", "El valor estimado"),
              uiOutput("resultado_final"),
              leafletOutput("mapa_resultado", height = "250px"),
              p("Puntos naranjas: Comparables de la zona.", style="font-size:12px; color:#888; text-align:center; margin-top:5px;"),
              br(),
              actionButton("back_step3", "< Editar Características", class = "btn-back"),
              actionButton("restart", "Nueva Tasación", class = "btn-next")
            )
          )
      )
  )
)

# Servidor
server <- function(input, output, session) {

  map_state    <- reactiveVal(0)
  distrito_sel <- reactiveVal(NULL)
  barrio_sel   <- reactiveVal(NULL)
  coords_click <- reactiveVal(NULL)
  
  premium_rv <- reactiveValues(
    capital_latente = NULL,
    mult = NULL,
    html_reforma = NULL,
    precio_total = NULL
  )
  
  observeEvent(input$btn_informe_premium, {
    req(premium_rv$capital_latente)
    showModal(modalDialog(
      title = div(style="text-align:center; color:#C69B3C; font-family:serif; font-weight:bold; letter-spacing:1px; font-size: 18px;", "EVALUACIÓN PREMIUM DEL ACTIVO"),
      size = "m",
      easyClose = TRUE,
      footer = div(style="display:flex; justify-content:space-between; border-top: 1px solid #eee; padding-top:15px;", 
                   tags$button(icon("print"), " IMPRIMIR INFORME (PDF)", onclick="window.print();", class="btn btn-default", style="background-color:#0A0A0A; color:#C69B3C; border:1px solid #C69B3C; font-family:serif; letter-spacing:1px;"),
                   modalButton("Cerrar Informe")
      ),
      tags$style(HTML("
        .modal-content { border-radius: 4px; border: none; box-shadow: 0 10px 30px rgba(0,0,0,0.1); }
        .modal-header { border-bottom: 1px solid #eee; padding: 20px; }
        .modal-body { padding: 30px; background-color: #faf9f6; }
      ")),
      
      premium_rv$html_desglose,
      premium_rv$html_testigos,
      
      div(style="background-color:#ffffff; padding:25px 15px; border-radius:4px; border: 1px solid #e6d5b8; margin-bottom:20px;",
        p(strong("REVALORIZACIÓN DE LA VIVIENDA (2010 - 2026)"), style="margin-bottom:20px; color:#0A0A0A; text-align:center; font-size:12px; letter-spacing:1px; font-family:serif; text-transform:uppercase;"),
        plotOutput("grafico_genesis", height = "220px"),
        p(style="text-align:center; font-size:14px; margin-top:15px; color:#0A0A0A; font-family:serif;",
          "Plusvalía latente estimada: ", strong(style="color:#C69B3C;", paste0("+", format(premium_rv$capital_latente, big.mark=".", decimal.mark=","), " €")), 
          br(),
          span(style="font-size:12px; color:#888;", paste0("(", round((premium_rv$mult-1)*100), "% de revalorización histórica)"))
        )
      ),
      div(style="background-color:#ffffff; padding:20px; border-radius:4px; border: 1px solid #e6d5b8; margin-bottom:20px;",
        p(strong("PERFIL DEL ENTORNO"), style="margin-bottom:5px; color:#0A0A0A; text-align:center; font-size:12px; letter-spacing:1px; font-family:serif; text-transform:uppercase;"),
        p("Análisis espacial vs. Media de Madrid (Percentiles)", style="text-align:center; font-size:11px; color:#888; margin-bottom:5px; font-family:serif;"),
        plotOutput("radar_entorno", height = "260px")
      ),
      
      div(style="background-color:#ffffff; padding:20px; border-radius:4px; border: 1px solid #e6d5b8; margin-bottom:20px;",
        p(strong("PROYECCIÓN VALOR VIVIENDA"), style="margin-bottom:15px; color:#0A0A0A; text-align:center; font-size:12px; letter-spacing:1px; font-family:serif; text-transform:uppercase; border-bottom: 1px solid #eee; padding-bottom:10px;"),
        plotOutput("grafico_proyeccion_capital", height = "180px"),
        uiOutput("texto_proyeccion"),
        p("Fuente Empírica: Serie Histórica 2010-2024. Tasas de crecimiento reales por distrito.", style="text-align:center; color:#555; font-size:10px; margin-top:15px; font-family:serif; letter-spacing:0.5px;")
      ),
      
      div(style="background-color:#ffffff; padding:20px; border-radius:4px; border: 1px solid #e6d5b8; margin-bottom:20px;",
        p(strong("FRANJAS DE PRECIO (DEAL CHECK)"), style="margin-bottom:15px; color:#0A0A0A; text-align:center; font-size:12px; letter-spacing:1px; font-family:serif; text-transform:uppercase; border-bottom: 1px solid #eee; padding-bottom:10px;"),
        uiOutput("resultado_brecha_valor")
      ),
      
      div(style="border: 1px solid #e6d5b8; border-radius:4px; overflow:hidden;",
        premium_rv$html_reforma
      )
    ))
  })
  
  output$resultado_brecha_valor <- renderUI({
    req(premium_rv$precio_total)
    estimado <- premium_rv$precio_total
    precio_fuerte_descuento <- estimado * 0.90
    precio_sobreprecio      <- estimado * 1.05
    
    div(
      div(style="background-color:rgba(46, 125, 50, 0.05); border-left: 3px solid #4caf50; padding:12px; margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;",
        div(
          p(strong("Target Descuento (-10%)"), style="color:#2e7d32; margin:0; font-size:13px;"),
          p(paste0("+", format(estimado - precio_fuerte_descuento, big.mark=".", decimal.mark=","), " € Margen de entrada"), style="color:#388e3c; margin:0; font-size:11px;")
        ),
        p(strong(paste0(format(precio_fuerte_descuento, big.mark=".", decimal.mark=","), " €")), style="color:#0A0A0A; margin:0; font-size:15px;")
      ),
      div(style="background-color:#F4EADE; border-left: 3px solid #ccc; padding:12px; margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;",
        div(
          p(strong("Valor Técnico de Mercado"), style="color:#555; margin:0; font-size:13px;"),
          p("Equilibrio justo", style="color:#888; margin:0; font-size:11px;")
        ),
        p(strong(paste0(format(estimado, big.mark=".", decimal.mark=","), " €")), style="color:#0A0A0A; margin:0; font-size:15px;")
      ),
      div(style="background-color:rgba(198, 40, 40, 0.05); border-left: 3px solid #ef5350; padding:12px; display:flex; justify-content:space-between; align-items:center;",
        div(
          p(strong("Límite Sobreprecio (+5%)"), style="color:#c62828; margin:0; font-size:13px;"),
          p(paste0("-", format(precio_sobreprecio - estimado, big.mark=".", decimal.mark=","), " € Destrucción de valor"), style="color:#d32f2f; margin:0; font-size:11px;")
        ),
        p(strong(paste0(format(precio_sobreprecio, big.mark=".", decimal.mark=","), " €")), style="color:#0A0A0A; margin:0; font-size:15px;")
      )
    )
  })
  
  output$grafico_proyeccion_capital <- renderPlot({
    req(premium_rv$precio_total, premium_rv$mult)
    cagr <- (premium_rv$mult)^(1/16) - 1
    anios <- 2026:2031
    val_base <- premium_rv$precio_total * (1 + cagr)^(0:5)
    val_alcista <- premium_rv$precio_total * (1 + cagr + 0.015)^(0:5)
    tasas_estres <- c(0, -0.04, -0.02, 0.01, 0.02, 0.03)
    val_estres <- premium_rv$precio_total * cumprod(1 + tasas_estres)
    
    df_proj <- data.frame(
      Anio = rep(anios, 3),
      Valor = c(val_base, val_alcista, val_estres),
      Escenario = factor(rep(c("Base (CAGR Histórico)", "Alcista (+1.5% Alpha)", "Estrés de Mercado"), each = 6),
                         levels = c("Alcista (+1.5% Alpha)", "Base (CAGR Histórico)", "Estrés de Mercado"))
    )
    df_labels <- subset(df_proj, Anio == 2031)
    ggplot(df_proj, aes(x = Anio, y = Valor, color = Escenario, group = Escenario)) +
      geom_line(linewidth = 1.2) +
      geom_point(aes(fill = Escenario), shape=21, color="#ffffff", size = 2.5, stroke=1) +
      scale_color_manual(values = c("Alcista (+1.5% Alpha)" = "#4caf50", "Base (CAGR Histórico)" = "#C69B3C", "Estrés de Mercado" = "#ef5350")) +
      scale_fill_manual(values = c("Alcista (+1.5% Alpha)" = "#4caf50", "Base (CAGR Histórico)" = "#C69B3C", "Estrés de Mercado" = "#ef5350")) +
      geom_text(data = df_labels, aes(label = paste0(round(Valor/1000), "k")), hjust = -0.3, size=3.5, family="serif", show.legend = FALSE) +
      scale_x_continuous(breaks = anios, limits = c(2026, 2031.5)) +
      scale_y_continuous(labels = scales::label_number(suffix="k", scale=1e-3)) +
      theme_minimal() +
      theme(text = element_text(family = "serif", color = "#0A0A0A"), axis.text = element_text(color = "#555", size=9), axis.title = element_blank(), panel.grid.major.y = element_line(color = "#eee"), panel.grid.major.x = element_blank(), panel.grid.minor = element_blank())
  }, bg = "transparent")

  output$grafico_genesis <- renderPlot({
    req(premium_rv$precio_total, premium_rv$mult)
    anios <- 2010:2026
    val_final <- premium_rv$precio_total
    val_inicial <- val_final / premium_rv$mult
    cagr <- (premium_rv$mult)^(1/16) - 1
    serie <- val_inicial * (1 + cagr)^(0:16)
    
    df_gen <- data.frame(Anio = anios, Valor = serie)
    ggplot(df_gen, aes(x = Anio, y = Valor)) +
      geom_area(fill = "#C69B3C", alpha = 0.1) +
      geom_line(color = "#C69B3C", linewidth = 1) +
      scale_y_continuous(labels = scales::label_number(suffix="k", scale=1e-3)) +
      theme_minimal() +
      theme(text = element_text(family = "serif", color = "#0A0A0A"), axis.title = element_blank(), panel.grid.minor = element_blank())
  }, bg = "transparent")

  output$radar_entorno <- renderPlot({
    req(coords_click())
    # Extraer variables exactas del micro-barrio clickado
    click <- coords_click()
    punto_utm <- st_transform(st_as_sf(data.frame(lon = click$lng, lat = click$lat), coords = c("lon", "lat"), crs = 4326), 25830)
    vecinos_local <- train_sf[order(as.numeric(st_distance(punto_utm, train_sf)))[1:5], ]
    
    # Calcular percentiles reales usando la Distribución Acumulada Empírica (ECDF) de todo Madrid
    pct_shopping <- round(ecdf(train_sf$shopping[!is.na(train_sf$shopping)])(mean(vecinos_local$shopping, na.rm=TRUE)) * 100)
    pct_historical <- round(ecdf(train_sf$historical[!is.na(train_sf$historical)])(mean(vecinos_local$historical, na.rm=TRUE)) * 100)
    pct_crime <- round((1 - ecdf(train_sf$crime[!is.na(train_sf$crime)])(mean(vecinos_local$crime, na.rm=TRUE))) * 100) # Invertido: 100 es más tranquilo
    
    df_radar <- data.frame(
      label = factor(c("Densidad\nComercial", "Legado\nHistórico", "Tranquilidad\nResidencial"),
                     levels = c("Densidad\nComercial", "Legado\nHistórico", "Tranquilidad\nResidencial")),
      value = c(pct_shopping, pct_historical, pct_crime)
    )
    
    ggplot(df_radar, aes(x = label, y = value)) +
      geom_polygon(aes(group = 1), fill = "#C69B3C", alpha = 0.3, color = "#C69B3C", linewidth=1.5) +
      geom_point(color = "#0A0A0A", size=2) +
      coord_polar() +
      scale_y_continuous(limits = c(0, 120), breaks = c(25, 50, 75, 100)) +
      geom_text(aes(label = paste0(value, " pctl.")), vjust=-1.5, size=4, family="serif", color="#0A0A0A", fontface="bold") +
      theme_minimal() +
      theme(
        text = element_text(family = "serif", size = 11, color="#0A0A0A"), 
        axis.title = element_blank(), 
        axis.text.y = element_blank(),
        axis.ticks = element_blank(),
        panel.grid.major = element_line(color="#e0e0e0", linetype="dashed")
      )
  }, bg = "transparent")

  output$texto_proyeccion <- renderUI({
    req(premium_rv$precio_total, premium_rv$mult)
    cagr <- (premium_rv$mult)^(1/16) - 1
    val_base <- premium_rv$precio_total * (1 + cagr)^(0:5)
    val_alcista <- premium_rv$precio_total * (1 + cagr + 0.015)^(0:5)
    val_estres <- val_base
    val_estres[2] <- val_estres[1] * 0.90
    for(i in 3:6) val_estres[i] <- val_estres[i-1] * 1.02
    ganancia_alcista <- val_alcista[6] - val_base[6]
    perdida_estres <- val_estres[6] - val_base[6]
    
    div(style="display:flex; justify-content:space-between; margin-top:15px;",
      div(style="text-align:center; padding:10px; background:#F4EADE; border:1px solid #D8CDBF; border-radius:4px; flex:1; margin-right:5px;",
          p("ALPHA ALCISTA (5Y)", style="color:#555; font-size:9px; letter-spacing:1px; margin-bottom:5px; font-family:serif;"),
          p(strong(paste0("+", format(ganancia_alcista, big.mark=".", decimal.mark=","), " €")), style="color:#4caf50; font-size:16px; margin:0; font-family:serif;")
      ),
      div(style="text-align:center; padding:10px; background:#F4EADE; border:1px solid #D8CDBF; border-radius:4px; flex:1; margin-left:5px;",
          p("VARIACIÓN ESTRÉS (5Y)", style="color:#555; font-size:9px; letter-spacing:1px; margin-bottom:5px; font-family:serif;"),
          p(strong(paste0(if(perdida_estres>0) "+" else "", format(perdida_estres, big.mark=".", decimal.mark=","), " €")), style="color:#c62828; font-size:16px; margin:0; font-family:serif;")
      )
    )
  })

  output$mapa_instruction <- renderUI({
    state <- map_state()
    if(state == 0) p("Paso 1: Seleccione su Distrito en el mapa de Madrid.", style="text-align:center; font-weight:600; color:#0A0A0A; font-size:15px;")
    else if (state == 1) p(paste("Paso 2: Distrito de", distrito_sel(), ". Haga clic en su Barrio."), style="text-align:center; font-weight:600; color:#388e3c; font-size:15px;")
    else p(paste("Paso 3: Barrio de", barrio_sel(), ". ¡Haga clic para colocar la chincheta!"), style="text-align:center; font-weight:600; color:#d84315; font-size:15px;")
  })

  output$btn_siguiente_mapa <- renderUI({
    if(!is.null(coords_click()) && map_state() == 2) actionButton("to_step2", "Siguiente >", class = "btn-next")
    else actionButton("dummy", "Siguiente >", class = "btn-next", disabled = TRUE)
  })

  output$btn_volver_mapa <- renderUI({
    state <- map_state()
    if(state == 1) actionButton("back_map", "< Volver a Distritos", class="btn-reset")
    else if(state == 2) actionButton("back_map", "< Volver a seleccionar Barrio", class="btn-reset")
    else NULL
  })

  # Navegación del asistente
  observeEvent(input$to_step2, { updateTabsetPanel(session, "wizard", selected = "step2") })
  observeEvent(input$back_step1, { updateTabsetPanel(session, "wizard", selected = "step1") })
  observeEvent(input$to_step3, { updateTabsetPanel(session, "wizard", selected = "step3") })
  observeEvent(input$back_step2, { updateTabsetPanel(session, "wizard", selected = "step2") })
  observeEvent(input$back_step3, { updateTabsetPanel(session, "wizard", selected = "step3") })
  observeEvent(input$restart, {
    map_state(0)
    coords_click(NULL)
    updateTabsetPanel(session, "wizard", selected = "step1")
    leafletProxy("mapa") |> clearMarkers() |> clearShapes() |> setView(lng = -3.703, lat = 40.417, zoom = 11) |>
      addPolygons(data = distritos_sf, layerId = ~NOMBRE, fillColor = "steelblue", fillOpacity = 0.4, weight = 1, color = "#F4EADE", label = ~NOMBRE)
  })
  observeEvent(input$back_map, {
    state <- map_state()
    coords_click(NULL)
    if (state == 1 || state == 0) {
      map_state(0)
      distrito_sel(NULL)
      leafletProxy("mapa") |> clearMarkers() |> clearShapes() |> setView(lng = -3.703, lat = 40.417, zoom = 11) |>
        addPolygons(data = distritos_sf, layerId = ~NOMBRE, fillColor = "steelblue", fillOpacity = 0.4, weight = 1, color = "#F4EADE", label = ~NOMBRE)
    } else if (state == 2) {
      map_state(1)
      barrio_sel(NULL)
      barrios_in_dist <- barrios_sf[barrios_sf$NOMDIS == distrito_sel(), ]
      leafletProxy("mapa") |> clearMarkers() |> clearShapes() |>
        addPolygons(data = barrios_in_dist, layerId = ~NOMBRE, fillColor = "#388e3c", fillOpacity = 0.4, weight = 2, color = "#F4EADE", label = ~NOMBRE)
    }
  })

  output$mapa <- renderLeaflet({
    leaflet() |> addProviderTiles(providers$CartoDB.Positron) |>
      setView(lng = -3.703, lat = 40.417, zoom = 11) |>
      addPolygons(data = distritos_sf, layerId = ~NOMBRE, fillColor = "steelblue", fillOpacity = 0.4, weight = 1, color = "#F4EADE", label = ~NOMBRE)
  })

  observeEvent(input$mapa_shape_click, {
    click <- input$mapa_shape_click
    state <- map_state()
    if (state == 0) {
      distrito_sel(click$id)
      map_state(1)
      dist_geom <- distritos_sf[distritos_sf$NOMBRE == click$id, ]
      barrios_in_dist <- barrios_sf[barrios_sf$NOMDIS == click$id, ]
      bbox <- st_bbox(dist_geom)
      leafletProxy("mapa") |> clearShapes() |> 
        fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]]) |>
        addPolygons(data = barrios_in_dist, layerId = ~NOMBRE, fillColor = "#388e3c", 
                    fillOpacity = 0.4, weight = 2, color = "#F4EADE", label = ~NOMBRE)
    } else if (state == 1) {
      barrio_sel(click$id)
      map_state(2)
      barrio_geom <- barrios_sf[barrios_sf$NOMBRE == click$id, ]
      bbox <- st_bbox(barrio_geom)
      leafletProxy("mapa") |> clearShapes() |> 
        fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]])
    }
  })

  observeEvent(input$mapa_click, {
    req(map_state() == 2)
    click <- input$mapa_click
    punto <- st_as_sf(data.frame(lon = click$lng, lat = click$lat), coords = c("lon", "lat"), crs = 4326)
    barrio_geom <- barrios_sf[barrios_sf$NOMBRE == barrio_sel(), ]
    if (nrow(barrio_geom) > 0) {
      esta_dentro <- suppressWarnings(any(st_intersects(punto, barrio_geom, sparse = FALSE)))
      if (!esta_dentro) {
        showNotification("Fuera de los límites. Seleccione un punto dentro del área delimitada.", type = "warning")
        leafletProxy("mapa") |> clearShapes() |>
          addPolygons(data = barrio_geom, layerId = "frontera_error",
                      fillColor = "#ff0000", fillOpacity = 0.1, 
                      weight = 3, color = "#ff0000", dashArray = "8, 8",
                      label = ~NOMBRE)
        return()
      }
      coords_click(click)
      leafletProxy("mapa") |> clearShapes() |> clearMarkers() |> addMarkers(lng = click$lng, lat = click$lat)
    }
  })

  observeEvent(input$to_step4, {
    req(coords_click(), distrito_sel(), input$built_area)
    
    click <- coords_click()
    punto_utm <- st_transform(st_as_sf(data.frame(lon = click$lng, lat = click$lat), coords = c("lon", "lat"), crs = 4326), 25830)
    distancias <- st_distance(punto_utm, train_sf)
    vecinos <- train_sf[order(as.numeric(distancias))[1:8], ]
    
    f_val <- if(input$floor == 0) "baja" else if(input$floor == 1) "primera" else "intermedia"
    
    nuevo <- tibble(
      built.area = input$built_area, age = input$age, baths = input$baths,
      type.house = factor(input$type_house, levels = lvl("type.house")),
      floor = factor(f_val, levels = lvl("floor")),
      good.cond = factor(input$good_cond, levels = lvl("good.cond")),
      garage = factor(if(!is.null(input$chk_garage) && input$chk_garage) "si" else "no", levels = lvl("garage")), 
      elevator = factor(if(!is.null(input$chk_elevator) && input$chk_elevator) "si" else "no", levels = lvl("elevator")),
      air.cond = factor(if(!is.null(input$chk_aircond) && input$chk_aircond) "si" else "no", levels = lvl("air.cond")), 
      swimming.pool = factor(if(!is.null(input$chk_pool) && input$chk_pool) "si" else "no", levels = lvl("swimming.pool")),
      log_built_area = log(input$built_area), log_age1 = log(input$age + 1),
      RP = mean(vecinos$RP, na.rm=T), crime = mean(vecinos$crime, na.rm=T),
      retired = mean(vecinos$retired, na.rm=T), children = mean(vecinos$children, na.rm=T),
      immigrants = mean(vecinos$immigrants, na.rm=T), shopping = round(mean(vecinos$shopping, na.rm=T)),
      historical = round(mean(vecinos$historical, na.rm=T)),
      Wy = mean(vecinos$log_price, na.rm=T), W_RP = mean(vecinos$RP, na.rm=T),
      W_crime = mean(vecinos$crime, na.rm=T), W_immigrants = mean(vecinos$immigrants, na.rm=T)
    )

    mult <- indices_mercado[indices_mercado$distrito == distrito_sel(), ]$indice_revalorizacion[1]
    if(is.na(mult)) mult <- 1.40
    
    p_rf  <- exp(predict(rf_model, nuevo)$.pred)
    p_xgb <- exp(predict(xgb_model, nuevo)$.pred)
    p_avg <- (p_rf + p_xgb) / 2
    
    precio_total_2026 <- round(p_avg * mult * input$built_area)
    precio_total_2010 <- round(p_avg * input$built_area)
    
    # Desglose
    n_base <- nuevo; n_base$elevator <- factor("no", levels=lvl("elevator")); n_base$garage <- factor("no", levels=lvl("garage")); n_base$good.cond <- factor("a_reformar", levels=lvl("good.cond")); n_base$swimming.pool <- factor("no", levels=lvl("swimming.pool")); n_base$air.cond <- factor("no", levels=lvl("air.cond"))
    p_base_10 <- (exp(predict(rf_model, n_base)$.pred) + exp(predict(xgb_model, n_base)$.pred))/2
    p_base_26 <- round(p_base_10 * mult * input$built_area)
    
    val_asc <- if(input$chk_elevator) round(((exp(predict(rf_model, transform(n_base, elevator=factor("si", levels=lvl("elevator"))))$.pred) + exp(predict(xgb_model, transform(n_base, elevator=factor("si", levels=lvl("elevator"))))$.pred))/2 - p_base_10) * mult * input$built_area) else 0
    val_gar <- if(input$chk_garage) round(((exp(predict(rf_model, transform(n_base, garage=factor("si", levels=lvl("garage"))))$.pred) + exp(predict(xgb_model, transform(n_base, garage=factor("si", levels=lvl("garage"))))$.pred))/2 - p_base_10) * mult * input$built_area) else 0
    val_est <- if(input$good_cond != "a_reformar") round(((exp(predict(rf_model, transform(n_base, good.cond=factor(input$good_cond, levels=lvl("good.cond"))))$.pred) + exp(predict(xgb_model, transform(n_base, good.cond=factor(input$good_cond, levels=lvl("good.cond"))))$.pred))/2 - p_base_10) * mult * input$built_area) else 0
    val_pis <- if(input$chk_pool) round(((exp(predict(rf_model, transform(n_base, swimming.pool=factor("si", levels=lvl("swimming.pool"))))$.pred) + exp(predict(xgb_model, transform(n_base, swimming.pool=factor("si", levels=lvl("swimming.pool"))))$.pred))/2 - p_base_10) * mult * input$built_area) else 0
    val_aire <- if(input$chk_aircond) round(((exp(predict(rf_model, transform(n_base, air.cond=factor("si", levels=lvl("air.cond"))))$.pred) + exp(predict(xgb_model, transform(n_base, air.cond=factor("si", levels=lvl("air.cond"))))$.pred))/2 - p_base_10) * mult * input$built_area) else 0
    
    val_ajuste <- precio_total_2026 - (p_base_26 + val_asc + val_gar + val_est + val_pis + val_aire)

    premium_rv$html_desglose <- div(style="border: 1px solid #D8CDBF; padding:15px; margin-bottom:20px; background:#FFF;",
      p(strong("DESGLOSE TÉCNICO"), style="font-family:serif; color:#C69B3C; font-size:11px; text-transform:uppercase; border-bottom:1px solid #D8CDBF; padding-bottom:5px;"),
      div(style="display:flex; justify-content:space-between; font-size:13px;", span(paste0("Valor Suelo (", input$built_area, " m²)")), span(paste0(format(p_base_26, big.mark="."), " €"))),
      if(val_asc>0) div(style="display:flex; justify-content:space-between; color:#388e3c; font-size:13px;", span("+ Ascensor"), span(paste0("+", format(val_asc, big.mark="."), " €"))) else NULL,
      if(val_gar>0) div(style="display:flex; justify-content:space-between; color:#388e3c; font-size:13px;", span("+ Garaje"), span(paste0("+", format(val_gar, big.mark="."), " €"))) else NULL,
      if(val_pis>0) div(style="display:flex; justify-content:space-between; color:#388e3c; font-size:13px;", span("+ Piscina"), span(paste0("+", format(val_pis, big.mark="."), " €"))) else NULL,
      if(val_aire>0) div(style="display:flex; justify-content:space-between; color:#388e3c; font-size:13px;", span("+ Aire Acond."), span(paste0("+", format(val_aire, big.mark="."), " €"))) else NULL,
      if(val_est>0) div(style="display:flex; justify-content:space-between; color:#388e3c; font-size:13px;", span("+ Estado"), span(paste0("+", format(val_est, big.mark="."), " €"))) else NULL,
      if(val_ajuste!=0) div(style="display:flex; justify-content:space-between; color:#888; font-size:13px;", span("Ajustes espaciales"), span(paste0(format(val_ajuste, big.mark="."), " €"))) else NULL,
      div(style="display:flex; justify-content:space-between; border-top:1px solid #eee; margin-top:10px; font-weight:bold;", span("TOTAL"), span(paste0(format(precio_total_2026, big.mark="."), " €")))
    )
        premium_rv$html_testigos <- div(style="border: 1px solid #D8CDBF; padding:15px; margin-bottom:15px; background:#FFF;",
          p(strong("VIVIENDAS COMPARABLES CERCANAS"), style="font-family:serif; color:#C69B3C; font-size:11px; text-transform:uppercase; border-bottom:1px solid #D8CDBF; padding-bottom:5px;"),
          lapply(1:3, function(i) {
            precio_testigo <- round(exp(vecinos$log_price[i]) * mult * vecinos$built.area[i])
            div(style="display:flex; justify-content:space-between; font-size:12px; margin-bottom:5px;", 
                span(paste0("Vivienda ", i, " (", round(vecinos$built.area[i]), " m² - ", vecinos$good.cond[i], ")")), 
                strong(paste0(format(precio_testigo, big.mark="."), " €")))
          })
        )
    necesita_reforma <- (input$good_cond == "a_reformar")
    if (necesita_reforma) {
      n_ref <- nuevo; n_ref$good.cond <- factor("bueno", levels=lvl("good.cond"))
      if (!is.null(input$chk_aircond) && !input$chk_aircond) n_ref$air.cond <- factor("si", levels=lvl("air.cond"))
      
      p_total_2026_ref <- round((exp(predict(rf_model, n_ref)$.pred) + exp(predict(xgb_model, n_ref)$.pred))/2 * mult * input$built_area)
      delta_reforma <- p_total_2026_ref - precio_total_2026
      coste_estimado <- 800 * input$built_area
      if (!input$chk_aircond) coste_estimado <- coste_estimado + 3500
      roi_neto <- delta_reforma - coste_estimado
      
      roi_pct <- round((roi_neto / coste_estimado) * 100, 1)
      
      premium_rv$html_reforma <- div(style="background-color:#F4EADE; padding:20px; border-top:1px solid #D8CDBF; font-size:13px; color:#0A0A0A;",
        p(strong("OPORTUNIDAD DE INVERSIÓN (HOUSE FLIPPING)"), style="color:#C69B3C; text-transform:uppercase; letter-spacing:1px; margin-bottom:15px; text-align:center;"),
        div(style="display:flex; justify-content:space-between; margin-bottom:5px;", span("Valor actual (A reformar):"), span(paste0(format(precio_total_2026, big.mark="."), " €"))),
        div(style="display:flex; justify-content:space-between; margin-bottom:5px; color:#c62828;", span("Coste Estimado de Obra:"), span(paste0("-", format(coste_estimado, big.mark="."), " €"))),
        div(style="display:flex; justify-content:space-between; margin-bottom:10px; color:#388e3c;", span("Valor proyectado (Reformado):"), span(paste0(format(p_total_2026_ref, big.mark="."), " €"))),
        div(style="display:flex; justify-content:space-between; font-weight:bold; border-top:1px solid #C69B3C; padding-top:10px; font-size:14px;", 
            span("Beneficio Neto Esperado:"), 
            span(style=ifelse(roi_neto>0, "color:#388e3c;", "color:#d32f2f;"), paste0(ifelse(roi_neto>0, "+", ""), format(roi_neto, big.mark="."), " € (", roi_pct, "%)")))
      )
    } else {
      premium_rv$html_reforma <- div(style="padding:20px; text-align:center; background-color:#fdfbf7; border-top:1px solid #e6d5b8;", p("Inmueble en estado óptimo. No requiere evaluación de House Flipping.", style="color:#888; font-style:italic; font-size:13px;"))
    }

    premium_rv$capital_latente <- precio_total_2026 - precio_total_2010
    premium_rv$mult <- mult
    premium_rv$precio_total <- precio_total_2026

    output$resultado_final <- renderUI({
      div(
        div(class="result-price", paste0(format(precio_total_2026, big.mark="."), " €")), 
        div(style="text-align:center; color:#888;", paste0("(", format(round(precio_total_2026/input$built_area), big.mark="."), " € / m²)")), 
        div(style="text-align:center; margin-top:20px;", actionButton("btn_informe_premium", "SOLICITAR INFORME", style="background:#0A0A0A; color:#C69B3C; border:1px solid #C69B3C; width:100%;")), 
        hr()
      )
    })

    output$mapa_resultado <- renderLeaflet({
      vecinos$precio_label <- paste0(format(round(exp(vecinos$log_price) * mult * vecinos$built.area), big.mark="."), " € (", vecinos$good.cond, ")")
      leaflet() |> addProviderTiles(providers$CartoDB.Positron) |> 
        setView(click$lng, click$lat, 16) |> 
        addMarkers(click$lng, click$lat, popup = "Tu Tasación") |> 
        addCircleMarkers(data = st_transform(vecinos, 4326),
                         radius=8, color="#ff7f00", opacity=0.8, fillOpacity=0.6,
                         label = ~precio_label, 
                         popup = ~paste0("<b>", precio_label, "</b><br>", round(built.area), " m² - ", good.cond))
    })
    
    updateTabsetPanel(session, "wizard", selected = "step4")
  })
}

shinyApp(ui, server)
