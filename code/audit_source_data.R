############################################################
# Source-data audit for the 1393 Iranian HEIS CHE project
#
# This script does not alter the analysis dataset or estimate CHE.
# It audits household coverage, medical-record coverage, provision
# methods, income-rank values, weights, and candidate design fields.
############################################################

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(readxl))

dir.create("outputs/diagnostics", recursive = TRUE, showWarnings = FALSE)

as_id <- function(x) {
  if (is.numeric(x)) {
    out <- format(x, scientific = FALSE, trim = TRUE, digits = 22)
    out <- sub("\\.0+$", "", out)
  } else {
    out <- trimws(as.character(x))
  }
  out[is.na(x)] <- NA_character_
  out
}

standardize_address <- function(data, label) {
  candidates <- intersect(c("Address", "ADDRESS", "address"), names(data))
  if (length(candidates) == 0) {
    stop(label, " has no recognizable household Address column.")
  }
  if (candidates[1] != "Address") {
    names(data)[names(data) == candidates[1]] <- "Address"
  }
  data$Address <- as_id(data$Address)
  data
}

read_households <- function(path, residence) {
  data <- readxl::read_excel(path, .name_repair = "unique")
  data <- standardize_address(data, path)
  data$survey_residence <- residence
  data
}

read_medical <- function(path, residence) {
  data <- readRDS(path)
  data <- standardize_address(data, path)
  required <- c("DYCOL01", "DYCOL02", "DYCOL03")
  absent <- setdiff(required, names(data))
  if (length(absent) > 0) {
    stop(path, " is missing required fields: ", paste(absent, collapse = ", "))
  }
  data$DYCOL03 <- suppressWarnings(as.numeric(as.character(data$DYCOL03)))
  data$survey_residence <- residence
  data
}

rural_households <- read_households("data/processed/R93.xls", "Rural")
urban_households <- read_households("data/processed/U93.xls", "Urban")
rural_medical <- read_medical("data/raw/R93P3S06.rds", "Rural")
urban_medical <- read_medical("data/raw/U93P3S06.rds", "Urban")

households <- bind_rows(rural_households, urban_households)
medical <- bind_rows(rural_medical, urban_medical)

if (anyNA(households$Address) || anyNA(medical$Address)) {
  stop("Missing household identifiers found in source files.")
}

# One row per sampled household for the coverage comparison.
household_keys <- households |>
  distinct(survey_residence, Address, .keep_all = TRUE)

medical_keys <- medical |>
  distinct(survey_residence, Address) |>
  mutate(has_medical_record = TRUE)

coverage <- household_keys |>
  left_join(medical_keys, by = c("survey_residence", "Address")) |>
  mutate(has_medical_record = if_else(is.na(has_medical_record), FALSE, has_medical_record))

weight_name <- intersect(c("weight", "Weight", "WEIGHT"), names(coverage))
if (length(weight_name) > 0) {
  coverage$analysis_weight <- suppressWarnings(as.numeric(coverage[[weight_name[1]]]))
} else {
  coverage$analysis_weight <- NA_real_
}

coverage_summary <- coverage |>
  group_by(survey_residence) |>
  summarise(
    household_rows_in_source = sum(households$survey_residence == first(survey_residence)),
    unique_sampled_households = n(),
    households_with_medical_records = sum(has_medical_record),
    households_without_medical_records = sum(!has_medical_record),
    share_with_medical_records = mean(has_medical_record),
    sum_weights_with_medical_records = sum(analysis_weight[has_medical_record], na.rm = TRUE),
    sum_weights_without_medical_records = sum(analysis_weight[!has_medical_record], na.rm = TRUE),
    .groups = "drop"
  )

overall_coverage <- coverage |>
  summarise(
    survey_residence = "All",
    household_rows_in_source = nrow(households),
    unique_sampled_households = n(),
    households_with_medical_records = sum(has_medical_record),
    households_without_medical_records = sum(!has_medical_record),
    share_with_medical_records = mean(has_medical_record),
    sum_weights_with_medical_records = sum(analysis_weight[has_medical_record], na.rm = TRUE),
    sum_weights_without_medical_records = sum(analysis_weight[!has_medical_record], na.rm = TRUE)
  )

coverage_summary <- bind_rows(coverage_summary, overall_coverage)

# Report only aggregate match diagnostics. Do not write household Address
# identifiers into workflow artifacts.
duplicate_household_count <- households |>
  count(survey_residence, Address, name = "row_count") |>
  filter(row_count > 1) |>
  nrow()

medical_only_address_count <- medical_keys |>
  anti_join(household_keys, by = c("survey_residence", "Address")) |>
  nrow()

household_only_address_count <- household_keys |>
  anti_join(medical_keys, by = c("survey_residence", "Address")) |>
  nrow()

# The 1393 metadata define these provision codes for the medical table.
# Labels cross-checked against the independent 1393 HEIS processing
# script (93.R), which recodes DYCOL02 as the acquisition method.
method_labels <- c(
  "1" = "Purchased",
  "2" = "Homemade",
  "3" = "Public service",
  "4" = "Cooperative service",
  "5" = "Private service",
  "6" = "Agriculture",
  "7" = "Non-agriculture",
  "8" = "Free"
)

medical$provision_method_label <- unname(method_labels[as.character(medical$DYCOL02)])
medical$provision_method_label[is.na(medical$provision_method_label)] <- "Unmapped code"

medical_method_summary <- medical |>
  group_by(survey_residence, DYCOL02, provision_method_label) |>
  summarise(
    record_count = n(),
    household_count = n_distinct(Address),
    expenditure_sum = sum(DYCOL03, na.rm = TRUE),
    positive_expenditure_records = sum(DYCOL03 > 0, na.rm = TRUE),
    zero_expenditure_records = sum(DYCOL03 == 0, na.rm = TRUE),
    negative_expenditure_records = sum(DYCOL03 < 0, na.rm = TRUE),
    .groups = "drop"
  )

medical_summary <- medical |>
  group_by(survey_residence) |>
  summarise(
    medical_record_rows = n(),
    households_with_medical_records = n_distinct(Address),
    total_recorded_expenditure_all_methods = sum(DYCOL03, na.rm = TRUE),
    records_with_positive_expenditure = sum(DYCOL03 > 0, na.rm = TRUE),
    records_with_zero_expenditure = sum(DYCOL03 == 0, na.rm = TRUE),
    records_with_negative_expenditure = sum(DYCOL03 < 0, na.rm = TRUE),
    min_expenditure = min(DYCOL03, na.rm = TRUE),
    median_expenditure = median(DYCOL03, na.rm = TRUE),
    max_expenditure = max(DYCOL03, na.rm = TRUE),
    .groups = "drop"
  )

# Inventory the original household-file fields, especially potential
# survey-design identifiers and the definition of C11.
inventory_one <- function(data, residence) {
  do.call(rbind, lapply(names(data), function(variable) {
    x <- data[[variable]]
    numeric_x <- is.numeric(x)
    data.frame(
      survey_residence = residence,
      variable = variable,
      class = paste(class(x), collapse = "/"),
      missing = sum(is.na(x)),
      unique_nonmissing = length(unique(x[!is.na(x)])),
      minimum = if (numeric_x && any(!is.na(x))) min(x, na.rm = TRUE) else NA_real_,
      maximum = if (numeric_x && any(!is.na(x))) max(x, na.rm = TRUE) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
}

variable_inventory <- bind_rows(
  inventory_one(rural_households, "Rural"),
  inventory_one(urban_households, "Urban")
)

# Use base R only here; no stringr dependency is required.
design_pattern <- paste(
  "strata", "cluster", "psu", "block", "province", "county",
  "address", "urban", "rural", "season", "fasl", "weight",
  "khooshe", "hhold", "c11",
  sep = "|"
)

design_candidate_fields <- variable_inventory |>
  filter(grepl(design_pattern, variable, ignore.case = TRUE)) |>
  arrange(survey_residence, variable)

# C11 is preserved as a raw category here. The audit does not assume its
# coding until the 1393 codebook and source values have been reconciled.
income_rank_distribution <- bind_rows(
  lapply(list(Rural = rural_households, Urban = urban_households), function(data) {
    if (!("C11" %in% names(data))) return(NULL)
    x <- as.character(data$C11)
    tab <- as.data.frame(table(x, useNA = "ifany"), stringsAsFactors = FALSE)
    names(tab) <- c("C11_value", "unweighted_households")
    if ("weight" %in% names(data)) {
      tab$weighted_households <- vapply(
        tab$C11_value,
        function(level) sum(as.numeric(data$weight)[ifelse(is.na(data$C11), "(Missing)", as.character(data$C11)) == level], na.rm = TRUE),
        numeric(1)
      )
    } else {
      tab$weighted_households <- NA_real_
    }
    tab$survey_residence <- unique(data$survey_residence)
    tab
  })
)

# Summary of the full sample and its match to the medical table.
sample_summary <- households |>
  group_by(survey_residence) |>
  summarise(
    source_rows = n(),
    unique_household_addresses = n_distinct(Address),
    duplicate_rows = n() - n_distinct(Address),
    .groups = "drop"
  )

write.csv(coverage_summary, "outputs/diagnostics/household_medical_coverage.csv", row.names = FALSE)
write.csv(medical_method_summary, "outputs/diagnostics/medical_provision_method.csv", row.names = FALSE)
write.csv(medical_summary, "outputs/diagnostics/medical_data_summary.csv", row.names = FALSE)
write.csv(variable_inventory, "outputs/diagnostics/household_variable_inventory.csv", row.names = FALSE)
write.csv(design_candidate_fields, "outputs/diagnostics/design_candidate_fields.csv", row.names = FALSE)
write.csv(sample_summary, "outputs/diagnostics/household_sample_summary.csv", row.names = FALSE)

if (!is.null(income_rank_distribution)) {
  write.csv(income_rank_distribution, "outputs/diagnostics/C11_value_distribution.csv", row.names = FALSE)
}

summary_lines <- c(
  "1393 HEIS source-data audit",
  paste0("Rural household rows: ", nrow(rural_households)),
  paste0("Urban household rows: ", nrow(urban_households)),
  paste0("Unique household addresses in combined household files: ", nrow(household_keys)),
  paste0("Rural medical rows: ", nrow(rural_medical)),
  paste0("Urban medical rows: ", nrow(urban_medical)),
  paste0("Unique addresses in combined medical files: ", nrow(medical_keys)),
  paste0("Duplicate household-address rows (count only): ", duplicate_household_count),
  paste0("Medical addresses absent from household files (count only): ", medical_only_address_count),
  paste0("Household addresses without medical records (count only): ", household_only_address_count),
  paste0("Household-file variables matching design/identifier patterns: ",
         paste(unique(design_candidate_fields$variable), collapse = ", ")),
  "",
  "Provision-method totals and household coverage are in the accompanying CSV files.",
  "This audit is descriptive only; it does not assign zero health spending to unmatched households."
)

writeLines(summary_lines, "outputs/diagnostics/source_data_audit.txt")

expected <- c(
  "outputs/diagnostics/household_medical_coverage.csv",
  "outputs/diagnostics/medical_provision_method.csv",
  "outputs/diagnostics/medical_data_summary.csv",
  "outputs/diagnostics/household_variable_inventory.csv",
  "outputs/diagnostics/design_candidate_fields.csv",
  "outputs/diagnostics/household_sample_summary.csv",
  "outputs/diagnostics/source_data_audit.txt"
)

missing <- expected[!file.exists(expected) | file.info(expected)$size <= 0]
if (length(missing) > 0) {
  stop("Source-data audit outputs missing or empty: ", paste(missing, collapse = ", "))
}

message("SOURCE-DATA AUDIT PASSED: ", length(expected), " diagnostic files created.")
