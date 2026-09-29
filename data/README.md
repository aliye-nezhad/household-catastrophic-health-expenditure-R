# Raw Data

This folder contains the original input files required for the household
catastrophic health expenditure analysis.

The analysis uses Iranian household survey data and combines household-level
information with health expenditure records to construct the analytical
dataset.

## Required Files

| File | Description |
| --- | --- |
| `R93.rar` | Raw household survey data archive |
| `U93.rar` | Raw household survey data archive |
| `R93P3S06.rds` | Household expenditure-related data component |
| `U93P3S06.rds` | Household expenditure-related data component |

## Data Processing

The R workflow imports and processes these files to construct the household-level
analytical dataset used for:

- catastrophic health expenditure measurement
- capacity-to-pay calculation
- survey-weighted regression analysis
- robustness and sensitivity analyses

## Reproducibility Note

The raw files are preserved with their original filenames because the analysis
workflow expects these file names during import.

The processed analytical dataset and generated outputs are created by the R
workflow and are stored separately from the raw input files.
