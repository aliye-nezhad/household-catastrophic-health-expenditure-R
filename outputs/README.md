# Results for the 1393 household survey

These files come from the analysis at [`e9499c5`](https://github.com/aliye-nezhad/household-catastrophic-health-expenditure-R/commit/e9499c5393662f50ba5378baa2ffaf3dcd025819). To regenerate them, run `pixi run --locked reproduce` from the repository root. The command prints the path to the full results under `reproduced/run-*/`.

## Sample, estimates, and figure

| File | Contents |
| --- | --- |
| [Sample characteristics](tables/summary_statistics.xlsx) | Household summary statistics, counts, and weighted shares. |
| [Main regression](tables/regression_results.docx) | Survey-weighted logit estimates reported as odds ratios. |
| [Final regression table](tables/CHE_final_regression_table.docx) | Baseline, province fixed effects, and the interaction between economic rank and residence. |
| [Coefficient estimates](tables/regression_coefficients.csv) | Log-odds estimates, odds ratios, standard errors, and p-values across specifications. |
| [Model comparison](tables/model_comparison.docx) | Baseline and urban-only specifications. |
| [Threshold sensitivity](tables/CHE_threshold_robustness.docx) | Estimates at the 30%, 40%, and 50% thresholds. |
| [Economic-rank figure](figures/figure1_economic_quintile_CHE.png) and [figure data](tables/Table_CHE_by_economic_quintile.csv) | Weighted prevalence across five groups formed by pairing adjacent C11 categories. |

The [missing-data summary](tables/missing_data_summary.csv) gives the number of missing observations by variable. The [large-household counts](tables/large_household_support.csv) and [model note](tables/large_household_model_status.txt) explain why a separate model for larger households would have few cases in some economic-rank categories.

## Diagnostics

- [Outcome construction](diagnostics/che_construction_diagnostics.csv) shows weighted prevalence by residence and threshold.
- [Published comparison](diagnostics/che_benchmark_comparison.csv) and [sample comparison](diagnostics/sample_benchmark_comparison.csv) compare the results and household counts with published figures.
- [Specification sensitivity](diagnostics/che_specification_sensitivity.csv) and [subsistence reference groups](diagnostics/subsistence_reference_group_diagnostics.csv) show how the spending definition and reference sample affect the estimates.
- [Inference sensitivity](diagnostics/baseline_inference_sensitivity.csv) compares the baseline standard errors with province-clustered standard errors.
- [Linkage counts](diagnostics/access_linkage.csv) and [input hashes](diagnostics/input_sha256.txt) identify the survey files and report their agreement with the original database.
