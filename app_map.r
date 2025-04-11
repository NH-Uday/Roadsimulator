library(duckdb)
library(dplyr)
library(shiny)
library(shinydashboard)
library(DT)
library(DBI)
library(ggplot2)  

# Define BUW colors
buw_colors <- list(
  primary = "#005ca9",
  secondary = "#009ee3",
  accent = "#94c11c",
  background = "#21141241",
  white = "#ffffff"
)

ui <- dashboardPage(
  dashboardHeader(
    title = div(
      style = "padding: 10px 15px; display: flex; align-items: left;",
      img(src = "https://www.grafik.uni-wuppertal.de/fileadmin/grafik/intern/Logos/BUW_Logo-weiss-auf-gruen-RGB.png", height = 30),
      span("Truck Travel Times", style = "align-items: left;15px;padding: 10px 15px; font-weight: 300;")
    ),
    titleWidth = 300
  ),

  dashboardSidebar(
    width = 250,
    tags$style(HTML(paste0(".skin-blue .main-header .logo { 
        background-color: ", buw_colors$accent, "; 
        padding: 0;
      }
      .skin-blue .main-header .navbar { background-color: ", buw_colors$accent, "; }
      .skin-blue .main-sidebar { 
        background-color: #ffffff;
        box-shadow: 0 2px 5px rgba(0,0,0,0.1);
      }
      .skin-blue .main-sidebar .sidebar .sidebar-menu a { color: #444; }
      .skin-blue .main-sidebar .sidebar .sidebar-menu .active a { 
        color: ", buw_colors$accent, ";
        background-color: #f4f8fb;
        border-left: 4px solid ", buw_colors$accent, ";
        font-weight: 600;
      }
      .skin-blue .main-sidebar .sidebar .sidebar-menu a:hover { 
        background-color: #f4f8fb;
        color: ", buw_colors$accent, ";
      }
      .content-wrapper { background-color: #f8f9fa; }
      .box {
        border-radius: 6px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        border-top: none;
      }
      .box-header {
        border-bottom: 1px solid #f0f0f0;
      }
      .form-control {
        border-radius: 4px;
      }
      .btn {
        border-radius: 4px;
        text-transform: uppercase;
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.5px;
      }
      .selectize-input {
        border-radius: 4px;
      }
    "))),
    sidebarMenu(
      id = "sidebarMenu",
      menuItem("Visualizations", tabName = "visualizations", icon = icon("chart-line")),
      menuItem("Explanations", tabName = "explanations", icon = icon("info-circle")),
      menuItem("Data Table", tabName = "data_table", icon = icon("table")),
      menuItem("Acknowledgement", tabName = "acknowledgement", icon = icon("handshake")),
      div(
        style = "position: absolute; bottom: 0; width: 100%; padding: 10px; background: #f4f8fb; \
                 text-align: center; border-top: 1px solid #e8e8e8;",
        img(src = "https://www.grafik.uni-wuppertal.de/fileadmin/grafik/intern/Logos/BUW_Logo-weiss-auf-gruen-RGB.png", height = 30)
      )
    )
  ),

  dashboardBody(
    tags$head(tags$style(HTML(paste0(".box-title {
        font-size: 16px;
        font-weight: 600;
      }
      .nav-tabs-custom {
        box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        border-radius: 6px;
      }
      .nav-tabs-custom > .nav-tabs > li.active {
        border-top-color: ", buw_colors$primary, ";
      }
      .btn-primary {
        background-color: ", buw_colors$primary, ";
        border-color: ", buw_colors$primary, ";
      }
      .btn-info {
        background-color: ", buw_colors$secondary, ";
        border-color: ", buw_colors$secondary, ";
      }
      .btn-success {
        background-color: ", buw_colors$accent, ";
        border-color: ", buw_colors$accent, ";
      }
      .bg-primary { background-color: ", buw_colors$primary, " !important; }
      .bg-info { background-color: ", buw_colors$secondary, " !important; }
      .bg-success { background-color: ", buw_colors$accent, " !important; }
      
      /* Modern card headers */
      .box-header.with-border {
        padding: 15px 20px;
      }
      .box-body {
        padding: 20px;
      }
      
      /* Custom styling for filter sidebar */
      .filter-section {
        margin-bottom: 25px;
      }
      .filter-header {
        font-weight: 600;
        color: ", buw_colors$primary, ";
        margin-bottom: 10px;
        border-bottom: 1px solid #eee;
        padding-bottom: 5px;
      }
    ")))),
    tabItems(
      tabItem(tabName = "visualizations",
        fluidRow(
          column(width = 3,
            div(class = "box",
              div(class = "box-header with-border", h3(class = "box-title", "Filter Options")),
              div(class = "box-body",
                div(class = "filter-section",
                  div(class = "filter-header", "Plot Configuration"),
                  selectInput("plot_type", "Plot Type:",
                    choices = c("Mean Travel Time" = "mean_travel_time",
                                "Coefficient of Variation" = "covariation",
                                "Buffer Time Index" = "buffer_time_index",
                                "Perzentile" = "percentile")),
                  selectInput("plot_style", "Plot Style:",
                    choices = c("Summenh\u00e4ufigkeit (ECDF)" = "ecdf",
                                "Histogram" = "histogram",
                                "Density" = "density"), selected = "ecdf")
                ),
                div(class = "filter-section",
                  div(class = "filter-header", "Network Section"),
                  numericInput("network_section", "Section ID:", value = 99, min = 1, max = 850)
                ),
                div(class = "filter-section",
                  div(class = "filter-header", "Time Filters"),
                  checkboxGroupInput("traffic_times", "Traffic Time Periods:",
                    choices = c("Morning Rush Hour" = "morgendliche Hauptverkehrszeit",
                                "Morning Off-Peak" = "morgendliche Nebenverkehrszeit",
                                "Evening Rush Hour" = "abendliche Hauptverkehrszeit",
                                "Evening Off-Peak" = "abendliche Nebenverkehrszeit"),
                    selected = c("morgendliche Hauptverkehrszeit", "morgendliche Nebenverkehrszeit",
                                 "abendliche Hauptverkehrszeit", "abendliche Nebenverkehrszeit"))
                ),
                div(class = "filter-section",
                  div(class = "filter-header", "Months"),
                  checkboxGroupInput("months", "Select Months:",
                    choices = c("Januar", "Februar", "M\u00e4rz", "April", "Mai", "Juni",
                                "Juli", "August", "September", "Oktober", "November", "Dezember"),
                    selected = c("Januar", "Februar", "M\u00e4rz", "April", "Mai", "Juni",
                                "Juli", "August", "September", "Oktober", "November", "Dezember"))
                ),
                div(class = "filter-section",
                  div(class = "filter-header", "Plot Size"),
                  sliderInput("plot_width", "Width (cm):", min = 10, max = 40, value = 30),
                  sliderInput("plot_height", "Height (cm):", min = 8, max = 30, value = 16)
                ),
                div(style = "text-align: center; margin-top: 20px;",
                    downloadButton("download_plot", "Download Plot", class = "btn-primary", style = "width: 100%;"))
              )
            )
          ),
          column(width = 9,
            div(class = "box",
              div(class = "box-header with-border", h3(class = "box-title", "Travel Time Analysis Plot")),
              div(class = "box-body",
                plotOutput("travel_time_plot", height = "600px"),
                hr(),
                div(class = "well well-sm", style = "margin-top: 20px; background: #f9f9f9; border: 1px solid #eee;",
                  uiOutput("plot_explanation")
                )
              )
            )
          )
        )
      ),

      tabItem(tabName = "explanations",
        div(class = "box",
          div(class = "box-header with-border", h3(class = "box-title", "About this Analysis")),
          div(class = "box-body",
            h3("Travel Time Analysis for German Highway Sections", 
              style = paste0("color: ", buw_colors$primary, "; font-weight: 600;")),
            p("This application visualizes travel time data for trucks on various freeway facilities in Germany. The travel times are derived from Floating Car Data for the year 2019.",
              style = "margin-bottom: 20px;"),
            div(style = "background: #f5f8fb; border-left: 4px solid #005ca9; padding: 15px; margin-bottom: 20px;",
              h4("Key Metrics:", style = "margin-top: 0;"),
              tags$ul(
                tags$li(strong("Mean Travel Time:"), "The average travel time in Minutes"),
                tags$li(strong("Coefficient of Variation:"), "A statistical measure showing the dispersion of travel times."),
                tags$li(strong("Buffer Time Index:"), "How much extra time travelers should plan for reliability."),
                tags$li(strong("Percentiles:"), "To show the skewness and spread of travel times.")
              )
            )
          )
        )
      ),

      tabItem(tabName = "data_table",
        div(class = "box",
          div(class = "box-header with-border", h3(class = "box-title", "Raw Data"),
            p("This table shows the filtered data based on your current selections.",
              style = "margin-top: 5px; color: #666; font-weight: normal;")),
          div(class = "box-body", DTOutput("data_table_output"))
        )
      ),

      tabItem(tabName = "acknowledgement",
        div(class = "box",
          div(class = "box-header with-border", h3(class = "box-title", "Acknowledgements")),
          div(class = "box-body",
            div(style = "display: flex; flex-direction: column; align-items: center; text-align: center; margin-bottom: 40px;",
              img(src = "https://www.uni-wuppertal.de/fileadmin/corporate_design/2018-01-31_Logo_BUW_variabel_RGB.png", height = 100),
              h3("University of Wuppertal", style = "margin-top: 20px; color: #005ca9;"),
              p("Department of Civil Engineering", style = "color: #666;")
            ),
            div(style = "text-align: center; margin-top: 20px; background: #f5f8fb; padding: 20px; border-radius: 6px;",
              h4("This research is funded by mFUND", style = "margin-top: 0;")
            )
          )
        )
      )
    )
  ),

  skin = "blue"
)


# Server anpassen
server <- function(input, output, session) {

  #selected_section <- reactiveVal(99)  # Standardwert
  selected_section <- reactiveVal(NULL)

  observe({
    query <- parseQueryString(session$clientData$url_search)
    netzabschnitt <- query$netzabschnitt
    if (!is.null(netzabschnitt)) {
      # Convert to numeric
      ns_id <- as.numeric(netzabschnitt)
      cat("URL param detected: netzabschnitt =", ns_id, "\n")
      selected_section(ns_id)
      updateNumericInput(session, "network_section", value = ns_id)
    }else if (is.null(selected_section())) {
      cat("⚠️ No netzabschnitt in URL, using default (99)\n")
      selected_section(99)
      updateNumericInput(session, "network_section", value = 99)
    }
  })
  
  network_geodata <- reactive({
    
    conn <- dbConnect(duckdb())
    
    # Spatial data aus Geodatendatei laden
    # Wenn du geojson-Daten hast:
    # sf_data <- sf::st_read("/pfad/zu/deinen/geodaten.geojson")
    dbExecute(conn, "load spatial;")
    # Alternativ aus einer Parquet-Datei:
    #fetching geodata
    sf_data <- dbGetQuery(conn, "SELECT a.*,b.*  FROM read_csv('/home/gut11/shiny_app/data/netze_geom.csv') a
                          left join read_csv('/home/gut11/shiny_app/data/sollgeschwindigkeiten_freier_fluss.csv') b on (a.netzabschnitt=b.netzabschnitts_id
                          ) where avg_velocity is not null;") %>%
      sf::st_as_sf(wkt = "wkt") 
    
    
    dbDisconnect(conn)
    return(sf_data)
  })


  observeEvent(input$network_section, {
    selected_section(input$network_section)
  })
  
  
  output$selected_section_info <- renderText({
  section_id <- req(selected_section())  # waits until it's not NULL
  section_data <- network_geodata() %>% 
    filter(netzabschnitt == section_id)

    
    if (nrow(section_data) == 0) {
      return(paste("Netzabschnitt", section_id, "nicht gefunden."))
    }
    
    paste0("Ausgewählter Netzabschnitt: ", section_id, "\n",
           "Name: ", section_data$name, "\n",
           "35% schnellste Geschwindigkeit: ", round(section_data$velocity_65, 1), " km/h\n")
  })
  
  
  output$map_section_stats <- renderPlot({
    req(data())
    
    df <- data()
    
    if (nrow(df) == 0) {
      return(ggplot() + 
               annotate("text", x = 0.5, y = 0.5, label = "Keine Daten für den ausgewählten Abschnitt") + 
               theme_minimal() +
               theme(panel.grid = element_blank(), 
                     axis.text = element_blank(), 
                     axis.title = element_blank()))
    }
    
    ggplot(df, aes(x = verkehrszeit_agg, y = avg_traveltime, fill = verkehrszeit_agg)) +
      geom_bar(stat = "summary", fun = "mean") +
      labs(
        title = paste("Durchschnittliche Fahrtzeiten für Netzabschnitt", selected_section()),
        x = "Verkehrszeit",
        y = "Durchschnittliche Geschwindigkeit (km/h)"
      ) +
      theme_minimal() +
      theme(legend.position = "none")
  })
  
  data <- reactive({

    #you will fetch the travel time data
    conn <- dbConnect(duckdb())
    dbExecute(conn, "Install icu; LOAD icu; set timezone='Europe/Berlin';")
    traveltimes_df <- dbGetQuery(conn, "
    SELECT *
    FROM read_parquet('/home/gut11/shiny_app/data/*.parquet');
    ")
    
    dbDisconnect(conn)
    
    if (!"wochentag" %in% names(traveltimes_df)) {
      stop("Column 'wochentag' not found in the dataset.")
    }
    
    monat_order <- c("Januar", "Februar", "März", "April", "Mai", "Juni", 
                     "Juli", "August", "September", "Oktober", "November", "Dezember")
    
    #creating df and also filtering for one specific netzabschnitt ->
    traveltimes_df <- traveltimes_df %>%
      mutate(month = format(as.POSIXct(wochentag), "%B")) %>%
      mutate(month = factor(month, levels = monat_order)) %>%
      filter(month %in% input$months) %>%
      filter(netzabschnitt == selected_section()) 
    
    if ("verkehrszeit_agg" %in% names(traveltimes_df)) {
      traveltimes_df <- traveltimes_df %>% 
        filter(verkehrszeit_agg %in% input$traffic_times)
    } else {
      warning("Column 'verkehrszeit_agg' not found in the dataset.")
    }
    
    return(as.data.frame(traveltimes_df))
  })
  
  output$data_table_output <- renderDT({
    req(data())
    datatable(data(), 
              options = list(pageLength = 10, 
                             scrollX = TRUE,
                             autoWidth = TRUE),
              filter = 'top')
  })
  
  plot_explanation <- reactive({
    if (input$plot_type == "mean_travel_time") {
      if (input$plot_style == "ecdf") {
        return(HTML("<strong>Mean Travel Time Analysis (ECDF):</strong> This plot shows the cumulative distribution function of mean truck travel times. It indicates what percentage of observations have travel times below a certain threshold.
                     <br><br>
                     <strong>Interpretation:</strong> Steeper curves indicate less variability in travel times. Curves that are shifted to the right indicate longer travel times. When comparing different traffic periods, separated curves indicate different traffic conditions."))
      } else if (input$plot_style == "histogram") {
        return(HTML("<strong>Mean Travel Time Analysis (Histogram):</strong> This plot shows the frequency distribution of mean truck travel times. Each bar represents the count of observations within a specific range of travel times.
                     <br><br>
                     <strong>Interpretation:</strong> The shape of the histogram reveals the distribution pattern. Multiple peaks may indicate different traffic conditions or route characteristics."))
      } else if (input$plot_style == "density") {
        return(HTML("<strong>Mean Travel Time Analysis (Density):</strong> This plot shows the probability density function of mean truck travel times, providing a smoothed view of the distribution.
                     <br><br>
                     <strong>Interpretation:</strong> Peaks in the density curve represent commonly occurring travel times. The width of the curve indicates the variability of travel times."))
      }
    } else if (input$plot_type == "covariation") {
      if (input$plot_style == "ecdf") {
        return(HTML("<strong>Coefficient of Variation Analysis (ECDF):</strong> This plot shows the cumulative distribution of the coefficient of variation, which is a measure of relative variability (standard deviation divided by the mean).
                     <br><br>
                     <strong>Interpretation:</strong> Higher values indicate less predictable travel times. This is important for logistics planning and reliability assessment. Values above 30% generally indicate significant variability that may impact schedule reliability."))
      } else if (input$plot_style == "histogram") {
        return(HTML("<strong>Coefficient of Variation Analysis (Histogram):</strong> This plot shows the frequency distribution of variation coefficients across observations.
                     <br><br>
                     <strong>Interpretation:</strong> This helps identify how common different levels of travel time variability are in the dataset."))
      } else if (input$plot_style == "density") {
        return(HTML("<strong>Coefficient of Variation Analysis (Density):</strong> This plot shows the smoothed probability density of variation coefficients.
                     <br><br>
                     <strong>Interpretation:</strong> Peaks indicate commonly occurring levels of variability. Comparing curves between traffic periods can reveal differences in travel time predictability."))
      }
    } else if (input$plot_type == "buffer_time_index") {
      if (input$plot_style == "ecdf") {
        return(HTML("<strong>Buffer Time Index Analysis (ECDF):</strong> This plot shows two measures of travel time reliability - one based on mean travel time (dashed line) and one based on median travel time (solid line).
                     <br><br>
                     <strong>Interpretation:</strong> The buffer time index represents the extra time that travelers should add to their average travel time to ensure on-time arrival 95% of the time. Lower values indicate more reliable travel times."))
      } else if (input$plot_style == "histogram") {
        return(HTML("<strong>Buffer Time Index Analysis (Histogram):</strong> This plot shows the frequency distribution of buffer time indices, with separate histograms for mean-based and median-based calculations.
                     <br><br>
                     <strong>Interpretation:</strong> The histograms reveal how common different levels of buffer time are required for reliable travel."))
      } else if (input$plot_style == "density") {
        return(HTML("<strong>Buffer Time Index Analysis (Density):</strong> This plot shows the smoothed probability density of buffer time indices.
                     <br><br>
                     <strong>Interpretation:</strong> The curves reveal the distribution of buffer times needed for reliability. Comparing mean-based and median-based indices can show how outliers affect reliability assessments."))
      }
    } else if (input$plot_type == "percentile") {
      return(HTML("<strong>Percentile Analysis:</strong> This plot shows the distribution of various travel time percentiles (9th, 10th, 15th, 20th, 25th, 50th, 75th, 85th, 95th, and 99th).
                   <br><br>
                   <strong>Interpretation:</strong> Comparing different percentiles helps understand the range and skewness of travel times. The 50th percentile is the median, while higher percentiles represent travel times during more congested conditions."))
    }
  })
  output$travel_time_plot <- renderPlot({
    req(data())
    
    df <- data()
    #section_id <- as.numeric(input$network_section)
    section_id <- req(selected_section())
    
    if (nrow(df) == 0) {
      return(ggplot() + 
               annotate("text", x = 0.5, y = 0.5, label = "No data available for the selected filters") + 
               theme_minimal() +
               theme(panel.grid = element_blank(), 
                     axis.text = element_blank(), 
                     axis.title = element_blank(),
                     plot.margin = margin(5, 5, 5, 5, "cm")))
    }
    
    if (input$plot_type == "mean_travel_time") {
      if (input$plot_style == "ecdf") {
        p <- ggplot(data = df, aes(x = avg_traveltime, color = verkehrszeit_agg)) +
          stat_ecdf() +
          theme_bw() +
          labs(
            title = paste0("Summenhäufigkeitsverteilungen der mittleren Lkw-Fahrtzeiten auf dem Netzabschnitt ", section_id),
            x = "Mittlere Fahrtzeit in Minuten",
            y = "Relativer Anteil",
            color = "Verkehrszeiten"
          )
      } else if (input$plot_style == "histogram") {
        p <- ggplot(data = df, aes(x = avg_traveltime, fill = verkehrszeit_agg)) +
          geom_histogram(position = "dodge", alpha = 0.7, bins = 30) +
          theme_bw() +
          labs(
            title = paste0("Histogramm der mittleren Lkw-Fahrtzeiten auf dem Netzabschnitt ", section_id),
            x = "Mittlere Fahrtzeit in Minuten",
            y = "Häufigkeit",
            fill = "Verkehrszeiten"
          )
      } else if (input$plot_style == "density") {
        p <- ggplot(data = df, aes(x = avg_traveltime, color = verkehrszeit_agg, fill = verkehrszeit_agg)) +
          geom_density(alpha = 0.2) +
          theme_bw() +
          labs(
            title = paste0("Dichteverteilung der mittleren Lkw-Fahrtzeiten auf dem Netzabschnitt ", section_id),
            x = "Mittlere Fahrtzeit in Minuten",
            y = "Dichte",
            color = "Verkehrszeiten",
            fill = "Verkehrszeiten"
          )
      }
    } 
    
    else if (input$plot_type == "covariation") {
      if (input$plot_style == "ecdf") {
        p <- ggplot(data = df, aes(x = covariation, color = verkehrszeit_agg)) +
          stat_ecdf() +
          theme_bw() +
          labs(
            title = paste0("Summenhäufigkeitsverteilungen des Variationskoeffizienten auf dem Netzabschnitt ", section_id),
            x = "Variationskoeffizient in Prozent",
            y = "Relativer Anteil",
            color = "Verkehrszeiten"
          )
      } else if (input$plot_style == "histogram") {
        p <- ggplot(data = df, aes(x = covariation, fill = verkehrszeit_agg)) +
          geom_histogram(position = "dodge", alpha = 0.7, bins = 30) +
          theme_bw() +
          labs(
            title = paste0("Histogramm des Variationskoeffizienten auf dem Netzabschnitt ", section_id),
            x = "Variationskoeffizient in Prozent",
            y = "Häufigkeit",
            fill = "Verkehrszeiten"
          )
      } else if (input$plot_style == "density") {
        p <- ggplot(data = df, aes(x = covariation, color = verkehrszeit_agg, fill = verkehrszeit_agg)) +
          geom_density(alpha = 0.2) +
          theme_bw() +
          labs(
            title = paste0("Dichteverteilung des Variationskoeffizienten auf dem Netzabschnitt ", section_id),
            x = "Variationskoeffizient in Prozent",
            y = "Dichte",
            color = "Verkehrszeiten",
            fill = "Verkehrszeiten"
          )
      }
    } 
    
    
    else if (input$plot_type == "buffer_time_index") {
      if (input$plot_style == "ecdf") {
        p <- ggplot(data = df, aes(color = verkehrszeit_agg)) +
          stat_ecdf(aes(x = buffertime_mean_index, linetype = "Mittlere Fahrtzeit")) +
          stat_ecdf(aes(x = buffertime_median_index, linetype = "Median-Fahrtzeit")) +
          theme_bw() +
          scale_linetype_manual(name = "Bewertung", values = c("Mittlere Fahrtzeit" = "dashed", "Median-Fahrtzeit" = "solid")) +
          labs(
            title = paste0("Summenhäufigkeitsverteilungen Buffer-Time-Index auf dem Netzabschnitt ", section_id),
            x = "Buffer-Time-Index in Prozent",
            y = "Relativer Anteil",
            color = "Verkehrszeiten"
          )
      } else if (input$plot_style == "histogram") {
        
        buffer_long <- df %>%
          tidyr::pivot_longer(
            cols = c(buffertime_mean_index, buffertime_median_index),
            names_to = "buffer_type",
            values_to = "buffer_value"
          ) %>%
          mutate(buffer_type = ifelse(buffer_type == "buffertime_mean_index", 
                                      "Mittlere Fahrtzeit", "Median-Fahrtzeit"))
        
        p <- ggplot(data = buffer_long, aes(x = buffer_value, fill = verkehrszeit_agg)) +
          geom_histogram(position = "dodge", alpha = 0.7, bins = 30) +
          facet_wrap(~buffer_type) +
          theme_bw() +
          labs(
            title = paste0("Histogramm des Buffer-Time-Index auf dem Netzabschnitt ", section_id),
            x = "Buffer-Time-Index in Prozent",
            y = "Häufigkeit",
            fill = "Verkehrszeiten"
          )
      } else if (input$plot_style == "density") {
        p <- ggplot(data = df, aes(color = verkehrszeit_agg, fill = verkehrszeit_agg)) +
          geom_density(aes(x = buffertime_mean_index, linetype = "Mittlere Fahrtzeit"), alpha = 0.1) +
          geom_density(aes(x = buffertime_median_index, linetype = "Median-Fahrtzeit"), alpha = 0.1) +
          theme_bw() +
          scale_linetype_manual(name = "Bewertung", values = c("Mittlere Fahrtzeit" = "dashed", "Median-Fahrtzeit" = "solid")) +
          labs(
            title = paste0("Dichteverteilung des Buffer-Time-Index auf dem Netzabschnitt ", section_id),
            x = "Buffer-Time-Index in Prozent",
            y = "Dichte",
            color = "Verkehrszeiten",
            fill = "Verkehrszeiten"
          )
      }
    } 
    
    
    else if (input$plot_type == "percentile") {
      if (input$plot_style == "ecdf") {
        
        percentile_labels <- c(
          "P10" = "10. Perzentil",
          "P15" = "15. Perzentil", 
          "P20" = "20. Perzentil",
          "P25" = "25. Perzentil", 
          "P50" = "50. Perzentil (Median)",
          "P75" = "75. Perzentil",
          "P85" = "85. Perzentil",
          "P90" = "90. Perzentil",
          "P95" = "95. Perzentil",
          "P99" = "99. Perzentil"
        )
        
        p <- ggplot(data = df) +
          stat_ecdf(aes(x = perc_10_traveltime, color = "P10"), size = 1) +
          stat_ecdf(aes(x = perc_15_traveltime, color = "P15"), size = 1) +
          stat_ecdf(aes(x = perc_20_traveltime, color = "P20"), size = 1) +
          stat_ecdf(aes(x = perc_25_traveltime, color = "P25"), size = 1) +
          stat_ecdf(aes(x = perc_50_traveltime, color = "P50"), size = 1) +
          stat_ecdf(aes(x = perc_75_traveltime, color = "P75"), size = 1) +
          stat_ecdf(aes(x = perc_85_traveltime, color = "P85"), size = 1) +
          stat_ecdf(aes(x = perc_9_traveltime, color = "P90"), size = 1) +
          stat_ecdf(aes(x = perc_95_traveltime, color = "P95"), size = 1) +
          stat_ecdf(aes(x = perc_99_traveltime, color = "P99"), size = 1) +
          scale_color_manual(name = "Perzentil", 
                             values = c("P10" = "skyblue", "P15" = "royalblue", "P20" = "blue",
                                        "P25" = "darkblue", "P50" = "green", "P75" = "yellow",
                                        "P85" = "orange", "P90" = "darkorange", "P95" = "red", "P99" = "darkred"),
                             labels = percentile_labels) +
          facet_wrap(~verkehrszeit_agg) +
          theme_bw() +
          labs(
            title = paste0("Summenhäufigkeitsverteilungen der Perzentile auf dem Netzabschnitt ", section_id),
            x = "Fahrtzeit in Minuten",
            y = "Relativer Anteil"
          )
      } else if (input$plot_style == "histogram" || input$plot_style == "density") {
        
        percentiles_long <- df %>%
          tidyr::pivot_longer(
            cols = c(perc_10_traveltime, perc_15_traveltime, perc_20_traveltime, 
                     perc_25_traveltime, perc_50_traveltime, perc_75_traveltime, 
                     perc_85_traveltime, perc_9_traveltime, perc_95_traveltime, perc_99_traveltime),
            names_to = "percentile",
            values_to = "travel_time"
          ) %>%
          mutate(percentile = case_when(
            percentile == "perc_10_traveltime" ~ "10. Perzentil",
            percentile == "perc_15_traveltime" ~ "15. Perzentil",
            percentile == "perc_20_traveltime" ~ "20. Perzentil",
            percentile == "perc_25_traveltime" ~ "25. Perzentil",
            percentile == "perc_50_traveltime" ~ "50. Perzentil (Median)",
            percentile == "perc_75_traveltime" ~ "75. Perzentil",
            percentile == "perc_85_traveltime" ~ "85. Perzentil",
            percentile == "perc_9_traveltime" ~ "90. Perzentil",
            percentile == "perc_95_traveltime" ~ "95. Perzentil",
            percentile == "perc_99_traveltime" ~ "99. Perzentil",
            TRUE ~ as.character(percentile)
          ))
        
        if (input$plot_style == "histogram") {
          p <- ggplot(data = percentiles_long, aes(x = travel_time, fill = percentile)) +
            geom_histogram(position = "dodge", alpha = 0.7, bins = 20) +
            facet_wrap(~verkehrszeit_agg) +
            theme_bw() +
            labs(
              title = paste0("Histogramm der Perzentil-Fahrtzeiten auf dem Netzabschnitt ", section_id),
              x = "Fahrtzeit in Minuten",
              y = "Häufigkeit",
              fill = "Perzentil"
            ) +
            theme(legend.position = "bottom")
        } else {
          p <- ggplot(data = percentiles_long, aes(x = travel_time, color = percentile, fill = percentile)) +
            geom_density(alpha = 0.1) +
            facet_wrap(~verkehrszeit_agg) +
            theme_bw() +
            labs(
              title = paste0("Dichteverteilung der Perzentil-Fahrtzeiten auf dem Netzabschnitt ", section_id),
              x = "Fahrtzeit in Minuten",
              y = "Dichte",
              color = "Perzentil",
              fill = "Perzentil"
            ) +
            theme(legend.position = "bottom")
        }
      }
    }
    
    p + theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 12)
    )
  })
  
  
  output$plot_explanation <- renderUI({
    req(plot_explanation())
    div(
      h4("Explanation:"),
      plot_explanation()
    )
  })

  output$download_plot <- downloadHandler(
    filename = function() {
      paste0("network_", selected_section(), "_", input$plot_type, "_", 
             input$plot_style, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".png")
    },
    content = function(file) {
      req(data())
      
      
      p <- output$travel_time_plot()
      
      
      if (!input$plot_type == "percentile") {
        p <- p + facet_wrap(~month)
      }
      
      ggsave(
        file = file,
        plot = p,
        scale = 1,
        width = input$plot_width,
        height = input$plot_height,
        units = "cm",
        dpi = 300,
        limitsize = TRUE
      )
    }
  )
}

shinyApp(ui = ui, server = server)