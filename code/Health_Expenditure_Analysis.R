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

library(dplyr)
library(readxl)
library(writexl)
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

dir.create(
  "outputs/diagnostics",
  recursive = TRUE,
  showWarnings = FALSE
)



############################################################
# 2. Import Survey Data
############################################################

# The original household expenditure components are supplied
# as committed RDS files. Using these files directly avoids a
# platform-specific Microsoft Access / ODBC dependency.

R93P3S06 <- readRDS("data/raw/R93P3S06.rds")
U93P3S06 <- readRDS("data/raw/U93P3S06.rds")

# Standardize household identifiers across Excel and RDS sources.
# Numeric IDs are formatted without scientific notation or a trailing
# decimal suffix; character IDs are trimmed but otherwise preserved.
normalize_household_id <- function(x) {
  if (is.numeric(x)) {
    out <- format(
      x,
      scientific = FALSE,
      trim = TRUE,
      digits = 22
    )
    out <- sub("\\.0+$", "", out)
  } else {
    out <- trimws(as.character(x))
  }
  out[is.na(x)] <- NA_character_
  out
}


############################################################
# 3. Prepare Imported Data
############################################################

# The source RDS files are read directly from data/raw/.
# No intermediate copies are written to the repository root.


############################################################
# 4. Construct Household Health Expenditure Variable
############################################################

# Aggregate the monthly health-expenditure records to one row per
# household. Only provision-method code 1 (purchased) enters the OOP
# numerator. Codes 2-8 are non-monetary acquisition methods in the
# independent HEIS processing script (93.R). The all-method total is
# retained separately for audit purposes. Households with no medical-table
# records receive zero recorded expenditure in this table.
#
# IMPORTANT: this creates nominal annual OOP by multiplying the monthly
# Table 6 amount by 12. Item-specific, interview-month CPI deflation is not
# yet implemented because the required CPI and Global-code source files
# are not present in this repository.

aggregate_health_expenditure <- function(data) {
  data <- data |>
    mutate(
      Address = normalize_household_id(Address),
      provision_method = suppressWarnings(as.integer(as.character(DYCOL02))),
      health_expenditure_component =
        suppressWarnings(as.numeric(as.character(DYCOL03)))
    )

  # HEIS provision-method code 1 means purchased. Codes 2-8 represent
  # non-cash acquisition methods and must not enter the OOP numerator.
  invalid_method <- is.na(data$provision_method) |
    !(data$provision_method %in% 1:8)
  if (any(invalid_method)) {
    stop(
      "Unmapped or missing medical provision-method codes found. ",
      "Review DYCOL02 before constructing out-of-pocket expenditure."
    )
  }

  data |>
    group_by(Address) |>
    summarise(
      health_expenditure = sum(
        health_expenditure_component[provision_method == 1L],
        na.rm = TRUE
      ),
      health_expenditure_all_methods = sum(
        health_expenditure_component,
        na.rm = TRUE
      ),
      medical_record_count = n(),
      oop_record_count = sum(provision_method == 1L, na.rm = TRUE),
      noncash_record_count = sum(provision_method %in% 2:8, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      # Table 6 is a monthly-recall expenditure table.
      annual_health_expenditure = health_expenditure * 12
    )
}

R93_health <- aggregate_health_expenditure(R93P3S06)
U93_health <- aggregate_health_expenditure(U93P3S06)

if (anyDuplicated(R93_health$Address) || anyDuplicated(U93_health$Address)) {
  stop("Health expenditure aggregation did not produce unique household identifiers.")
}
############################################################
# 5. Import External Household Files
############################################################

# Import household-level survey files containing demographic
# and expenditure information.

R93 <- read_excel("data/processed/R93.xls")
U93 <- read_excel("data/processed/U93.xls")


# Standardize household identifier name

R93 <- R93 |>
  rename(
    Address = ADDRESS
  )

U93 <- U93 |>
  rename(
    Address = ADDRESS
  )

R93 <- R93 |>
  mutate(Address = normalize_household_id(Address))

U93 <- U93 |>
  mutate(Address = normalize_household_id(Address))


############################################################
# 6. Merge Household Information
############################################################

# Merge household characteristics with health expenditure data

# Preserve the complete household sample. A household with no row in
# the medical-expenditure table has no recorded health expenditure in
# that table; the independent HEIS processing script likewise fills
# absent expenditure categories with zero after a household-level join.
merge_rural <- R93 |>
  left_join(R93_health, by = "Address")

merge_urban <- U93 |>
  left_join(U93_health, by = "Address")

health_data <- bind_rows(
  merge_rural,
  merge_urban
) |>
  mutate(
    health_expenditure = coalesce(health_expenditure, 0),
    health_expenditure_all_methods =
      coalesce(health_expenditure_all_methods, 0),
    medical_record_count = coalesce(medical_record_count, 0L),
    oop_record_count = coalesce(oop_record_count, 0L),
    noncash_record_count = coalesce(noncash_record_count, 0L),
    annual_health_expenditure = coalesce(annual_health_expenditure, 0)
  )

if (nrow(health_data) != nrow(R93) + nrow(U93)) {
  stop("Household merge changed the source household count.")
}
if (anyDuplicated(health_data$Address)) {
  stop("Household merge produced duplicate household identifiers.")
}


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
    income_rank = C11New,
    income_rank_unweighted = C11
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
  mutate(
    across(
      c(
        food_expenditure,
        total_expenditure,
        household_size,
        age,
        weight,
        annual_health_expenditure,
        health_expenditure
      ),
      ~ suppressWarnings(as.numeric(as.character(.x)))
    )
  )

# The benchmark excludes households with unreported food expenditure.
# Build one scalar summary per residence directly from the household-level
# data. This avoids relying on vector comparisons inside scalar if() calls.
summarise_sample_by_residence <- function(data, residence) {
  data |>
    filter(as.character(residence_type) == residence) |>
    summarise(
      residence_type = residence,
      source_n = n(),
      missing_food_n = sum(is.na(food_expenditure)),
      analysis_n = sum(!is.na(food_expenditure))
    )
}

sample_by_residence <- bind_rows(
  summarise_sample_by_residence(health_data, "Urban"),
  summarise_sample_by_residence(health_data, "Rural")
)

urban_sample <- sample_by_residence |>
  filter(residence_type == "Urban")
rural_sample <- sample_by_residence |>
  filter(residence_type == "Rural")

if (nrow(urban_sample) != 1L || nrow(rural_sample) != 1L) {
  stop("Expected exactly one sample-summary row for each residence category.")
}

observed_urban_source_n <- urban_sample$source_n[[1]]
observed_rural_source_n <- rural_sample$source_n[[1]]
observed_urban_missing_food_n <- urban_sample$missing_food_n[[1]]
observed_rural_missing_food_n <- rural_sample$missing_food_n[[1]]
observed_urban_analysis_n <- urban_sample$analysis_n[[1]]
observed_rural_analysis_n <- rural_sample$analysis_n[[1]]
observed_total_analysis_n <- observed_urban_analysis_n +
  observed_rural_analysis_n
observed_urban_share_percent <- 100 * observed_urban_analysis_n /
  observed_total_analysis_n

benchmark_2018_status <- if (
  observed_urban_analysis_n == 18857L &&
    observed_rural_analysis_n == 19334L
) "MATCH" else "DIFFERS"

# Mousavi et al. (2024) report the total and rounded urban share, not the
# exact urban/rural analytical counts.
benchmark_2024_status <- if (
  observed_total_analysis_n == 38189L &&
    round(observed_urban_share_percent, 2) == 49.37
) "CONSISTENT_WITH_REPORTED_TOTAL_AND_SHARE" else "DIFFERS"

sample_benchmark_comparison <- tibble(
  benchmark = c(
    "Yazdi-Feyzabadi et al. (2018)",
    "Mousavi et al. (2024)"
  ),
  observed_urban_source_n = observed_urban_source_n,
  observed_rural_source_n = observed_rural_source_n,
  observed_urban_missing_food_n = observed_urban_missing_food_n,
  observed_rural_missing_food_n = observed_rural_missing_food_n,
  observed_urban_analysis_n = observed_urban_analysis_n,
  observed_rural_analysis_n = observed_rural_analysis_n,
  observed_total_analysis_n = observed_total_analysis_n,
  observed_urban_share_percent = observed_urban_share_percent,
  expected_urban_analysis_n = c(18857L, NA_integer_),
  expected_rural_analysis_n = c(19334L, NA_integer_),
  expected_total_analysis_n = c(38191L, 38189L),
  expected_urban_share_percent = c(
    100 * 18857 / 38191,
    49.37
  ),
  benchmark_status = c(
    benchmark_2018_status,
    benchmark_2024_status
  ),
  comparison_note = c(
    "The 2018 article reports two more urban households than the current source files.",
    "The 2024 article reports 38,189 households and a rounded urban share of 49.37%; exact residence-specific counts are not reported in its sample-size table."
  )
)

write.csv(
  sample_benchmark_comparison,
  "outputs/diagnostics/sample_benchmark_comparison.csv",
  row.names = FALSE
)

health_data <- health_data |>
  filter(!is.na(food_expenditure))


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
    income_rank_unweighted,
    weight,
    health_expenditure,
    health_expenditure_all_methods,
    medical_record_count,
    oop_record_count,
    noncash_record_count,
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
  group_by(year, residence_type) |>
  mutate(
    food_share_percentile = percent_rank(food_expenditure_share)
  ) |>
  ungroup()


############################################################
# 18. Estimate Subsistence Expenditure
############################################################

# Estimate the subsistence expenditure level using households
# around the median food-share group.

final_health_data <- final_health_data |>
  group_by(year, residence_type) |>
  mutate(
    subsistence_expenditure = weighted.mean(
      equivalent_food_expenditure[
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
# Validate core measurement inputs before constructing CHE.
if (any(!is.finite(final_health_data$weight)) ||
    any(final_health_data$weight <= 0)) {
  stop("Survey weights must be finite and strictly positive.")
}
if (any(!is.finite(final_health_data$total_expenditure)) ||
    any(final_health_data$total_expenditure <= 0)) {
  stop("Total household expenditure must be finite and positive.")
}
if (any(!is.finite(final_health_data$food_expenditure)) ||
    any(final_health_data$food_expenditure < 0)) {
  stop("Food expenditure must be finite and non-negative.")
}
if (any(final_health_data$household_size < 1, na.rm = TRUE)) {
  stop("Household size must be at least one.")
}
if (any(final_health_data$annual_health_expenditure < 0, na.rm = TRUE)) {
  stop("Annualized OOP expenditure cannot be negative.")
}

############################################################
# 23. Descriptive Statistics
############################################################

# Export reproducible descriptive statistics to a standards-compliant
# Excel workbook. Identifier fields are excluded from the summaries.

numeric_variables <- names(final_health_data)[
  vapply(final_health_data, is.numeric, logical(1))
]
numeric_variables <- setdiff(
  numeric_variables,
  c("Address", "DYCOL01", "DYCOL02")
)

numeric_summary <- do.call(
  rbind,
  lapply(numeric_variables, function(variable) {
    x <- final_health_data[[variable]]
    observed <- x[!is.na(x)]

    data.frame(
      variable = variable,
      observations = length(observed),
      missing = sum(is.na(x)),
      mean = if (length(observed) > 0) mean(observed) else NA_real_,
      standard_deviation = if (length(observed) > 1) sd(observed) else NA_real_,
      minimum = if (length(observed) > 0) min(observed) else NA_real_,
      median = if (length(observed) > 0) median(observed) else NA_real_,
      maximum = if (length(observed) > 0) max(observed) else NA_real_
    )
  })
)

categorical_variables <- intersect(
  c("residence_type", "gender", "literacy", "income_rank"),
  names(final_health_data)
)
categorical_variables <- categorical_variables[
  !vapply(
    final_health_data[categorical_variables],
    is.numeric,
    logical(1)
  )
]

categorical_summary <- do.call(
  rbind,
  lapply(categorical_variables, function(variable) {
    values <- as.character(final_health_data[[variable]])
    values[is.na(values)] <- "(Missing)"
    counts <- as.data.frame(
      table(values),
      stringsAsFactors = FALSE
    )
    names(counts) <- c("category", "unweighted_n")
    counts$variable <- variable
    counts$weighted_n <- vapply(
      counts$category,
      function(level) {
        sum(final_health_data$weight[values == level], na.rm = TRUE)
      },
      numeric(1)
    )
    counts$weighted_percent <- 100 * counts$weighted_n /
      sum(final_health_data$weight, na.rm = TRUE)

    counts[, c(
      "variable",
      "category",
      "unweighted_n",
      "weighted_n",
      "weighted_percent"
    )]
  })
)

if (is.null(categorical_summary)) {
  categorical_summary <- data.frame(
    variable = character(),
    category = character(),
    unweighted_n = integer(),
    weighted_n = numeric(),
    weighted_percent = numeric()
  )
}

writexl::write_xlsx(
  list(
    "Numeric Summary" = numeric_summary,
    "Categorical Counts" = categorical_summary
  ),
  path = "outputs/tables/summary_statistics.xlsx"
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
  
  family = quasibinomial(link = "logit")
  
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
  gof_map = NA,
  notes = "Odds ratios are reported; delta-method standard errors are in parentheses. Survey-weighted logistic models.",
  
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
  
  family = quasibinomial(link = "logit")
  
)


summary(model_urban)



############################################################
# 29. Large-Household Outcome-Support Diagnostics
############################################################

# The previous large-household logit produced extreme odds ratios and
# standard errors, consistent with sparse cells or separation. Do not
# present that unstable specification as a substantive result. Export
# the outcome support by income category for transparent diagnosis.

large_household_support <- final_health_data |>
  filter(
    household_size > 6,
    !is.na(catastrophic_health_expenditure),
    !is.na(income_rank)
  ) |>
  group_by(income_rank) |>
  summarise(
    unweighted_n = n(),
    CHE_cases = sum(catastrophic_health_expenditure == 1),
    non_CHE_cases = sum(catastrophic_health_expenditure == 0),
    weighted_n = sum(weight, na.rm = TRUE),
    weighted_CHE_prevalence = weighted.mean(
      catastrophic_health_expenditure,
      weight,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

write.csv(
  large_household_support,
  "outputs/tables/large_household_support.csv",
  row.names = FALSE
)

writeLines(
  c(
    "Large-household logistic regression not reported.",
    "The previous specification produced extreme estimates and standard errors,",
    "consistent with sparse outcome support or separation.",
    "See large_household_support.csv before selecting an alternative specification."
  ),
  "outputs/tables/large_household_model_status.txt"
)



############################################################
# 30. Export Multiple Models
############################################################

modelsummary(
  
  list(
    "Main Model" = model_main,
    "Urban Households" = model_urban
  ),
  
  exponentiate = TRUE,
  
  statistic = "std.error",
  
  stars = TRUE,
  gof_omit = "AIC|BIC|Log.Lik|RMSE|R2",
  notes = "Odds ratios are reported; delta-method standard errors are in parentheses. Survey-weighted logistic models.",
  
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


# Export measurement diagnostics by residence and for the full sample.
che_diagnostic_data <- bind_rows(
  final_health_data |>
    mutate(residence_group = as.character(residence_type)),
  final_health_data |>
    mutate(residence_group = "All")
)

che_construction_diagnostics <- che_diagnostic_data |>
  group_by(residence_group) |>
  summarise(
    households = n(),
    weighted_population = sum(weight, na.rm = TRUE),
    nonpositive_capacity_to_pay_n = sum(capacity_to_pay <= 0, na.rm = TRUE),
    nonfinite_health_ratio_n = sum(!is.finite(health_expenditure_ratio)),
    missing_CHE_n = sum(is.na(catastrophic_health_expenditure)),
    poor_before_health_payment_n = sum(poor_household == 1, na.rm = TRUE),
    unweighted_CHE_prevalence = mean(catastrophic_health_expenditure, na.rm = TRUE),
    weighted_CHE_prevalence = weighted.mean(
      catastrophic_health_expenditure, weight, na.rm = TRUE
    ),
    weighted_CHE30_prevalence = weighted.mean(cata_30, weight, na.rm = TRUE),
    weighted_CHE50_prevalence = weighted.mean(cata_50, weight, na.rm = TRUE),
    weighted_mean_annual_OOP = weighted.mean(
      annual_health_expenditure, weight, na.rm = TRUE
    ),
    weighted_mean_capacity_to_pay = weighted.mean(
      capacity_to_pay, weight, na.rm = TRUE
    ),
    .groups = "drop"
  )

write.csv(
  che_construction_diagnostics,
  "outputs/diagnostics/che_construction_diagnostics.csv",
  row.names = FALSE
)

if (any(che_construction_diagnostics$nonpositive_capacity_to_pay_n > 0) ||
    any(che_construction_diagnostics$nonfinite_health_ratio_n > 0)) {
  stop(
    "CHE construction produced non-positive capacity to pay or non-finite ",
    "health-expenditure ratios. Inspect che_construction_diagnostics.csv."
  )
}

############################################################
# 31. Final Research Extensions
############################################################

# Income quintile analysis

# C11New is used as the primary weighted income-decile candidate.
# The source audit finds near-equal weighted totals across its ten categories
# within each residence group, while original C11 has near-equal unweighted
# counts. Official metadata confirmation remains outstanding.
# Map adjacent deciles into quintiles explicitly; ntile() would split tied
# categories and create artificial breaks.
income_decile <- suppressWarnings(as.integer(as.character(final_health_data$income_rank)))
income_decile_unweighted <- suppressWarnings(
  as.integer(as.character(final_health_data$income_rank_unweighted))
)
if (any(!is.na(income_decile) & !(income_decile %in% 0:9))) {
  stop("C11New contains values outside the expected 0-9 income-decile coding.")
}
if (any(!is.na(income_decile_unweighted) & !(income_decile_unweighted %in% 0:9))) {
  stop("C11 contains values outside the expected 0-9 income-decile coding.")
}

final_health_data <- final_health_data |>
  mutate(
    income_decile = income_decile,
    income_decile_unweighted = income_decile_unweighted,
    income_quintile = case_when(
      income_decile %in% c(0L, 1L) ~ 1L,
      income_decile %in% c(2L, 3L) ~ 2L,
      income_decile %in% c(4L, 5L) ~ 3L,
      income_decile %in% c(6L, 7L) ~ 4L,
      income_decile %in% c(8L, 9L) ~ 5L,
      TRUE ~ NA_integer_
    )
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
  "outputs/tables/Table_CHE_by_income_quintile.csv",
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
  "outputs/figures/figure1_income_quintile_CHE.png",
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
  family = quasibinomial(link = "logit")
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
  family = quasibinomial(link = "logit")
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
  family = quasibinomial(link = "logit")
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
  family = quasibinomial(link = "logit")
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
  gof_omit = "AIC|BIC|Log.Lik|RMSE|R2",
  notes = "Odds ratios are reported; delta-method standard errors are in parentheses. Survey-weighted logistic models.",
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
  gof_omit = "AIC|BIC|Log.Lik|RMSE|R2",
  notes = "Odds ratios are reported; delta-method standard errors are in parentheses. Survey-weighted logistic models.",
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

write.csv(
  final_missing_summary,
  "outputs/tables/missing_data_summary.csv",
  row.names = FALSE
)

# Validate the constructed outcome before estimation.
observed_CHE_values <- unique(
  na.omit(final_health_data$catastrophic_health_expenditure)
)
if (!all(observed_CHE_values %in% c(0, 1))) {
  stop("The catastrophic health expenditure outcome is not binary.")
}

# Session information for reproducibility
sessionInfo()




# Preserve warnings rather than allowing Rscript to report only a count.
captured_warnings <- warnings()
warning_text <- if (is.null(captured_warnings)) {
  "No warnings recorded."
} else {
  capture.output(print(captured_warnings))
}
writeLines(
  c(
    paste0(
      "Captured warning count: ",
      if (is.null(captured_warnings)) 0L else length(captured_warnings)
    ),
    warning_text
  ),
  "outputs/diagnostics/analysis_warnings.txt"
)

############################################################
# OUTPUT VALIDATION
############################################################

# Verify that the principal files generated by this analysis
# exist and are non-empty before reporting successful completion.

expected_outputs <- c(
  "outputs/tables/summary_statistics.xlsx",
  "outputs/tables/regression_results.docx",
  "outputs/tables/model_comparison.docx",
  "outputs/tables/CHE_final_regression_table.docx",
  "outputs/tables/CHE_threshold_robustness.docx",
  "outputs/tables/Table_CHE_by_income_quintile.csv",
  "outputs/tables/large_household_support.csv",
  "outputs/tables/large_household_model_status.txt",
  "outputs/tables/missing_data_summary.csv",
  "outputs/diagnostics/che_construction_diagnostics.csv",
  "outputs/diagnostics/analysis_warnings.txt",
  "outputs/figures/figure1_income_quintile_CHE.png"
)

missing_outputs <- expected_outputs[
  !file.exists(expected_outputs) |
    file.info(expected_outputs)$size <= 0
]

if (length(missing_outputs) > 0) {
  stop(
    "Output validation failed. Missing or empty files: ",
    paste(missing_outputs, collapse = ", ")
  )
}

# Validate that the Excel workbook is readable, not merely non-empty.
tryCatch(
  {
    workbook_path <- "outputs/tables/summary_statistics.xlsx"
    workbook_sheets <- readxl::excel_sheets(workbook_path)

    expected_sheets <- c("Numeric Summary", "Categorical Counts")
    if (!identical(workbook_sheets, expected_sheets)) {
      stop(
        "Unexpected workbook sheets: ",
        paste(workbook_sheets, collapse = ", ")
      )
    }

    invisible(lapply(
      workbook_sheets,
      function(sheet) readxl::read_excel(workbook_path, sheet = sheet)
    ))
  },
  error = function(e) {
    stop(
      "Excel output validation failed: ",
      conditionMessage(e)
    )
  }
)

message(
  "OUTPUT VALIDATION PASSED: ",
  length(expected_outputs),
  " expected outputs exist, are non-empty, and the Excel workbook is readable."
)

############################################################
# END OF ANALYSIS
############################################################
