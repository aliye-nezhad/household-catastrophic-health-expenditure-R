############################################################
# Source-data audit for the 1393 Iranian HEIS CHE project
#
# This script does not alter the analysis dataset or estimate CHE.
# It audits household coverage, medical-record coverage, provision
# methods, income-rank values, weights, and candidate design fields.
############################################################

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(readxl))

access_dir <- commandArgs(trailingOnly = TRUE)
if (length(access_dir) > 1L) {
  stop("Usage: Rscript code/audit_source_data.R [temporary Access-export directory]")
}

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
  data <- readxl::read_excel(path, col_types = "text", .name_repair = "unique")
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

# DYCOL02 records how the item was obtained, not the type of
# healthcare provider. Codes 2-8 are non-monetary acquisition methods.
# Labels follow the HEIS questionnaire documentation and its description
# of non-monetary income.
method_labels <- c(
  "1" = "Purchased",
  "2" = "Home-produced",
  "3" = "Received in return for public-sector work",
  "4" = "Received in return for cooperative-sector work",
  "5" = "Received in return for private-sector work",
  "6" = "Received in return for agricultural-business work",
  "7" = "Received in return for non-agricultural-business work",
  "8" = "Received free"
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
# Compare original and alternate income-rank and household-size fields.
# These diagnostics do not choose a preferred variable; the codebook must
# establish the intended definitions before the analysis specification changes.
income_rank_distribution <- bind_rows(
  lapply(list(Rural = rural_households, Urban = urban_households), function(data) {
    bind_rows(lapply(intersect(c("C11", "C11New"), names(data)), function(variable) {
      x <- as.character(data[[variable]])
      w <- suppressWarnings(as.numeric(as.character(data$weight)))
      total_exp <- suppressWarnings(as.numeric(as.character(data$GHazineh)))
      food_exp <- suppressWarnings(as.numeric(as.character(data$VKhorak)))

      tibble(
        survey_residence = unique(data$survey_residence),
        income_variable = variable,
        category = x,
        analysis_weight = w,
        total_expenditure = total_exp,
        food_expenditure = food_exp
      ) |>
        filter(!is.na(category)) |>
        group_by(survey_residence, income_variable, category) |>
        summarise(
          unweighted_households = n(),
          weighted_households = sum(analysis_weight, na.rm = TRUE),
          weighted_mean_total_expenditure = weighted.mean(
            total_expenditure, analysis_weight, na.rm = TRUE
          ),
          weighted_mean_food_expenditure = weighted.mean(
            food_expenditure, analysis_weight, na.rm = TRUE
          ),
          .groups = "drop"
        )
    }))
  })
)

income_rank_crosswalk <- bind_rows(
  lapply(list(Rural = rural_households, Urban = urban_households), function(data) {
    if (!all(c("C11", "C11New") %in% names(data))) return(NULL)
    tibble(
      survey_residence = unique(data$survey_residence),
      C11 = as.character(data$C11),
      C11New = as.character(data$C11New)
    ) |>
      count(survey_residence, C11, C11New, name = "households") |>
      group_by(survey_residence, C11) |>
      mutate(share_within_C11 = households / sum(households)) |>
      ungroup()
  })
)

household_size_crosswalk <- bind_rows(
  lapply(list(Rural = rural_households, Urban = urban_households), function(data) {
    if (!all(c("C01", "C01New") %in% names(data))) return(NULL)
    tibble(
      survey_residence = unique(data$survey_residence),
      C01 = as.character(data$C01),
      C01New = as.character(data$C01New)
    ) |>
      count(survey_residence, C01, C01New, name = "households") |>
      group_by(survey_residence, C01) |>
      mutate(share_within_C01 = households / sum(households)) |>
      ungroup()
  })
)

# Fasl and block are candidate survey-design fields, not confirmed strata
# or PSU identifiers. Report their empirical structure without assigning
# design roles based on names alone.
sampling_candidate_summary <- bind_rows(
  lapply(list(Rural = rural_households, Urban = urban_households), function(data) {
    if (!all(c("Fasl", "block", "weight") %in% names(data))) return(NULL)
    tibble(
      survey_residence = unique(data$survey_residence),
      Fasl = as.character(data$Fasl),
      block = as.character(data$block),
      analysis_weight = suppressWarnings(as.numeric(as.character(data$weight)))
    ) |>
      group_by(survey_residence, Fasl) |>
      summarise(
        household_rows = n(),
        distinct_blocks = n_distinct(block),
        blocks_with_multiple_households = sum(table(block) > 1),
        min_households_per_block = min(as.integer(table(block))),
        median_households_per_block = median(as.integer(table(block))),
        max_households_per_block = max(as.integer(table(block))),
        sum_weights = sum(analysis_weight, na.rm = TRUE),
        .groups = "drop"
      )
  })
)

# Check whether the same block identifier recurs across survey quarters
# within province and residence. This helps determine whether Fasl belongs
# in the PSU identifier; it does not assign design roles by itself.
block_fasl_reuse <- households |>
  mutate(
    province_code = substr(Address, 2, 3),
    block = as.character(block),
    Fasl = as.character(Fasl)
  ) |>
  filter(!is.na(block), !is.na(Fasl)) |>
  distinct(survey_residence, province_code, block, Fasl) |>
  group_by(survey_residence, province_code, block) |>
  summarise(fasl_count = n_distinct(Fasl), .groups = "drop") |>
  group_by(survey_residence, province_code) |>
  summarise(
    unique_blocks = n(),
    blocks_observed_in_multiple_fasls = sum(fasl_count > 1),
    share_blocks_observed_in_multiple_fasls = mean(fasl_count > 1),
    max_fasls_per_block = max(fasl_count),
    .groups = "drop"
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

canonical_medical_records <- function(data) {
  fields <- c("Address", "DYCOL01", "DYCOL02", "DYCOL03")
  if (!all(fields %in% names(data))) {
    stop("A Table 6 input is missing Address, item, acquisition method or amount.")
  }

  # Access stores zero-padded item codes and amounts as text. The committed
  # RDS stores them as numbers. Sort all four fields to compare multisets.
  data |>
    as_tibble() |>
    transmute(
      Address = as_id(Address),
      DYCOL01 = as.numeric(DYCOL01),
      DYCOL02 = as.numeric(DYCOL02),
      DYCOL03 = as.numeric(DYCOL03)
    ) |>
    arrange(Address, DYCOL01, DYCOL02, DYCOL03)
}

audit_access_linkage <- function(prefix, household_data, medical_data) {
  month_path <- file.path(access_dir, paste0(prefix, "Data_interview_month.csv"))
  access_months <- read.csv(month_path, colClasses = "character")
  address <- as_id(access_months$Address)
  month_text <- trimws(access_months$MahMorajeh)
  valid_month <- grepl("^(0?[1-9]|1[0-2])$", month_text)
  if (anyNA(address) || any(!nzchar(address)) || anyDuplicated(address)) {
    stop(prefix, " Access metadata must contain one row per nonempty Address.")
  }

  household_match <- match(household_data$Address, address)
  medical_match <- match(medical_data$Address, address)
  month <- suppressWarnings(as.integer(month_text))
  previous_month_quarter <- ((month[household_match] - 2L) %% 12L) %/% 3L + 1L
  recorded_quarter <- suppressWarnings(as.integer(household_data$Fasl))
  purchased <- medical_data$DYCOL02 == 1
  purchased_item_months <- tibble(
    item = medical_data$DYCOL01[purchased],
    month = month[medical_match[purchased]]
  ) |>
    filter(month %in% 1:12) |>
    distinct() |>
    nrow()

  medical_path <- file.path(access_dir, paste0(prefix, "P3S06.csv"))
  access_medical <- read.csv(medical_path, colClasses = "character")
  rds_records <- canonical_medical_records(medical_data)
  access_records <- canonical_medical_records(access_medical)

  tibble(
    survey_residence = first(household_data$survey_residence),
    access_household_rows = nrow(access_months),
    workbook_households = nrow(household_data),
    workbook_households_with_valid_month = sum(valid_month[household_match], na.rm = TRUE),
    workbook_quarters_matching_previous_month = sum(
      recorded_quarter == previous_month_quarter, na.rm = TRUE
    ),
    medical_records_in_rds = nrow(rds_records),
    medical_records_in_access = nrow(access_records),
    medical_records_with_valid_month = sum(valid_month[medical_match], na.rm = TRUE),
    purchased_item_month_pairs = purchased_item_months,
    medical_records_match_access = !anyNA(rds_records) &&
      identical(rds_records, access_records)
  )
}

if (length(access_dir) == 1L) {
  access_linkage <- bind_rows(
    audit_access_linkage("R93", rural_households, rural_medical),
    audit_access_linkage("U93", urban_households, urban_medical)
  )
  write.csv(access_linkage, "outputs/diagnostics/access_linkage.csv", row.names = FALSE)
}

write.csv(coverage_summary, "outputs/diagnostics/household_medical_coverage.csv", row.names = FALSE)
write.csv(medical_method_summary, "outputs/diagnostics/medical_provision_method.csv", row.names = FALSE)
write.csv(medical_summary, "outputs/diagnostics/medical_data_summary.csv", row.names = FALSE)
write.csv(variable_inventory, "outputs/diagnostics/household_variable_inventory.csv", row.names = FALSE)
write.csv(design_candidate_fields, "outputs/diagnostics/design_candidate_fields.csv", row.names = FALSE)
write.csv(sample_summary, "outputs/diagnostics/household_sample_summary.csv", row.names = FALSE)

write.csv(
  income_rank_distribution,
  "outputs/diagnostics/income_rank_candidate_distribution.csv",
  row.names = FALSE
)
write.csv(
  income_rank_crosswalk,
  "outputs/diagnostics/C11_C11New_crosswalk.csv",
  row.names = FALSE
)
write.csv(
  household_size_crosswalk,
  "outputs/diagnostics/C01_C01New_crosswalk.csv",
  row.names = FALSE
)
write.csv(
  sampling_candidate_summary,
  "outputs/diagnostics/Fasl_block_design_candidates.csv",
  row.names = FALSE
)
write.csv(
  block_fasl_reuse,
  "outputs/diagnostics/block_fasl_reuse_by_province.csv",
  row.names = FALSE
)

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
  "outputs/diagnostics/source_audit_warnings.txt"
)

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
  paste0("Households with missing or non-positive weights: ",
         sum(is.na(coverage$analysis_weight) | coverage$analysis_weight <= 0)),
  "",
  "C11 has nearly equal unweighted counts; C11New has nearly equal weighted totals within residence.",
  "The analysis retains C11 as the original project baseline and treats C11New as an alternative.",
  "The official meaning of these derived decile fields (income versus expenditure) remains unverified; no substantive label is inferred from distributional patterns alone.",
  "C01New top-codes household size at 10; the original C01 preserves larger values.",
  "Fasl and block remain candidate design fields pending confirmation from survey documentation.",
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
  "outputs/diagnostics/income_rank_candidate_distribution.csv",
  "outputs/diagnostics/C11_C11New_crosswalk.csv",
  "outputs/diagnostics/C01_C01New_crosswalk.csv",
  "outputs/diagnostics/Fasl_block_design_candidates.csv",
  "outputs/diagnostics/block_fasl_reuse_by_province.csv",
  "outputs/diagnostics/source_data_audit.txt",
  "outputs/diagnostics/source_audit_warnings.txt"
)
if (length(access_dir) == 1L) {
  expected <- c(expected, "outputs/diagnostics/access_linkage.csv")
}

missing <- expected[!file.exists(expected) | file.info(expected)$size <= 0]
if (length(missing) > 0) {
  stop("Source-data audit outputs missing or empty: ", paste(missing, collapse = ", "))
}

message("SOURCE-DATA AUDIT PASSED: ", length(expected), " diagnostic files validated.")
