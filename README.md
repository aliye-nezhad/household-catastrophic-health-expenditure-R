# Determinants of Household Catastrophic Health Expenditure

## Overview

This repository implements a reproducible R workflow for constructing household-level catastrophic health expenditure measures from Iranian household survey data, following the Xu et al. (2003) methodology, estimating survey-weighted logistic regression models, conducting subgroup and robustness analyses, and exporting tables and figures in a reviewer-friendly structure.

The project is presented as an applied microeconometrics and R coding sample. Its regression estimates describe conditional associations between household characteristics and catastrophic health expenditure and should not be interpreted as causal effects.

## Research Question

How are household socioeconomic and demographic characteristics associated with catastrophic health expenditure among Iranian households?

## Data

The workflow uses household survey data containing household demographic characteristics, expenditure information, health-related out-of-pocket expenditure, and sampling weights.

| Variable | Description | Role |
| --- | --- | --- |
| `catastrophic_health_expenditure` | Catastrophic health expenditure indicator | Dependent variable |
| `annual_health_expenditure` | Household annual out-of-pocket health expenditure | Health expenditure measure |
| `capacity_to_pay` | Household capacity to pay after subsistence needs | CHE denominator |
| `income_rank` | Household economic position indicator | Main socioeconomic variable |
| `residence_type` | Urban/rural residence classification | Household characteristic |
| `household_size` | Number of household members | Household characteristic |
| `age` | Age of household head | Demographic characteristic |
| `gender` | Gender of household head | Demographic characteristic |
| `literacy` | Literacy status of household head | Demographic characteristic |

The analytical dataset is constructed through:

- importing household survey tables and supporting files;
- validating and cleaning variables;
- aggregating household health expenditure;
- merging household-level information; and
- constructing demographic, socioeconomic, and expenditure indicators.

## Catastrophic Health Expenditure Construction

The workflow follows the catastrophic health expenditure methodology developed by Xu et al. (2003).

Capacity to pay is defined as:

```text
CTP = Total Expenditure - Subsistence Expenditure
```

The baseline catastrophic health expenditure indicator is:

```text
CHE = 1 if OOP / CTP >= 40%
CHE = 0 otherwise
```

The baseline specification uses the 40% threshold following Xu et al. (2003). Additional threshold specifications of 30% and 50% are estimated as sensitivity analyses.

## Empirical Workflow

The R script performs:

- household survey-data import and validation;
- construction of health expenditure measures;
- calculation of subsistence expenditure and capacity to pay;
- creation of catastrophic health expenditure indicators;
- survey-design declaration using sampling weights;
- weighted descriptive analysis;
- survey-weighted logistic regression estimation;
- odds-ratio calculation and regression output export;
- urban household robustness analysis;
- large household robustness analysis;
- province fixed-effects estimation;
- income-residence interaction analysis; and
- alternative CHE threshold sensitivity analysis.

## Repository Structure

```text
household-catastrophic-health-expenditure-R/
│
├── README.md
├── LICENSE
├── .gitignore
│
├── code/
│   └── Health_Expenditure_Analysis.R
│
├── data/
│   ├── README.md
│   └── raw/
│       ├── README.md
│       ├── R93.rar
│       ├── U93.rar
│       ├── R93P3S06.rds
│       └── U93P3S06.rds
│
└── outputs/
    ├── figures/
    │   └── Figure1_CHE_income_quintile.png
    │
    └── tables/
        ├── summary_statistics.xlsx
        ├── regression_results.docx
        ├── model_comparison.docx
        ├── CHE_final_regression_table.docx
        ├── Table_CHE_by_income_quintile.csv
        └── marginal_effects.csv
```

## Requirements

The code requires:

- R 4.2 or newer;
- dplyr;
- readxl;
- labelled;
- survey;
- ggplot2;
- modelsummary;
- RODBC;
- openxlsx.

The workflow requires access to the original household survey files and an appropriate Access database driver for importing the source data.

## Reproduction

Run the analysis from the repository root:

```r
source("code/Health_Expenditure_Analysis.R")
```

The script constructs the analytical dataset, estimates survey-weighted models, performs robustness and sensitivity analyses, and exports tables and figures to the output folders.

## Output Guide

| Location | Contents |
| --- | --- |
| `outputs/figures/` | Catastrophic health expenditure prevalence by income quintile |
| `outputs/tables/` | Descriptive statistics, regression results, subgroup analyses, province specifications, interaction models, and CHE threshold sensitivity results |

## Interpretation and Limitations

This project estimates conditional associations and is presented as an applied microeconometrics coding sample rather than a causal research design.

Important limitations include:

- catastrophic health expenditure estimates depend on methodological choices such as thresholds and subsistence expenditure definitions;
- household survey measures depend on sampling and reporting procedures;
- alternative specifications may produce different numerical estimates;
- survey-weighted models account for sampling design but do not eliminate all sources of bias; and
- the analysis does not identify causal effects of socioeconomic characteristics on health expenditure outcomes.

## Skills Demonstrated

- R data management and validation;
- household survey data construction;
- applied microeconometric analysis;
- survey-weighted regression methods;
- subgroup, robustness, and sensitivity analysis;
- reproducible output generation; and
- transparent documentation of empirical limitations.

## Author

Aliye Nezhad

## License

The code and documentation are released under the MIT License.
