############################################################
# Household Catastrophic Health Expenditure Analysis
#
# Purpose:
# This script constructs a household-level dataset from survey
# data, performs data cleaning and variable construction,
# estimates survey-weighted logistic regression models, and
# exports analytical outputs.
#
# Workflow:
# 1. Import household survey data
# 2. Merge household-level files
# 3. Clean variables and construct indicators
# 4. Define catastrophic health expenditure
# 5. Estimate survey-weighted logistic regressions
# 6. Export tables
#
# Author: Redacted
############################################################


############################################################
# 1. Load Packages
############################################################

library(RODBC)
library(dplyr)
library(readxl)
library(openxlsx)
library(modelsummary)
library(labelled)
library(survey)
library(ggplot2)

# Reproducibility seed
set.seed(1234)


############################################################
# 1.1 Create Output Directories
############################################################

# Create reproducible output folders used by exported tables
# and figures.

dir.create(
  "outputs/tables",
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  "outputs/figures",
  recursive = TRUE,
  showWarnings = FALSE
)



############################################################
# 2. Import Survey Data
############################################################

# The original dataset is stored in Microsoft Access format.
# This section imports available household survey tables.

database_path <- "data/raw/database.mdb"

channel <- RODBC::odbcConnectAccess2007(database_path)


# Identify available tables

survey_tables <- subset(
  sqlTables(channel),
  TABLE_TYPE == "TABLE",
  TABLE_NAME
)[[1]]


# Import tables into R environment

for (table_name in survey_tables) {
  
  assign(
    table_name,
    sqlFetch(channel, table_name)
  )
}


############################################################
# 3. Save and Reload Intermediate Data
############################################################

# Save relevant survey components

saveRDS(
  U93P3S06,
  "U93P3S06.rds"
)

saveRDS(
  R93P3S06,
  "R93P3S06.rds"
)


# Reload data

U93P3S06 <- readRDS("U93P3S06.rds")

R93P3S06 <- readRDS("R93P3S06.rds")


############################################################
# 4. Construct Household Health Expenditure Variable
############################################################

# Aggregate health expenditure components at household level

R93P3S06 <- R93P3S06 |>
  
  group_by(Address) |>
  
  mutate(
    health_expenditure = sum(
      DYCOL03,
      na.rm = TRUE
    )
  ) |>
  
  arrange(
    Address,
    health_expenditure
  ) |>
  
  filter(
    row_number() == n()
  ) |>
  
  mutate(
    annual_health_expenditure =
      health_expenditure * 12
  )


U93P3S06 <- U93P3S06 |>
  
  group_by(Address) |>
  
  mutate(
    health_expenditure = sum(
      DYCOL03,
      na.rm = TRUE
    )
  ) |>
  
  arrange(
    Address,
    health_expenditure
  ) |>
  
  filter(
    row_number() == n()
  ) |>
  
  mutate(
    annual_health_expenditure =
      health_expenditure * 12
  )
############################################################
# 5. Import External Household Files
############################################################

# Import household-level survey files containing demographic
# and expenditure information.

R93 <- read_excel("R93.xls")
U93 <- read_excel("U93.xls")


# Standardize household identifier name

R93 <- R93 |>
  rename(
    Address = ADDRESS
  )

U93 <- U93 |>
  rename(
    Address = ADDRESS
  )


############################################################
# 6. Merge Household Information
############################################################

# Merge household characteristics with health expenditure data

merge_rural <- merge(
  R93,
  R93P3S06,
  by = "Address"
)


merge_urban <- merge(
  U93,
  U93P3S06,
  by = "Address"
)


# Combine urban and rural households

health_data <- rbind(
  merge_rural,
  merge_urban
)


############################################################
# 7. Rename Variables
############################################################

# Rename original survey variables into meaningful names

health_data <- health_data |>
  
  rename(
    gender = A01,
    literacy = A03,
    age = A02,
    household_size = C01,
    total_expenditure = GHazineh,
    food_expenditure = VKhorak,
    income_rank = C11
  )


############################################################
# 8. Create Variable Labels
############################################################

# Add descriptive labels for easier interpretation

var_label(health_data) <- list(
  
  household_size =
    "Household size",
  
  gender =
    "Gender of household head",
  
  age =
    "Age of household head",
  
  literacy =
    "Literacy status of household head"
)


############################################################
# 9. Construct Geographic Variables
############################################################

# Household address codes contain geographic information.
# Extract residence type and regional identifiers.

health_data <- health_data |>
  
  mutate(
    residence_type = substr(Address,1,1),
    province = substr(Address,2,3),
    county = substr(Address,4,5)
  )


# Convert residence type into readable categories

health_data$residence_type <- factor(
  health_data$residence_type,
  levels = c(1,2),
  labels = c(
    "Urban",
    "Rural"
  )
)


############################################################
# 10. Convert Categorical Variables
############################################################

# Gender

health_data$gender <- factor(
  health_data$gender,
  levels = c(1,2),
  labels = c(
    "Male",
    "Female"
  )
)


# Literacy

health_data$literacy <- factor(
  health_data$literacy,
  levels = c(1,2),
  labels = c(
    "Literate",
    "Illiterate"
  )
)


############################################################
# 11. Additional Cleaning
############################################################

# Survey year

health_data$year <- 2014


# Convert numerical variables

health_data <- health_data |>
  
  mutate_at(
    c(
      "food_expenditure",
      "total_expenditure",
      "household_size",
      "age",
      "weight"
    ),
    as.numeric
  )


############################################################
# 12. Construct Basic Expenditure Indicators
############################################################

health_data <- health_data |>
  
  mutate(
    
    # Share of household expenditure devoted to food
    food_share =
      food_expenditure / total_expenditure
  )


############################################################
# 13. Create Final Analytical Dataset
############################################################

final_health_data <- health_data |>
  
  select(
    Address,
    year,
    residence_type,
    province,
    county,
    household_size,
    age,
    gender,
    literacy,
    total_expenditure,
    food_expenditure,
    food_share,
    income_rank,
    weight,
    DYCOL01,
    DYCOL02,
    annual_health_expenditure
  )
############################################################
# Methodological Framework
############################################################

# This analysis follows the catastrophic health expenditure
# framework developed by Xu et al. (2003).
#
# Capacity to pay is defined as household expenditure remaining
# after subsistence expenditure.
#
# Subsistence expenditure is estimated using households whose
# food expenditure share falls between the 45th and 55th
# percentiles of the food-share distribution.
#
# Household-size adjustment follows the equivalence scale:
#
# equivalence_size = household_size^0.56
#
# Catastrophic health expenditure is defined as:
#
# out-of-pocket health expenditure /
# capacity to pay >= 40%
#
############################################################

############################################################
# 14. Construct Household Equivalence Scale
############################################################

# Adjust household consumption needs according to household size.
# The exponent follows the equivalence-scale approach used in
# catastrophic health expenditure research.

final_health_data <- final_health_data |>
  
  mutate(
    
    equivalence_size =
      household_size ^ 0.56
    
  )


############################################################
# 15. Calculate Equivalent Food Expenditure
############################################################

# Convert household food expenditure into equivalent
# per-consumption-unit expenditure.

final_health_data <- final_health_data |>
  
  mutate(
    
    equivalent_food_expenditure =
      food_expenditure / equivalence_size
    
  )


############################################################
# 16. Calculate Food Expenditure Share
############################################################

# Food expenditure share is used to identify the reference
# group for subsistence expenditure estimation.

final_health_data <- final_health_data |>
  
  mutate(
    
    food_expenditure_share =
      food_expenditure / total_expenditure
    
  )


############################################################
# 17. Create Food Share Percentiles
############################################################

# Rank households according to food expenditure share.

final_health_data <- final_health_data |>
  
  mutate(
    
    food_share_percentile =
      percent_rank(food_expenditure_share)
    
  )


############################################################
# 18. Estimate Subsistence Expenditure
############################################################

# Estimate the subsistence expenditure level using households
# around the median food-share group.

final_health_data <- final_health_data |>
  
  group_by(year) |>
  
  mutate(
    
    subsistence_expenditure =
      
      weighted.mean(
        
        food_expenditure[
          food_share_percentile >= 0.45 &
            food_share_percentile <= 0.55
        ],
        
        weight[
          food_share_percentile >= 0.45 &
            food_share_percentile <= 0.55
        ],
        
        na.rm = TRUE
        
      )
    
  ) |>
  
  ungroup()


############################################################
# 19. Calculate Household-Specific Subsistence Need
############################################################

# Adjust subsistence expenditure according to household size.

final_health_data <- final_health_data |>
  
  mutate(
    
    adjusted_subsistence_expenditure =
      subsistence_expenditure *
      equivalence_size
    
  )


############################################################
# 20. Calculate Capacity To Pay
############################################################

# Capacity to pay is expenditure remaining after basic
# subsistence needs.

final_health_data <- final_health_data |>
  
  mutate(
    
    capacity_to_pay =
      
      if_else(
        
        adjusted_subsistence_expenditure >
          food_expenditure,
        
        total_expenditure -
          food_expenditure,
        
        total_expenditure -
          adjusted_subsistence_expenditure
        
      )
    
  )


############################################################
# 21. Identify Poor Households
############################################################

# Households whose total expenditure is below subsistence
# expenditure are classified separately.

final_health_data <- final_health_data |>
  
  mutate(
    
    poor_household =
      
      if_else(
        
        total_expenditure <
          adjusted_subsistence_expenditure,
        
        1,
        0
        
      )
    
  )


############################################################
# 22. Construct Catastrophic Health Expenditure Indicator
############################################################

# Main outcome variable:
# Catastrophic health expenditure occurs when out-of-pocket
# health spending exceeds 40% of capacity to pay.

final_health_data <- final_health_data |>
  
  mutate(
    
    health_expenditure_ratio =
      annual_health_expenditure /
      capacity_to_pay,
    
    
    catastrophic_health_expenditure =
      
      if_else(
        
        health_expenditure_ratio >= 0.40,
        
        1,
        0
        
      )
    
  )
############################################################
# 23. Descriptive Statistics
############################################################

# Generate descriptive statistics for the analytical dataset.

datasummary_skim(
  final_health_data
)


# Export descriptive statistics

datasummary_skim(
  final_health_data,
  output = "outputs/tables/summary_statistics.xlsx"
)



############################################################
# 24. Define Survey Design
############################################################

# Apply household survey weights.

survey_design <- svydesign(
  
  ids = ~1,
  
  weights = ~weight,
  
  data = final_health_data
  
)



############################################################
# 25. Main Logistic Regression Model
############################################################

# Estimate determinants of catastrophic health expenditure.
#
# Dependent variable:
# catastrophic_health_expenditure
#
# Explanatory variables:
# socioeconomic and demographic household characteristics


model_main <- svyglm(
  
  catastrophic_health_expenditure ~
    income_rank +
    residence_type +
    household_size +
    gender +
    age +
    literacy,

  design = survey_design,
  
  family = binomial(link = "logit")
  
)



############################################################
# 26. Regression Results
############################################################

# Display regression output

summary(model_main)



# Convert coefficients to odds ratios

odds_ratios_main <- exp(
  coef(model_main)
)


odds_ratios_main



############################################################
# 27. Export Main Regression Table
############################################################

modelsummary(
  
  list(
    "Survey Weighted Logistic Regression" =
      model_main
  ),
  
  exponentiate = TRUE,
  
  statistic = "std.error",
  
  stars = TRUE,
  
  title =
    "Determinants of Catastrophic Health Expenditure",
  
  output =
    "outputs/tables/regression_results.docx"
  
)



############################################################
# 28. Robustness Analysis: Urban Households
############################################################

# Estimate model for urban households only.

urban_design <- subset(
  
  survey_design,
  
  residence_type == "Urban"
  
)


model_urban <- svyglm(
  
  catastrophic_health_expenditure ~
    income_rank +
    household_size,
  
  design = urban_design,
  
  family = binomial(link = "logit")
  
)


summary(model_urban)



############################################################
# 29. Robustness Analysis: Large Households
############################################################

# Estimate model among larger households.

large_household_design <- subset(
  
  survey_design,
  
  household_size > 6
  
)


model_large_households <- svyglm(
  
  catastrophic_health_expenditure ~
    income_rank +
    residence_type +
    household_size +
    age,
  
  design = large_household_design,
  
  family = binomial(link = "logit")
  
)


summary(model_large_households)



############################################################
# 30. Export Multiple Models
############################################################

modelsummary(
  
  list(
    
    "Main Model" =
      model_main,
    
    "Urban Households" =
      model_urban,
    
    "Large Households" =
      model_large_households
    
  ),
  
  exponentiate = TRUE,
  
  statistic = "std.error",
  
  stars = TRUE,
  
  title =
    "Logistic Regression Results",
  
  output =
    "outputs/tables/model_comparison.docx"
  
)


############################################################
# Threshold Sensitivity Preparation
############################################################

# Alternative catastrophic expenditure definitions.
#
# The baseline threshold is 40% of capacity to pay.
# Additional thresholds are estimated to evaluate whether
# results are sensitive to this methodological choice.

final_health_data <- final_health_data |>
  mutate(
    cata_30 = if_else(
      health_expenditure_ratio >= 0.30,
      1,
      0
    ),

    cata_50 = if_else(
      health_expenditure_ratio >= 0.50,
      1,
      0
    )
  )


############################################################
# 31. Final Research Extensions
############################################################

# Income quintile analysis

final_health_data <- final_health_data |>
  mutate(
    income_quintile = ntile(income_rank, 5)
  )

survey_design <- svydesign(
  ids = ~1,
  weights = ~weight,
  data = final_health_data
)


income_quintile_summary <- svyby(
  ~catastrophic_health_expenditure,
  ~income_quintile,
  survey_design,
  svymean,
  na.rm = TRUE
)


write.csv(
  income_quintile_summary,
  "outputs/tables/CHE_by_income_quintile.csv",
  row.names = FALSE
)


income_plot <- ggplot(
  income_quintile_summary,
  aes(
    x = income_quintile,
    y = catastrophic_health_expenditure
  )
) +
  geom_line() +
  geom_point() +
  labs(
    title = "Catastrophic Health Expenditure by Income Quintile",
    x = "Income Quintile",
    y = "Weighted Prevalence"
  )


ggsave(
  "outputs/figures/Figure1_CHE_income_quintile.png",
  income_plot,
  width = 7,
  height = 5
)


# Province fixed effects

model_province <- svyglm(
  catastrophic_health_expenditure ~
    income_rank +
    residence_type +
    household_size +
    gender +
    age +
    literacy +
    factor(province),
  design = survey_design,
  family = binomial(link="logit")
)


# Income and rural interaction

model_interaction <- svyglm(
  catastrophic_health_expenditure ~
    income_rank * residence_type +
    household_size +
    gender +
    age +
    literacy,
  design = survey_design,
  family = binomial(link="logit")
)


# Threshold robustness

model_CHE30 <- svyglm(
  cata_30 ~
    income_rank +
    residence_type +
    household_size +
    gender +
    age +
    literacy,
  design = survey_design,
  family = binomial(link="logit")
)


model_CHE50 <- svyglm(
  cata_50 ~
    income_rank +
    residence_type +
    household_size +
    gender +
    age +
    literacy,
  design = survey_design,
  family = binomial(link="logit")
)


# Final regression table

modelsummary(
  list(
    "Baseline" = model_main,
    "Province FE" = model_province,
    "Income x Rural" = model_interaction
  ),
  exponentiate = TRUE,
  statistic = "std.error",
  stars = TRUE,
  output = "outputs/tables/CHE_final_regression_table.docx"
)


modelsummary(
  list(
    "CHE 30%" = model_CHE30,
    "CHE 40%" = model_main,
    "CHE 50%" = model_CHE50
  ),
  exponentiate = TRUE,
  statistic = "std.error",
  stars = TRUE,
  output = "outputs/tables/CHE_threshold_robustness.docx"
)


############################################################
# Main Model Confidence Intervals
############################################################

# Export confidence intervals for the main survey-weighted
# logistic regression model.

main_model_confidence_intervals <- confint(model_main)

main_model_confidence_intervals


############################################################
# FINAL CLEAN VALIDATION
############################################################

# Confirm final analytical dataset
dim(final_health_data)

# Missing values summary
final_missing_summary <- data.frame(
  variable = names(final_health_data),
  missing = colSums(is.na(final_health_data))
)

final_missing_summary

# Session information for reproducibility
sessionInfo()

############################################################
# END OF ANALYSIS
############################################################
