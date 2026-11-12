# Household Catastrophic Health Expenditure in Iran

An R workflow for constructing a household-level measure of catastrophic health expenditure (CHE) from the Iranian 1393 Household Expenditure and Income Survey (2014–15). The analysis estimates conditional associations between CHE and household characteristics using survey-weighted logistic regression.

## Reproduce the analysis

Use 64-bit Linux. On Windows, use a Linux distribution in WSL2 and clone the repository inside it. Install Pixi 0.84.2. [Pixi release](https://github.com/prefix-dev/pixi/releases/tag/v0.84.2)

Run this command from the repository root.

```bash
pixi run --locked reproduce
```

Pixi installs R 4.4.3, the R packages, 7-Zip, MDB Tools and Python from the committed lockfile. The first installation downloads the locked packages from conda-forge. The runner checks the five input hashes, extracts the source files in a private temporary directory, runs the audits and analysis, and publishes the outputs after the checks pass.

Each successful invocation prints its new `reproduced/run-*/` directory. The tracked `outputs/` directory contains earlier snapshots. GitHub Actions runs the same command on Ubuntu 24.04 and provides the current results under the `household-che-research-outputs` artifact.

| Result | Where to find it |
| --- | --- |
| Regression coefficients, standard errors and model counts | `tables/regression_coefficients.csv` and four Word tables |
| Descriptive statistics and weighted CHE by economic quintile | `tables/summary_statistics.xlsx`, `tables/Table_CHE_by_economic_quintile.csv`, `figures/` |
| Source provenance, interview-month linkage and sample comparison | `diagnostics/access_linkage.csv`, `diagnostics/sample_benchmark_comparison.csv` |
| CHE definition sensitivity and comparison with published estimates | `diagnostics/che_specification_sensitivity.csv`, `diagnostics/che_benchmark_comparison.csv` |
| Baseline inference with province clustering | `diagnostics/baseline_inference_sensitivity.csv` |
| Run provenance | `diagnostics/input_sha256.txt`, `diagnostics/session_info.txt` |

## Data and measurement

The pipeline starts with 38,275 households from the rural and urban summary workbooks. It uses the household address to link the medical module and assigns zero recorded Table 6 expenditure to households with no Table 6 records. Excluding 86 households with missing food expenditure leaves 38,189 households for CHE construction. The Access audit verifies a valid interview month for every workbook household and medical record and matches all 68,217 RDS medical records to the original Table 6 data after normalizing their storage formats. [Input inventory](data/README.md)

The baseline numerator sums purchased Table 6 medical items (acquisition code 1) and multiplies the monthly amount by 12. The denominator treats `GHazineh` and `VKhorak` as annual total and food expenditures. Capacity to pay equals total expenditure minus the smaller of observed food expenditure and estimated subsistence expenditure. The baseline CHE indicator applies a 40% threshold to the ratio of these two amounts. The analysis also applies 30% and 50% thresholds.

To estimate subsistence expenditure, the analysis divides food expenditure by household size raised to 0.56. Within each residence group, it takes the weighted mean among households whose food share is strictly between 45% and 55%, then scales the resulting poverty line to each household's size. A sensitivity analysis uses the 45th–55th percentile of total consumption to select the reference group. A further diagnostic totals Table 6 records across all acquisition methods, including noncash methods. [Yazdi-Feyzabadi et al. (2018)](https://doi.org/10.1186/s12939-018-0743-y) · [Ghiasvand et al. (2015)](https://doi.org/10.5812/ircmj.30974)

The regressions use the original `C11` decile field as a categorical measure of economic rank. The analysis retains `C11New` for source diagnostics. Both derived fields need original metadata to establish whether they rank income or expenditure.

## Validation and limits

- The automated checks compare the frozen sample and CHE prevalence with the earlier nominal run. They also verify the medical record linkage, model outputs, threshold ordering and report files.
- At the 40% threshold, the weighted nominal CHE prevalence is **1.79% overall**, **2.50% rural** and **1.54% urban**. The corresponding 2014 published figures are 3.15%, 4.38% and 2.69%. Weighted monthly total and food expenditure match the published table at its reported precision. Monthly OOP and the estimated poverty line still differ. [Yazdi-Feyzabadi et al. (2018), Tables 2–3](https://doi.org/10.1186/s12939-018-0743-y)
- The analytical sample contains 19,334 rural and 18,855 urban households. Its total and rounded urban share of 49.37% agree with the 2024 paper. The 2018 paper excludes 28 urban households with unreported food expenditure, compared with 30 in the frozen workbook. The comparison keeps those observed counts. [Mousavi et al. (2024), Table 1](https://doi.org/10.3961/jpmph.23.291) · [Yazdi-Feyzabadi et al. (2018), Table 1](https://doi.org/10.1186/s12939-018-0743-y)
- The medical numerator is nominal. An item-level price adjustment requires the verified 1393 item crosswalk and monthly price indices, as well as a consistent price basis for the numerator and denominator. The independent HEIS script references `Global.rds` and `CPI.rds`. These inputs are unavailable in the public code checkout. The interview-month audit establishes the linkage needed for that adjustment. [Hoseini's HEIS documentation](https://m-hoseini.github.io/HEIS/cleaning-data.html) · [1393 processing script](https://github.com/m-hoseini/HEIS_script/blob/c0b7c6acc96447cd1baa2881e1929b6036c7c657/93.R)
- The main regression tables use weights-only standard errors. The baseline sensitivity uses 31 province clusters, with the same point estimates. Full design-based variance estimation still requires confirmed 1393 strata and primary sampling units. The workbook's `Fasl` agrees with the quarter of the month preceding the interview for every linked household. The workbook's block field and its relation to the survey design require official metadata. [HEIS sample design](https://m-hoseini.github.io/HEIS/introduction.html)
