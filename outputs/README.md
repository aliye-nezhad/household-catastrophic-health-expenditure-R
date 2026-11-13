# Results for the 1393 household survey

The files in this directory are a historical results snapshot associated with analysis version [`e9499c5`](https://github.com/aliye-nezhad/household-catastrophic-health-expenditure-R/commit/e9499c5393662f50ba5378baa2ffaf3dcd025819). They are retained for reference and are not fresh outputs from the current `main` version. To reproduce the current analysis, run `pixi run --locked reproduce` from the repository root and inspect the new results under `reproduced/run-*/`. See the [main README](../README.md) for the reproduction procedure and validation checks.

## Sample, estimates, and figure

| File | Contents |
| --- | --- |
| [Sample characteristics](tables/summary_statistics.xlsx) | Household summary statistics, counts, and weighted shares. |
| [Main regression](tables/regression_results.docx) | Household-weighted logistic estimates reported as odds ratios. |
| [Final regression table](tables/CHE_final_regression_table.docx) | Baseline, province fixed effects, and the interaction between economic rank and residence. |
| [Coefficient estimates](tables/regression_coefficients.csv) | Log-odds estimates, odds ratios, standard errors, and p-values across specifications. |
| [Model comparison](tables/model_comparison.docx) | Baseline and urban-only specifications. |
| [Threshold sensitivity](tables/CHE_threshold_robustness.docx) | Estimates at the 30%, 40%, and 50% thresholds. |
| [Economic-rank figure](figures/figure1_economic_quintile_CHE.png) and [figure data](tables/Table_CHE_by_economic_quintile.csv) | Weighted prevalence across five groups formed by pairing adjacent C11 categories. |

The missing-data summary counts missing observations by variable. The large-household table gives case counts by economic rank for households with more than six members. [Missing-data summary](tables/missing_data_summary.csv) · [Large-household counts](tables/large_household_support.csv) · [Model note](tables/large_household_model_status.txt)

## Diagnostics

- Weighted CHE prevalence by residence and threshold. [Outcome construction](diagnostics/che_construction_diagnostics.csv)
- Estimates and household counts alongside the published figures. [Published estimates](diagnostics/che_benchmark_comparison.csv) · [Household counts](diagnostics/sample_benchmark_comparison.csv)
- Estimates under alternative spending definitions and subsistence reference groups. [Specification sensitivity](diagnostics/che_specification_sensitivity.csv) · [Subsistence reference groups](diagnostics/subsistence_reference_group_diagnostics.csv)
- Baseline and province-clustered standard errors. [Inference sensitivity](diagnostics/baseline_inference_sensitivity.csv)
- Survey-file hashes and aggregate matches to the Access database. [Input hashes](diagnostics/input_sha256.txt) · [Linkage counts](diagnostics/access_linkage.csv)
