# Compare results with the nominal estimates at 482f4ce and check the
# data linkage, tables, and figure.
check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

linkage <- read.csv("outputs/diagnostics/access_linkage.csv")
check(
  identical(linkage$survey_residence, c("Rural", "Urban")) &&
    identical(linkage$workbook_households, c(19390L, 18885L)) &&
    identical(linkage$medical_records_in_rds, c(33932L, 34285L)) &&
    all(linkage$workbook_households == linkage$workbook_households_with_valid_month) &&
    all(linkage$workbook_households == linkage$workbook_quarters_matching_previous_month) &&
    all(linkage$medical_records_in_rds == linkage$medical_records_with_valid_month) &&
    all(linkage$medical_records_match_access),
  "Access linkage or original Table 6 record verification failed."
)

construction <- read.csv("outputs/diagnostics/che_construction_diagnostics.csv")
check(
  identical(construction$residence_group, c("All", "Rural", "Urban")) &&
    identical(construction$households, c(38189L, 19334L, 18855L)) &&
    all(construction$nonpositive_capacity_to_pay_n == 0L) &&
    all(construction$nonfinite_health_ratio_n == 0L) &&
    all(construction$missing_CHE_n == 0L) &&
    all(construction$weighted_CHE30_prevalence >= construction$weighted_CHE_prevalence) &&
    all(construction$weighted_CHE_prevalence >= construction$weighted_CHE50_prevalence),
  "Household counts, capacity to pay, or CHE threshold checks failed."
)
check(
  isTRUE(all.equal(
    construction$weighted_CHE_prevalence,
    c(0.017878736346289, 0.0249732742922547, 0.0153530551627343),
    tolerance = 1e-10
  )),
  "Weighted nominal CHE prevalence differs from the reference run."
)

quintiles <- read.csv("outputs/tables/Table_CHE_by_economic_quintile.csv")
prevalence <- quintiles$catastrophic_health_expenditure
check(
  identical(quintiles$economic_quintile, 1:5) &&
    all(is.finite(prevalence) & prevalence >= 0 & prevalence <= 1) &&
    all(is.finite(quintiles$se) & quintiles$se >= 0) &&
    isTRUE(all.equal(
      prevalence,
      c(0.0301388705610919, 0.0213394452638728, 0.0159936332185114,
        0.0124080444108737, 0.0138083271474178),
      tolerance = 1e-10
    )),
  "Economic-quintile prevalence or standard errors are invalid."
)

coefficients <- read.csv("outputs/tables/regression_coefficients.csv")
check(
  setequal(unique(coefficients$model), c(
    "baseline", "urban", "province_fixed_effects",
    "economic_rank_residence_interaction", "che_30_percent", "che_50_percent"
  )) &&
    !anyDuplicated(coefficients[c("model", "term")]) &&
    all(coefficients$observations > 0L) &&
    all(is.finite(coefficients$log_odds)) &&
    all(is.finite(coefficients$log_odds_std_error) & coefficients$log_odds_std_error > 0) &&
    all(is.finite(coefficients$p_value) & coefficients$p_value >= 0 & coefficients$p_value <= 1),
  "Regression coefficients, standard errors, or p-values are invalid."
)

inference <- read.csv("outputs/diagnostics/baseline_inference_sensitivity.csv")
check(
  identical(inference$term, coefficients$term[coefficients$model == "baseline"]) &&
    all(inference$provinces == 31L) &&
    all(is.finite(inference$province_clustered_std_error) &
          inference$province_clustered_std_error > 0) &&
    all(is.finite(inference$province_clustered_p_value) &
          inference$province_clustered_p_value >= 0 &
          inference$province_clustered_p_value <= 1),
  "Province-clustered baseline inference checks failed."
)

documents <- list.files("outputs/tables", pattern = "[.]docx$", full.names = TRUE)
check(length(documents) == 4L, "Expected four Word regression tables.")
for (path in documents) {
  summary <- officer::docx_summary(officer::read_docx(path))
  check(any(summary$text == "Observations"), paste("Missing model counts in", basename(path)))
}

png <- readBin("outputs/figures/figure1_economic_quintile_CHE.png", "raw", n = 8)
check(
  identical(png, as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))),
  "The economic-quintile figure is not a readable PNG."
)

message("The sample counts and nominal estimates match the reference results.")
