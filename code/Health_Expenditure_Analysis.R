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

# Use the native Word writer so report generation uses the locked R libraries.
write_regression_table <- function(models, title, path) {
  counts <- vapply(models, function(model) {
    format(stats::nobs(model), big.mark = ",", scientific = FALSE)
  }, character(1))
  observations <- as.data.frame(
    c(list(term = "Observations"), as.list(counts)),
    check.names = FALSE
  )
  table <- modelsummary(
    models,
    exponentiate = TRUE,
    statistic = "std.error",
    stars = TRUE,
    gof_map = NA,
    add_rows = observations,
    notes = paste(
      "Odds ratios with delta-method standard errors in parentheses.",
      "Survey weights are applied. Standard errors use the weights-only design."
    ),
    title = title,
    output = "flextable"
  )
  table <- table |>
    flextable::fontsize(size = 9, part = "all") |>
    flextable::padding(padding = 2, part = "all") |>
    flextable::width(j = 1L, width = 2.75) |>
    flextable::width(j = seq_along(models) + 1L, width = 3.45 / length(models)) |>
    flextable::set_table_properties(
      layout = "fixed",
      align = "left",
      opts_word = list(split = FALSE, repeat_headers = TRUE)
    )
  flextable::save_as_docx(table, path = path)
}

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
      provision_method = trimws(as.character(DYCOL02)),
      health_expenditure_component =
        suppressWarnings(as.numeric(as.character(DYCOL03)))
    )

  # HEIS provision-method code 1 means purchased. Codes 2-8 represent
  # non-cash acquisition methods and must not enter the OOP numerator.
  if (anyNA(data$Address) || any(!grepl("^[12][0-9]{10}$", data$Address))) {
    stop("Table 6 contains missing or malformed household identifiers.")
  }
  if (any(!is.finite(data$health_expenditure_component) |
          data$health_expenditure_component < 0)) {
    stop("Table 6 amounts must be finite and non-negative.")
  }
  invalid_method <- !(data$provision_method %in% as.character(1:8))
  if (any(invalid_method)) {
    stop(
      "Unmapped or missing medical provision-method codes found. ",
      "Review DYCOL02 before constructing out-of-pocket expenditure."
    )
  }

  data |>
    mutate(provision_method = as.integer(provision_method)) |>
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
      annual_health_expenditure = health_expenditure * 12,
      annual_health_expenditure_all_methods =
        health_expenditure_all_methods * 12
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

# Import the analysis fields as text, preserving the identifier and category
# codes. Importing unused columns with guessed types produces cell warnings.
read_households_for_analysis <- function(path) {
  required <- c(
    "ADDRESS", "A01", "A02", "A03", "C01",
    "GHazineh", "VKhorak", "C11", "C11New", "weight"
  )
  header <- names(read_excel(path, n_max = 0))
  missing <- setdiff(required, header)
  if (length(missing) > 0L) {
    stop(path, " is missing analysis fields: ", paste(missing, collapse = ", "))
  }
  read_excel(path, col_types = ifelse(header %in% required, "text", "skip")) |>
    rename(Address = ADDRESS) |>
    mutate(Address = normalize_household_id(Address))
}

R93 <- read_households_for_analysis("data/processed/R93.xls")
U93 <- read_households_for_analysis("data/processed/U93.xls")

if (anyNA(R93$Address) || any(!grepl("^2[0-9]{10}$", R93$Address)) ||
    anyNA(U93$Address) || any(!grepl("^1[0-9]{10}$", U93$Address))) {
  stop("The rural and urban workbooks contain missing or malformed household IDs.")
}


############################################################
# 6. Merge Household Information
############################################################

# Merge household characteristics with health expenditure data

# Preserve the complete household sample. A household with no row in
# the medical-expenditure table has no recorded health expenditure in
# that table; the independent HEIS processing script likewise fills
# absent expenditure categories with zero after a household-level join.
merge_rural <- R93 |>
  left_join(R93_health, by = "Address", relationship = "one-to-one")

merge_urban <- U93 |>
  left_join(U93_health, by = "Address", relationship = "one-to-one")

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
    annual_health_expenditure = coalesce(annual_health_expenditure, 0),
    annual_health_expenditure_all_methods =
      coalesce(annual_health_expenditure_all_methods, 0)
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
    economic_rank = C11,
    economic_rank_alternative = C11New
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
    "Primary source-file counts match the article (18,885 urban; 19,390 rural), but the current food-expenditure field is missing for 30 urban households versus 28 reported exclusions, leaving two additional urban exclusions.",
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
    economic_rank,
    economic_rank_alternative,
    weight,
    health_expenditure,
    health_expenditure_all_methods,
    annual_health_expenditure_all_methods,
    medical_record_count,
    oop_record_count,
    noncash_record_count,
    annual_health_expenditure
  )

# Validate the inputs used by the subsistence and capacity-to-pay calculations.
if (any(!is.finite(final_health_data$weight) | final_health_data$weight <= 0)) {
  stop("Survey weights must be finite and strictly positive.")
}
if (any(!is.finite(final_health_data$total_expenditure) |
        final_health_data$total_expenditure <= 0)) {
  stop("Total household expenditure must be finite and positive.")
}
if (any(!is.finite(final_health_data$food_expenditure) |
        final_health_data$food_expenditure < 0)) {
  stop("Food expenditure must be finite and non-negative.")
}
if (any(!is.finite(final_health_data$household_size) | final_health_data$household_size < 1)) {
  stop("Household size must be finite and at least one.")
}
if (any(!is.finite(final_health_data$annual_health_expenditure) |
        final_health_data$annual_health_expenditure < 0)) {
  stop("Annualized OOP expenditure must be finite and non-negative.")
}

############################################################
# Methodological Framework
############################################################

# This analysis follows the catastrophic health expenditure
# framework developed by Xu et al. (2003).
#
# Capacity to pay is defined as household expenditure remaining
# after subsistence expenditure.
#
# For the 2018 benchmark, subsistence expenditure is estimated from
# households whose food expenditure share is between 45% and 55%.
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
# 17. Identify the Food-Share Reference Group
############################################################

# The primary specification follows Yazdi-Feyzabadi et al. (2018):
# the reference group consists of households whose food expenditure is
# between 45% and 55% of total expenditure, separately by residence.
# The poverty line is the weighted mean of equivalent food expenditure
# within this reference group.
#
# The alternative specification follows Ghiasvand et al. (2015):
# rank households by total consumption and use the 45th-55th percentile
# group to estimate the weighted mean equivalent-food poverty line.

final_health_data <- final_health_data |>
  group_by(year, residence_type) |>
  mutate(
    total_expenditure_percentile = percent_rank(total_expenditure)
  ) |>
  ungroup()


############################################################
# 18. Estimate Subsistence Expenditure
############################################################

final_health_data <- final_health_data |>
  group_by(year, residence_type) |>
  mutate(
    subsistence_expenditure = weighted.mean(
      equivalent_food_expenditure[
        food_expenditure_share > 0.45 &
          food_expenditure_share < 0.55
      ],
      weight[
        food_expenditure_share > 0.45 &
          food_expenditure_share < 0.55
      ],
      na.rm = TRUE
    ),
    subsistence_expenditure_total_rank = weighted.mean(
      equivalent_food_expenditure[
        total_expenditure_percentile >= 0.45 &
          total_expenditure_percentile <= 0.55
      ],
      weight[
        total_expenditure_percentile >= 0.45 &
          total_expenditure_percentile <= 0.55
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
      subsistence_expenditure * equivalence_size,
    adjusted_subsistence_expenditure_total_rank =
      subsistence_expenditure_total_rank * equivalence_size
  )


############################################################
# 20. Calculate Capacity To Pay
############################################################

# Capacity to pay is expenditure remaining after basic
# subsistence needs.

final_health_data <- final_health_data |>
  mutate(
    # Following the WHO-style rule used in the benchmark literature:
    # subtract subsistence expenditure when food spending reaches it;
    # otherwise subtract observed food expenditure.
    # This is total expenditure less the smaller of the two amounts.
    capacity_to_pay = total_expenditure - pmin(
      food_expenditure,
      adjusted_subsistence_expenditure
    ),
    capacity_to_pay_total_rank = total_expenditure - pmin(
      food_expenditure,
      adjusted_subsistence_expenditure_total_rank
    )
  )

if (any(!is.finite(final_health_data$capacity_to_pay) |
        final_health_data$capacity_to_pay <= 0) ||
    any(!is.finite(final_health_data$capacity_to_pay_total_rank) |
        final_health_data$capacity_to_pay_total_rank <= 0)) {
  stop("Both CHE specifications require finite, strictly positive capacity to pay.")
}

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
      as.integer(health_expenditure_ratio >= 0.40),
    health_expenditure_ratio_total_rank =
      annual_health_expenditure / capacity_to_pay_total_rank,
    catastrophic_health_expenditure_total_rank =
      as.integer(health_expenditure_ratio_total_rank >= 0.40)
  )
if (any(!is.finite(final_health_data$health_expenditure_ratio)) ||
    any(!is.finite(final_health_data$health_expenditure_ratio_total_rank))) {
  stop("Both CHE specifications require finite health-expenditure ratios.")
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
  c("residence_type", "gender", "literacy", "economic_rank"),
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
    economic_rank +
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

write_regression_table(
  list("Survey Weighted Logistic Regression" = model_main),
  "Determinants of Catastrophic Health Expenditure",
  "outputs/tables/regression_results.docx"
)



############################################################
# 28. Robustness Analysis: Urban Households
############################################################

# Estimate model for urban households only, using the same neutral economic-rank field.

urban_design <- subset(
  
  survey_design,
  
  residence_type == "Urban"
  
)


model_urban <- svyglm(
  
  catastrophic_health_expenditure ~
    economic_rank +
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
# the outcome support by economic-rank category for transparent diagnosis.

large_household_support <- final_health_data |>
  filter(
    household_size > 6,
    !is.na(catastrophic_health_expenditure),
    !is.na(economic_rank)
  ) |>
  group_by(economic_rank) |>
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

write_regression_table(
  list("Main Model" = model_main, "Urban Households" = model_urban),
  "Logistic Regression Results",
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
# The benchmark reports a national poverty line as well as rural and urban
# lines. The national line must be estimated from the national 45%-55%
# food-share reference group; it is not the weighted average of the two
# residence-specific lines. This national line is diagnostic only: the
# household-level CHE outcome continues to use the residence-specific line.
national_reference_group <- final_health_data$food_expenditure_share > 0.45 &
  final_health_data$food_expenditure_share < 0.55
if (!any(national_reference_group)) {
  stop("The national 45%-55% food-share reference group is empty.")
}
national_subsistence_expenditure <- weighted.mean(
  final_health_data$equivalent_food_expenditure[national_reference_group],
  final_health_data$weight[national_reference_group],
  na.rm = TRUE
)
if (!is.finite(national_subsistence_expenditure)) {
  stop("The national subsistence expenditure estimate is not finite.")
}

subsistence_reference_group_data <- bind_rows(
  final_health_data |>
    mutate(residence_group = as.character(residence_type)),
  final_health_data |>
    mutate(residence_group = "All")
) |>
  mutate(
    in_food_share_reference_group =
      food_expenditure_share > 0.45 & food_expenditure_share < 0.55
  )

subsistence_reference_group_diagnostics <- subsistence_reference_group_data |>
  group_by(residence_group) |>
  summarise(
    households = n(),
    reference_group_households = sum(in_food_share_reference_group),
    reference_group_unweighted_share =
      mean(in_food_share_reference_group),
    reference_group_weighted_population = sum(
      weight[in_food_share_reference_group], na.rm = TRUE
    ),
    reference_group_weighted_share = weighted.mean(
      as.numeric(in_food_share_reference_group), weight, na.rm = TRUE
    ),
    weighted_mean_equivalent_food_expenditure = weighted.mean(
      equivalent_food_expenditure[in_food_share_reference_group],
      weight[in_food_share_reference_group], na.rm = TRUE
    ),
    unweighted_mean_equivalent_food_expenditure = mean(
      equivalent_food_expenditure[in_food_share_reference_group],
      na.rm = TRUE
    ),
    weighted_mean_household_size = weighted.mean(
      household_size[in_food_share_reference_group],
      weight[in_food_share_reference_group], na.rm = TRUE
    ),
    weighted_mean_monthly_food_expenditure = weighted.mean(
      food_expenditure[in_food_share_reference_group],
      weight[in_food_share_reference_group], na.rm = TRUE
    ) / 12,
    weighted_mean_monthly_total_expenditure = weighted.mean(
      total_expenditure[in_food_share_reference_group],
      weight[in_food_share_reference_group], na.rm = TRUE
    ) / 12,
    .groups = "drop"
  )

write.csv(
  subsistence_reference_group_diagnostics,
  "outputs/diagnostics/subsistence_reference_group_diagnostics.csv",
  row.names = FALSE
)

che_diagnostic_data <- bind_rows(
  final_health_data |>
    mutate(residence_group = as.character(residence_type)),
  final_health_data |>
    mutate(residence_group = "All")
) |>
  mutate(
    diagnostic_subsistence_expenditure = if_else(
      residence_group == "All",
      national_subsistence_expenditure,
      subsistence_expenditure
    )
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
    weighted_mean_total_expenditure_annual = weighted.mean(
      total_expenditure, weight, na.rm = TRUE
    ),
    weighted_mean_food_expenditure_annual = weighted.mean(
      food_expenditure, weight, na.rm = TRUE
    ),
    weighted_mean_annual_OOP = weighted.mean(
      annual_health_expenditure, weight, na.rm = TRUE
    ),
    weighted_mean_capacity_to_pay_annual = weighted.mean(
      capacity_to_pay, weight, na.rm = TRUE
    ),
    weighted_mean_monthly_total_expenditure = weighted.mean(
      total_expenditure, weight, na.rm = TRUE
    ) / 12,
    weighted_mean_monthly_food_expenditure = weighted.mean(
      food_expenditure, weight, na.rm = TRUE
    ) / 12,
    weighted_mean_monthly_OOP = weighted.mean(
      health_expenditure, weight, na.rm = TRUE
    ),
    weighted_mean_monthly_capacity_to_pay = weighted.mean(
      capacity_to_pay, weight, na.rm = TRUE
    ) / 12,
    weighted_mean_monthly_poverty_line = weighted.mean(
      diagnostic_subsistence_expenditure, weight, na.rm = TRUE
    ) / 12,
    weighted_mean_monthly_adjusted_subsistence = weighted.mean(
      adjusted_subsistence_expenditure, weight, na.rm = TRUE
    ) / 12,
    weighted_mean_monthly_CTP_deduction = weighted.mean(
      pmin(food_expenditure, adjusted_subsistence_expenditure),
      weight, na.rm = TRUE
    ) / 12,
    weighted_share_food_below_subsistence = weighted.mean(
      food_expenditure < adjusted_subsistence_expenditure,
      weight, na.rm = TRUE
    ),
    .groups = "drop"
  )

write.csv(
  che_construction_diagnostics,
  "outputs/diagnostics/che_construction_diagnostics.csv",
  row.names = FALSE
)

# Compare the two published subsistence-reference-group approaches and
# two medical-numerator definitions. "All Table 6 values" is diagnostic only:
# it includes non-purchased acquisition methods and must not be interpreted
# as an OOP measure without further validation of the questionnaire coding.
summarise_che_specification <- function(
  data,
  reference_method,
  capacity_variable,
  numerator_method,
  numerator_variable
) {
  specification_data <- data |>
    mutate(
      residence_group = as.character(residence_type),
      reference_method = reference_method,
      numerator_method = numerator_method,
      specification_capacity_to_pay = .data[[capacity_variable]],
      specification_annual_health = .data[[numerator_variable]],
      specification_CHE = as.integer(
        specification_annual_health / specification_capacity_to_pay >= 0.40
      )
    )

  specification_data <- bind_rows(
    specification_data,
    specification_data |> mutate(residence_group = "All")
  )

  specification_data |>
    group_by(reference_method, numerator_method, residence_group) |>
    summarise(
      households = n(),
      weighted_CHE_prevalence = weighted.mean(
        specification_CHE, weight, na.rm = TRUE
      ),
      weighted_mean_capacity_to_pay = weighted.mean(
        specification_capacity_to_pay, weight, na.rm = TRUE
      ),
      weighted_mean_annual_health_expenditure = weighted.mean(
        specification_annual_health, weight, na.rm = TRUE
      ),
      .groups = "drop"
    )
}

che_specification_sensitivity <- bind_rows(
  summarise_che_specification(
    final_health_data,
    "Food-share interval 45%-55% (Yazdi-Feyzabadi et al., 2018)",
    "capacity_to_pay",
    "Purchased records only (candidate OOP measure)",
    "annual_health_expenditure"
  ),
  summarise_che_specification(
    final_health_data,
    "Total-consumption percentile 45th-55th (Ghiasvand et al., 2015)",
    "capacity_to_pay_total_rank",
    "Purchased records only (candidate OOP measure)",
    "annual_health_expenditure"
  ),
  summarise_che_specification(
    final_health_data,
    "Food-share interval 45%-55% (Yazdi-Feyzabadi et al., 2018)",
    "capacity_to_pay",
    "All recorded Table 6 acquisition methods (diagnostic only)",
    "annual_health_expenditure_all_methods"
  ),
  summarise_che_specification(
    final_health_data,
    "Total-consumption percentile 45th-55th (Ghiasvand et al., 2015)",
    "capacity_to_pay_total_rank",
    "All recorded Table 6 acquisition methods (diagnostic only)",
    "annual_health_expenditure_all_methods"
  )
) |>
  mutate(
    weighted_CHE_prevalence_percent = 100 * weighted_CHE_prevalence
  )

write.csv(
  che_specification_sensitivity,
  "outputs/diagnostics/che_specification_sensitivity.csv",
  row.names = FALSE
)


# Compare the current weighted CHE prevalence with the published 2014
# benchmark reported by Yazdi-Feyzabadi et al. (2018). This is a diagnostic,
# not an assertion that the measures are identical: CPI treatment, numerator
# scope, and sampling-design implementation still require reconciliation.
published_che_benchmark <- tibble(
  residence_group = c("All", "Rural", "Urban"),
  published_2014_weighted_CHE_prevalence_percent = c(3.15, 4.38, 2.69),
  published_monthly_total_expenditure_thousand_rials = c(17857, 11749, 20032),
  published_monthly_food_expenditure_thousand_rials = c(4670, 4673, 4669),
  published_monthly_poverty_line_thousand_rials = c(2393, 2223, 2354),
  published_monthly_capacity_to_pay_thousand_rials = c(14105, 8019, 16303),
  published_monthly_OOP_thousand_rials = c(1194, 781, 1341)
)

che_benchmark_comparison <- che_construction_diagnostics |>
  select(
    residence_group,
    weighted_CHE_prevalence,
    weighted_mean_monthly_total_expenditure,
    weighted_mean_monthly_food_expenditure,
    weighted_mean_monthly_capacity_to_pay,
    weighted_mean_monthly_poverty_line,
    weighted_mean_monthly_adjusted_subsistence,
    weighted_mean_monthly_CTP_deduction,
    weighted_share_food_below_subsistence,
    weighted_mean_monthly_OOP
  ) |>
  mutate(
    observed_weighted_CHE_prevalence_percent =
      100 * weighted_CHE_prevalence,
    observed_monthly_total_expenditure_thousand_rials =
      weighted_mean_monthly_total_expenditure / 1000,
    observed_monthly_food_expenditure_thousand_rials =
      weighted_mean_monthly_food_expenditure / 1000,
    observed_monthly_poverty_line_thousand_rials =
      weighted_mean_monthly_poverty_line / 1000,
    observed_monthly_capacity_to_pay_thousand_rials =
      weighted_mean_monthly_capacity_to_pay / 1000,
    observed_monthly_adjusted_subsistence_thousand_rials =
      weighted_mean_monthly_adjusted_subsistence / 1000,
    observed_monthly_CTP_deduction_thousand_rials =
      weighted_mean_monthly_CTP_deduction / 1000,
    observed_share_food_below_subsistence_percent =
      100 * weighted_share_food_below_subsistence,
    observed_monthly_OOP_thousand_rials =
      weighted_mean_monthly_OOP / 1000
  ) |>
  left_join(published_che_benchmark, by = "residence_group") |>
  mutate(
    difference_percentage_points =
      observed_weighted_CHE_prevalence_percent -
      published_2014_weighted_CHE_prevalence_percent,
    difference_monthly_total_expenditure_thousand_rials =
      observed_monthly_total_expenditure_thousand_rials -
      published_monthly_total_expenditure_thousand_rials,
    difference_monthly_food_expenditure_thousand_rials =
      observed_monthly_food_expenditure_thousand_rials -
      published_monthly_food_expenditure_thousand_rials,
    difference_monthly_poverty_line_thousand_rials =
      observed_monthly_poverty_line_thousand_rials -
      published_monthly_poverty_line_thousand_rials,
    published_implied_monthly_CTP_deduction_thousand_rials =
      published_monthly_total_expenditure_thousand_rials -
      published_monthly_capacity_to_pay_thousand_rials,
    difference_monthly_CTP_deduction_thousand_rials =
      observed_monthly_CTP_deduction_thousand_rials -
      published_implied_monthly_CTP_deduction_thousand_rials,
    difference_monthly_capacity_to_pay_thousand_rials =
      observed_monthly_capacity_to_pay_thousand_rials -
      published_monthly_capacity_to_pay_thousand_rials,
    difference_monthly_OOP_thousand_rials =
      observed_monthly_OOP_thousand_rials -
      published_monthly_OOP_thousand_rials
  )

write.csv(
  che_benchmark_comparison,
  "outputs/diagnostics/che_benchmark_comparison.csv",
  row.names = FALSE
)

############################################################
# 31. Final Research Extensions
############################################################

# Economic quintile analysis

# Preserve C11 as the primary decile variable used in the original project
# specification. C11New is retained as an alternative candidate because
# its weighted distribution differs materially, especially in urban areas.
# Neither variable is labelled as income- or expenditure-based until the
# official 1393 variable metadata are verified.
# Map adjacent deciles into quintiles explicitly.

economic_decile <- suppressWarnings(
  as.integer(as.character(final_health_data$economic_rank))
)
economic_decile_alternative <- suppressWarnings(
  as.integer(as.character(final_health_data$economic_rank_alternative))
)

if (any(!is.na(economic_decile) & !(economic_decile %in% 0:9))) {
  stop("C11 contains values outside the expected 0-9 decile coding.")
}
if (any(!is.na(economic_decile_alternative) &
        !(economic_decile_alternative %in% 0:9))) {
  stop("C11New contains values outside the expected 0-9 decile coding.")
}

final_health_data <- final_health_data |>
  mutate(
    economic_decile = economic_decile,
    economic_decile_alternative = economic_decile_alternative,
    economic_quintile = case_when(
      economic_decile %in% c(0L, 1L) ~ 1L,
      economic_decile %in% c(2L, 3L) ~ 2L,
      economic_decile %in% c(4L, 5L) ~ 3L,
      economic_decile %in% c(6L, 7L) ~ 4L,
      economic_decile %in% c(8L, 9L) ~ 5L,
      TRUE ~ NA_integer_
    )
  )

survey_design <- svydesign(
  ids = ~1,
  weights = ~weight,
  data = final_health_data
)


economic_quintile_summary <- svyby(
  ~catastrophic_health_expenditure,
  ~economic_quintile,
  survey_design,
  svymean,
  na.rm = TRUE
)


write.csv(
  economic_quintile_summary,
  "outputs/tables/Table_CHE_by_economic_quintile.csv",
  row.names = FALSE
)


income_plot <- ggplot(
  economic_quintile_summary,
  aes(
    x = economic_quintile,
    y = catastrophic_health_expenditure
  )
) +
  geom_line() +
  geom_point() +
  labs(
    title = "Catastrophic Health Expenditure by Economic Quintile",
    x = "Economic Quintile",
    y = "Weighted Prevalence"
  )


ggsave(
  "outputs/figures/figure1_economic_quintile_CHE.png",
  income_plot,
  width = 7,
  height = 5
)


# Province fixed effects

model_province <- svyglm(
  catastrophic_health_expenditure ~
    economic_rank +
    residence_type +
    household_size +
    gender +
    age +
    literacy +
    factor(province),
  design = survey_design,
  family = quasibinomial(link = "logit")
)


# Economic-rank and rural interaction

model_interaction <- svyglm(
  catastrophic_health_expenditure ~
    economic_rank * residence_type +
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
    economic_rank +
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
    economic_rank +
    residence_type +
    household_size +
    gender +
    age +
    literacy,
  design = survey_design,
  family = quasibinomial(link = "logit")
)


# Final regression table

write_regression_table(
  list(
    "Baseline" = model_main,
    "Province FE" = model_province,
    "Economic rank x Rural" = model_interaction
  ),
  "Survey-Weighted Logistic Regression Specifications",
  "outputs/tables/CHE_final_regression_table.docx"
)


write_regression_table(
  list(
    "CHE 30%" = model_CHE30,
    "CHE 40%" = model_main,
    "CHE 50%" = model_CHE50
  ),
  "Catastrophic Expenditure Threshold Sensitivity",
  "outputs/tables/CHE_threshold_robustness.docx"
)

# Export unrounded regression results alongside the formatted Word tables.
reported_models <- list(
  baseline = model_main,
  urban = model_urban,
  province_fixed_effects = model_province,
  economic_rank_residence_interaction = model_interaction,
  che_30_percent = model_CHE30,
  che_50_percent = model_CHE50
)
regression_coefficients <- bind_rows(lapply(names(reported_models), function(name) {
  fit <- reported_models[[name]]
  terms <- summary(fit)$coefficients
  tibble(
    model = name,
    term = rownames(terms),
    observations = stats::nobs(fit),
    log_odds = terms[, 1],
    log_odds_std_error = terms[, 2],
    odds_ratio = exp(log_odds),
    odds_ratio_std_error = odds_ratio * log_odds_std_error,
    p_value = terms[, 4]
  )
}))
write.csv(regression_coefficients, "outputs/tables/regression_coefficients.csv", row.names = FALSE)

# Sensitivity of baseline inference to correlation within provinces.
# The documented HEIS sampling stages require additional design identifiers.
province_cluster_design <- svydesign(
  ids = ~province,
  weights = ~weight,
  data = final_health_data
)
model_main_province_clusters <- svyglm(
  formula(model_main),
  design = province_cluster_design,
  family = quasibinomial(link = "logit")
)
baseline_terms <- summary(model_main)$coefficients
clustered_terms <- summary(model_main_province_clusters)$coefficients
if (!isTRUE(all.equal(baseline_terms[, 1], clustered_terms[, 1], tolerance = 1e-10))) {
  stop("Province clustering changed the baseline point estimates.")
}
inference_sensitivity <- tibble(
  term = rownames(baseline_terms),
  log_odds = baseline_terms[, 1],
  weights_only_std_error = baseline_terms[, 2],
  province_clustered_std_error = clustered_terms[, 2],
  weights_only_p_value = baseline_terms[, 4],
  province_clustered_p_value = clustered_terms[, 4],
  provinces = n_distinct(final_health_data$province),
  province_clustered_residual_df = model_main_province_clusters$df.residual
)
write.csv(
  inference_sensitivity,
  "outputs/diagnostics/baseline_inference_sensitivity.csv",
  row.names = FALSE
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

# Preserve the R version, locale, BLAS and loaded package versions in the run.
writeLines(capture.output(sessionInfo()), "outputs/diagnostics/session_info.txt")




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
  "outputs/tables/Table_CHE_by_economic_quintile.csv",
  "outputs/tables/large_household_support.csv",
  "outputs/tables/large_household_model_status.txt",
  "outputs/tables/regression_coefficients.csv",
  "outputs/tables/missing_data_summary.csv",
  "outputs/diagnostics/che_construction_diagnostics.csv",
  "outputs/diagnostics/che_specification_sensitivity.csv",
  "outputs/diagnostics/che_benchmark_comparison.csv",
  "outputs/diagnostics/baseline_inference_sensitivity.csv",
  "outputs/diagnostics/analysis_warnings.txt",
  "outputs/diagnostics/sample_benchmark_comparison.csv",
  "outputs/diagnostics/subsistence_reference_group_diagnostics.csv",
  "outputs/diagnostics/session_info.txt",
  "outputs/figures/figure1_economic_quintile_CHE.png"
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
