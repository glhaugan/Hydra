#####################################################################
####      Beheading a Hydra: Kingpin Extradition, Homicides,     ####  
####  Education Outcomes, and the End of Medellin's Pax Mafiosa  ####       
####                  Created by: Greg Haugan                    ####
#####################################################################

###Load packages
packages <- c("tidyverse" , "foreign" , "sf" , "mapview", "leaflet.extras2" , 
              "fixest", "lmtest" , "lwgeom", "htmlwidgets" , "ggplot2")
lapply(packages, require, character.only = TRUE)
rm(list=ls())

### Read in Shapefile for Medellin's comunas
comunas <- st_read(
  "data/Comunas/comunasmedellin.shp")
# Find and fix invalid geometries
st_is_valid(comunas) 
# Show rows with invalid geometries
comunas[!st_is_valid(comunas), ]
# Make geometries valid
comunas <- st_make_valid(comunas)
# Double-check they're fixed
all(st_is_valid(comunas))

### Read in coordinates file for all crimes and keep only homicides. 
#Drop obs missing coordinates.
homicides <- read.csv(
    "data/Medellin_crimes.csv") %>%
    subset(delito =="Homicidio Comun" & !is.na(x) & x != 0) 
#Convert to sf object and set CRS
homicides <- st_as_sf(homicides, coords = c("x","y")) %>%
  st_set_crs(st_crs(comunas))

### Read in file for schools
schools <- read.csv(
  "data/Schools.csv")
schools <- st_as_sf(schools, coords = c("x","y")) %>%
  st_set_crs(st_crs(comunas))
#Draw 250 meter buffer around schools
schools_250m <- schools %>%
  select(DANE_sede, geometry) %>%
  distinct(DANE_sede, .keep_all = TRUE) %>%
  st_buffer(dist = 250) 

# Spatial join: match homicides within each school's buffer
homicides_near_schools <- st_join(homicides, schools_250m, left = FALSE)

# Count homicides by school and year
homicide_counts <- as.data.frame(homicides_near_schools) %>%
  group_by(DANE_sede, year) %>%
  summarise(homicide_count = n(), .groups = "drop")

schools_with_homicides <- schools %>%
  left_join(homicide_counts, by = c("DANE_sede" = "DANE_sede", "YEAR" = "year")) 
schools_with_homicides$homicide_count[is.na(schools_with_homicides$homicide_count)] <- 0


#And let's check that it worked - click on any school and confirm the homicide count
schools_for_map <- schools_with_homicides %>%
    select(DANE_sede , YEAR , homicide_count) %>% 
    subset(YEAR %in% c(2007,2010)) %>%
  pivot_wider(
    names_from = YEAR,
    values_from = homicide_count,
    names_prefix = "homicides_"
    )

map2010 <- mapview(subset(comunas , NUMERO_COM %in% c(1, 3, 5, 6, 8, 13)), 
          col.regions = "darkgrey" , layer.name = "Berna-Controlled Comunas") + 
  mapview(subset(comunas , NUMERO_COM %in% c(2, 4, 7, 9, 10, 11 , 12 , 14 , 15 , 16)), 
          col.regions = "lightgrey" , layer.name = "Non-Controlled Comunas") + 
    mapview(subset(homicides , year == 2010), col.regions = "blue" , 
            layer.name = "Homicides - 2010") + 
    mapview(select(schools_250m, geometry), col.regions = "yellow" , 
            layer.name = "250m Buffer") +
    mapview(schools_for_map , col.regions = "red", 
            layer.name = "Schools")

map2007 <- mapview(subset(comunas , NUMERO_COM %in% c(1, 3, 5, 6, 8, 13)), 
          col.regions = "darkgrey" , layer.name = "Berna-Controlled Comunas" , 
          legend = FALSE) + 
  mapview(subset(comunas , NUMERO_COM %in% c(2, 4, 7, 9, 10, 11 , 12 , 14 , 15 , 16) ), 
          col.regions = "lightgrey" , layer.name = "Non-Controlled Comunas" , 
          legend = FALSE) +
  mapview(subset(homicides , year == 2007), col.regions = "blue" , 
          layer.name = "Homicides - 2007") + 
  mapview(select(schools_250m, geometry), col.regions = "yellow" , 
          layer.name = "250m Buffer" , legend = FALSE) +
  mapview(schools_for_map , col.regions = "red", 
          layer.name = "Schools" , legend = FALSE)

#Plot 2007 and 2010 back-to-back
map <- map2007 | map2010
leaflet_map <- map@map
saveWidget(leaflet_map, "output/MedellinMap.html")


### Trendlines for monthly homicides in Berna-controlled and non-controlled comunas
#Get comuna for each homicide and define as berna-controlled or not
homicides <- st_join(homicides, comunas["NUMERO_COM"])
homicides$berna_comuna <- as.factor(
  ifelse(homicides$NUMERO_COM %in% c(1, 3, 5, 6, 8, 13), "Berna", "Non"))

#monthly averages for berna and non-berna comunas
homicides_monthly <- homicides %>%
  group_by(berna_comuna , NUMERO_COM, year , mes_num) %>%
  summarise(
    homicides = n()
  ) %>%
  group_by(berna_comuna, year , mes_num) %>%
  summarise(
    homicides = mean(homicides, na.rm = TRUE),
  ) %>%
  arrange(berna_comuna, year , mes_num)

#index the months
homicides_monthly <- homicides_monthly %>%
  group_by(berna_comuna) %>%
  mutate(period = row_number())

#wide format
homicides_monthly <- homicides_monthly %>%
  pivot_wider(names_from = berna_comuna, values_from = c(homicides))

#make plot
trendline <- ggplot(homicides_monthly, aes(x = period)) +
  geom_smooth(aes(y = Non, color = "Non-Berna Comunas"), method = "loess", formula = y ~ poly(x, 2) , span = 0.75, se = FALSE) +
  geom_smooth(aes(y = Berna, color = "Berna-Controlled Comunas"), method = "loess", formula = y ~ poly(x, 2) , span = 0.75, se = FALSE, linetype = "dashed") +
  scale_x_continuous(breaks = c(1, 25, 49, 73, 97),
                     labels = c("2004", "2006", "2008", "2010", "2012")) +
  labs(
    x = "Year",
    y = "Homicides per Comuna",
    title = "Panel A: Homicides in Berna-Controlled and Non-Berna Comunas (Monthly)",
    caption = "Note: Trend lines use a local polynomial smoothing function."
  ) +
  theme_minimal() +
  scale_color_manual(values = c("black", "grey")) +
  theme(
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.5),
    legend.title = element_blank() ,
    legend.position = "bottom"
  ) +
  annotate("text", x = 55, y = 3, label = "Extradition to USA\nMay 2008", color = "black", size = 3, angle = 0, hjust = 0) +
  geom_vline(xintercept = 53, linetype = "dashed", color = "black")
ggsave("output/plot.png", plot = trendline, width = 12, height = 6, units = "in" , bg = "white")


### Some prep so we can fit a regression model

#Get comuna for each school
schools_with_homicides <- st_join(schools_with_homicides, comunas["NUMERO_COM"])

# Ensure the variables are factors
schools_with_homicides$berna_comuna <- as.factor(
    ifelse(schools_with_homicides$NUMERO_COM %in% c(1, 3, 5, 6, 8, 13), 1, 0))

schools_with_homicides$DANE_sede <- as.factor(schools_with_homicides$DANE_sede)

schools_with_homicides <- schools_with_homicides %>%
  mutate(berna_period = factor(case_when(
    YEAR <= 2008 ~ "Pre-extradition",
    YEAR >= 2009 & YEAR <= 2012 ~ "Internecine war",
    YEAR >= 2013 ~ "Post"
  ), levels = c("Pre-extradition", "Internecine war", "Post")))
schools_with_homicides$YEAR <- as.factor(schools_with_homicides$YEAR)

#Log math scores
schools_with_homicides$log_math <- log(schools_with_homicides$MATEMATICAS_PUNT)


### Run the two-way fixed effects model w/ comuna FE for effect on homicides
model1 <- feols(homicide_count ~ berna_comuna * berna_period | NUMERO_COM, 
               data = schools_with_homicides, 
               cluster = ~NUMERO_COM)

# Summary with clustered standard errors
summary1 <- summary(model1, cluster = "NUMERO_COM")

### Run the two-way fixed effects model w/ comuna FE for effect on test scores
model2 <- feols(log_math ~ berna_comuna * berna_period | NUMERO_COM, 
                data = schools_with_homicides, 
                cluster = ~NUMERO_COM)

# Summary with clustered standard errors
summary2 <- summary(model2, cluster = "NUMERO_COM")
