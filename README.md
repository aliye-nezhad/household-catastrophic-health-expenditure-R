# Determinants of Household Catastrophic Health Expenditure

## Overview

This repository contains an R workflow for constructing household-level catastrophic health expenditure (CHE) measures from Iranian household survey data, estimating survey-weighted logistic regression models, conducting subgroup and threshold-sensitivity analyses, and exporting tables and figures.

The project is an applied microeconometrics and R coding sample. The regression estimates describe conditional associations; they should not be interpreted as causal effects.

## Research question

How are household socioeconomic and demographic characteristics associated with catastrophic health expenditure among Iranian households?

## Data

The workflow combines household demographic and expenditure information with health-expenditure records and sampling weights. For the medical module, only provision-method code 1 (purchased) is included in the out-of-pocket numerator. Codes 2–8 (homemade, public service, cooperative service, private service, agriculture, non-agriculture, and free) are excluded from that numerator. The all-method total and record counts are retained as diagnostics.

| Variable | Description | Role |
| --- | --- | --- |
| `catastrophic_health_expenditure` | CHE indicator based on the baseline threshold | Dependent variable |
| `annual_health_expenditure` | Annualized purchased medical expenditure from Table 6 (provision-method code 1) | CHE numerator; CPI adjustment remains outstanding |
| `capacity_to_pay` | Household expenditure remaining after subsistence needs | CHE denominator |
| `economic_rank` | C11, the original project decile field; interpretation pending metadata | Main socioeconomic variable |
| `residence_type` | Urban/rural classification | Household characteristic |
| `household_size` | Number of household members | Household characteristic |
| `age` | Age of household head | Demographic characteristic |
| `gender` | Gender of household head | Demographic characteristic |
| `literacy` | Literacy status of household head | Demographic characteristic |

### Input files

The committed source files are stored in `data/raw/`:

- `R93P3S06.rds` and `U93P3S06.rds`: household health-expenditure components used directly by the R script.
- `R93.rar` and `U93.rar`: archives containing the rural and urban household Excel files (`R93.xls` and `U93.xls`).
- `93.rar`: archive containing the original Access database. It is retained as a source archive but is not required by the current R workflow.

The Excel files are extracted at runtime into `data/processed/`. This is a generated directory and is excluded from version control.

## Catastrophic health expenditure construction

The script documents its implementation as following the Xu et al. (2003) framework.

Capacity to pay is defined as total household expenditure after subsistence needs. The baseline CHE indicator is:

```text
CHE = 1 if annual out-of-pocket health expenditure / capacity to pay >= 0.40
CHE = 0 otherwise
```

The baseline threshold is 40% of capacity to pay. The script also estimates alternative 30% and 50% thresholds. The primary reference group for the 2018 benchmark ranks households by food-expenditure share and selects the 45th–55th percentile group within residence; the weighted mean of equivalent food expenditure in that group defines subsistence expenditure. A total-consumption-expenditure percentile reference group, used in a separate Iranian CHE study (Ghiasvand et al., 2015), is retained as a sensitivity specification. These approaches are not interchangeable.

The equivalence-scale exponent is 0.56. Capacity to pay is total expenditure less the greater of observed food expenditure and household-specific subsistence expenditure. The sensitivity output reports how the food-share and total-expenditure reference-group methods affect CHE prevalence. The numerator includes provision-method code 1 (cash purchase) and excludes codes 2–8, consistent with the HEIS questionnaire's acquisition categories and the independent HEIS processing script.

The source audit finds that original C11 has nearly equal unweighted counts across its ten categories, whereas C11New has nearly equal weighted totals within rural and urban samples. The analysis retains C11 as the original project baseline and treats C11New as an alternative candidate. The official meaning of these derived decile fields (income versus expenditure) has not yet been verified, so the code uses the neutral term "economic rank" rather than assigning an unsupported label.

The health numerator currently includes provision-method code 1 (purchased) and excludes codes 2–8. The questionnaire labels code 1 as purchase and codes 2–8 as home production, public/cooperative/private service, agricultural/non-agricultural acquisition, and free provision. This is a candidate cash-OOP definition; it must be checked against the exact benchmark's numerator definition. The health numerator is annualized from monthly Table 6 values. The item-specific CPI series and interview-month linkage used in the independent HEIS processing workflow are not included in this repository, so the numerator remains nominal and the CHE estimates remain provisional.

## Empirical workflow

The R script:

1. Imports the committed RDS health-expenditure components.
2. Aggregates health expenditure to the household level.
3. Reads the rural and urban household files extracted from the RAR archives.
4. Merges the household and health-expenditure information.
5. Constructs demographic, socioeconomic, geographic, and expenditure variables.
6. Calculates subsistence expenditure, capacity to pay, and CHE indicators.
7. Declares a survey design using the household sampling weights.
8. Estimates survey-weighted logistic regressions.
9. Conducts urban-household and large-household subgroup analyses.
10. Estimates province fixed-effects and economic-rank-residence interaction specifications.
11. Estimates alternative CHE thresholds and exports tables and figures.

## Repository structure

```text
household-catastrophic-health-expenditure-R/
├── .github/
│   └── workflows/
│       └── r-reproducibility.yml
├── .gitignore
├── LICENSE
├── README.md
├── code/
│   └── Health_Expenditure_Analysis.R
├── data/
│   ├── README.md
│   └── raw/
│       ├── 93.rar
│       ├── R93.rar
│       ├── U93.rar
│       ├── R93P3S06.rds
│       └── U93P3S06.rds
└── outputs/
    ├── figures/
    │   └── figure1_economic_quintile_CHE.png
    └── tables/
        ├── summary_statistics.xlsx
        ├── regression_results.docx
        ├── model_comparison.docx
        ├── CHE_final_regression_table.docx
        ├── CHE_threshold_robustness.docx
        └── Table_CHE_by_economic_quintile.csv
```

## Requirements

- R 4.4 (the version configured in GitHub Actions)
- `dplyr`
- `readxl`
- `writexl`
- `modelsummary`
- `labelled`
- `survey`
- `ggplot2`
- `flextable`
- `officer`
- 7-Zip, to extract the two household Excel files from their RAR archives

The workflow installs the listed R packages at runtime. A committed package lockfile has not yet been added, so package versions are not currently pinned.

## Reproduction

Run the following commands from the repository root.

First install 7-Zip and extract the two household files:

```bash
mkdir -p data/processed
7z x data/raw/R93.rar -odata/processed -y
7z x data/raw/U93.rar -odata/processed -y
```

Install the R packages:

```r
install.packages(c(
  "dplyr",
  "readxl",
  "openxlsx",
  "modelsummary",
  "labelled",
  "survey",
  "ggplot2",
  "flextable",
  "officer"
))
```

Run the analysis:

```r
source("code/Health_Expenditure_Analysis.R")
```

The script writes tables to `outputs/tables/` and the economic-quintile figure to `outputs/figures/`. It performs a final check that the expected output files exist and are non-empty.

## Automated workflow

GitHub Actions is configured to run when changes are pushed to `main`, when a pull request targets `main`, or when the workflow is manually dispatched.

The workflow checks out the repository, sets up R, extracts the household Excel files, inventories the original 1393 archive, audits household/medical-record coverage and candidate survey identifiers, installs the R dependencies, runs the analysis, validates the expected outputs, and uploads the generated `outputs/` directory as a workflow artifact.

The workflow also performs a schema-only inventory of the original Access database stored in `data/raw/93.rar`. It extracts the database into the runner's temporary directory, records table names, column definitions, and declared relationships with `mdbtools`, and removes the temporary extraction when the job ends. It does not export household-level records. The inventory is uploaded with the other diagnostic outputs for inspection.

The workflow is an execution check; a successful run does not by itself validate the underlying data definitions or research methodology. At the current audit stage, the household sample constructed after excluding missing food expenditure contains 38,189 observations (19,334 rural and 18,855 urban), two fewer urban observations than the published benchmark of 38,191 (19,334 rural and 18,857 urban). The script reports this discrepancy in `outputs/diagnostics/sample_benchmark_comparison.csv` and does not force the sample to match.

## Interpretation and limitations

- The estimates are conditional associations, not causal effects.
- CHE estimates depend on the threshold and the construction of subsistence expenditure and capacity to pay.
- Household survey estimates depend on the quality of the underlying survey variables, weights, and identifiers.
- The current survey-design declaration uses `ids = ~1` and household weights. Candidate fields `Fasl` and `block` have been audited, but their roles as strata, PSUs, or nested sampling identifiers are not confirmed. Standard errors therefore do not yet reflect a verified multistage design.
- The workflow resolves direct R package dependencies through `setup-r-dependencies` and caches them by dependency signature. It does not yet commit a permanent `renv.lock` file.
- The source variable definitions, expenditure annualization, OOP classification, item-specific CPI adjustment, household merges, and subsistence-expenditure calculation should be verified against the original survey documentation before the estimates are used in research conclusions.
- The published 2014 analytical sample in Yazdi-Feyzabadi et al. (2018) contains 38,191 households (19,334 rural and 18,857 urban). The current constructed sample contains 38,189 (19,334 rural and 18,855 urban); two urban observations remain unexplained.
- The script exports `che_benchmark_comparison.csv`, which compares the current weighted 2014 CHE headcount with the published 2014 estimates (3.15% overall, 4.38% rural, 2.69% urban). It also exports `che_specification_sensitivity.csv`, comparing the food-share and total-consumption reference groups and purchased-only versus all-recorded Table 6 numerators. The all-recorded numerator is diagnostic only, not an OOP measure. These are diagnostic comparisons, not pass/fail criteria; CPI treatment, numerator scope, and survey-design implementation must be reconciled before interpreting any gap.
- The current code should be treated as an evolving replication audit, not a validated reproduction of the published estimates.
- Health expenditure is annualized from the monthly Table 6 values, but it has not yet been deflated with the interview-month, item-specific CPI series used by the independent HEIS processing code. Do not interpret the current CHE estimates as final real-expenditure estimates.

## References\n\n- Ghiasvand, H. et al. (2015). “Catastrophic Health Expenditure Among Iranian Rural and Urban Households, 2013–2014.” *Iranian Red Crescent Medical Journal*. DOI: 10.5812/ircmj.30974.\n- Yazdi-Feyzabadi, V. et al. (2018). “Prevalence and intensity of catastrophic health care expenditures in Iran from 2008 to 2015.” *International Journal for Equity in Health*. DOI: 10.1186/s12939-018-0743-y.\n- Household Expenditure and Income Surveys of Iran, Chapter 1 (sample design and rotating-panel feature): https://m-hoseini.github.io/HEIS/introduction.html\n\n## Skills demonstrated

- R data management and validation
- Household survey data construction
- Survey-weighted descriptive analysis
- Survey-weighted logistic regression
- Subgroup, interaction, and sensitivity analysis
- Reproducible output generation
- Transparent documentation of empirical limitations
