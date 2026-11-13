# Household Catastrophic Health Expenditure in Iran

This project examines the incidence of catastrophic health expenditure in Iran using the 1393 Household Expenditure and Income Survey (2014–15). The analysis links rural and urban household workbooks to the survey's Table 6 medical-expenditure records and covers 38,189 households.

## Data and sample

The analysis uses five source files from the 1393 survey:

- `R93.rar` and `U93.rar`: rural and urban household workbooks.
- `R93P3S06.rds` and `U93P3S06.rds`: rural and urban Table 6 medical records.
- `93.rar`: the original Access database, including the Table 6 records and the household interview-month field.

The two medical extracts match all 68,217 Table 6 records in the original Access database on household identifier, item code, acquisition method, and amount. The Access database also provides interview-month information for the workbook households and medical records. The reproduction workflow checks these links and reports aggregate counts; record-level Access exports are kept in temporary storage. [Data notes](data/README.md)

The household workbooks contain 38,275 records. Eighty-six households are excluded because food expenditure is missing, leaving 38,189 households in the analytical sample. Households without a Table 6 entry remain in the sample with zero recorded expenditure in that module, following the survey-processing convention.

| Field | Use in the analysis |
| --- | --- |
| Table 6 medical records | Monthly medical expenditure by item and acquisition method |
| `GHazineh` and `VKhorak` | Total and food expenditure, treated as annual amounts |
| `C11` | Main economic-rank field, recorded in ten categories |
| `C11New` | Alternative rank field examined in the source-data audit |
| `C01`, `A01`, `A02`, and `A03` | Household size and the gender, age, and literacy of the household head |
| `weight` | Household sampling weight |

The original codebook definition of `C11` and `C11New` has not been established. The analysis therefore uses the neutral label *economic rank* rather than assuming that either field ranks income or expenditure.

## Measuring catastrophic health expenditure

The main out-of-pocket measure includes purchased medical items (`DYCOL02 = 1)). Table 6 amounts are monthly, so they are multiplied by 12 to match the annual household expenditure measures. A separate sensitivity comparison includes all recorded acquisition methods, including noncash methods.

Household size is adjusted using the equivalence scale:

\[
\text{equivalence size}=\text{household size}^{0.56}.
\]

The primary subsistence line is estimated separately for rural and urban households. It is the survey-weighted mean of equivalized food expenditure among households whose food-expenditure share is strictly between 45% and 55% of total expenditure. Household-specific subsistence expenditure is obtained by multiplying this line by the household equivalence size.

Capacity to pay is total expenditure less the smaller of observed food expenditure and adjusted subsistence expenditure:

\[
\text{capacity to pay}
=\text{total expenditure}
-\min(\text{food expenditure},\text{subsistence expenditure}).
\]

A household is classified as facing catastrophic health expenditure when annual out-of-pocket medical expenditure is at least 40% of capacity to pay. The analysis also evaluates 30% and 50% thresholds. An alternative subsistence line uses the weighted mean of equivalized food expenditure among households between the 45th and 55th percentiles of total expenditure. [Xu et al. (2003)](https://doi.org/10.1016/S0140-6736(03)13861-5) · [Yazdi-Feyzabadi et al. (2018)](https://doi.org/10.1186/s12939-018-0743-y) · [Ghiasvand et al. (2015)](https://doi.org/10.5812/ircmj.30974)

## Empirical approach

The baseline model is a household-weighted logistic regression of catastrophic health expenditure on economic rank, residence, household size, and the age, gender, and literacy of the household head. The estimates describe conditional associations, not causal effects.

Additional specifications examine the urban subsample, province fixed effects, and the interaction between economic rank and residence. The analysis also estimates models at the 30% and 50% thresholds. For households with more than six members, case counts are reported by economic rank because some groups contain few or no catastrophic-expenditure cases.

The baseline variance calculation uses household weights and treats households as independent sampling units. A separate sensitivity calculation clusters standard errors by province. Full survey-design variance estimation requires the original strata and primary sampling-unit identifiers, which are not available in the source files used here.

## Results and limitations

At the 40% threshold, estimated weighted prevalence is 1.79% nationally, 2.50% in rural areas, and 1.54% in urban areas.

| Residence | Households | Estimated weighted prevalence | Published 2014 benchmark |
| --- | ---: | ---: | ---: |
| All | 38,189 | 1.79% | 3.15% |
| Rural | 19,334 | 2.50% | 4.38% |
| Urban | 18,855 | 1.54% | 2.69% |

The weighted monthly averages for total and food expenditure agree with the published figures at their reported precision. Out-of-pocket spending and the estimated subsistence line differ, and the published sample contains two more urban households. These estimates use nominal expenditure amounts. An item-level price adjustment requires the 1393 item-to-CPI crosswalk and monthly item price indices. Differences in the out-of-pocket measure and survey-design treatment also matter when comparing the estimates with published results. [Published comparison, Tables 1–3](https://doi.org/10.1186/s12939-018-0743-y) · [HEIS processing notes](https://m-hoseini.github.io/HEIS/cleaning-data.html) · [HEIS sample design](https://m-hoseini.github.io/HEIS/introduction.html)

## Repository structure

```text
├── .github/
│   ├── scripts/
│   │   ├── audit_access_database.sh
│   │   └── reproduce.sh
│   └── workflows/
│       └── r-reproducibility.yml
├── code/
│   ├── Health_Expenditure_Analysis.R
│   ├── audit_source_data.R
│   └── validate_reproduction.R
├── data/
│   ├── raw/
│   ├── raw.sha256
│   └── README.md
├── outputs/
│   ├── diagnostics/
│   ├── figures/
│   ├── tables/
│   └── README.md
├── LICENSE
├── pixi.lock
└── pixi.toml
```

## Reproducing the analysis

The project uses Pixi 0.84.2 or later on x86-64 Linux. On Windows, run the commands inside WSL2. The Pixi manifest and lockfile specify R 4.4.3 and the required packages and system dependencies. The first run downloads the locked environment from conda-forge. [Pixi releases](https://github.com/prefix-dev/pixi/releases)

```bash
git clone https://github.com/aliye-nezhad/household-catastrophic-health-expenditure-R.git
cd household-catastrophic-health-expenditure-R
pixi run --locked reproduce
```

The reproduction task performs the following checks and steps:

1. Verifies the raw survey files against `data/raw.sha256` and records the input and lockfile hashes.
2. Extracts the rural and urban workbooks and inventories the original Access database.
3. Audits the interview-month links and compares the Table 6 records in the RDS extracts with the original Access records.
4. Runs the main R analysis in the locked Pixi environment.
5. Checks that required tables, diagnostics, and the figure exist and are non-empty, and verifies that the summary workbook can be read.
6. Runs a separate validation script that checks the source-data linkage, sample counts, key CHE estimates, quintile results, regression output, inference diagnostics, Word tables, and PNG figure against reference results.

Each successful run writes a fresh set of results to `reproduced/run-*/`. The GitHub Actions workflow runs the same locked reproduction task on Ubuntu 24.04 and uploads the resulting files as a workflow artifact.

The committed files under `outputs/` are a historical results snapshot associated with analysis version [`e9499c5`](https://github.com/aliye-nezhad/household-catastrophic-health-expenditure-R/commit/e9499c5393662f50ba5378baa2ffaf3dcd025819). They are retained for reference and should not be mistaken for fresh outputs from the current `main` version. Use the results generated under `reproduced/run-*/` when checking the current analysis. [Results guide](outputs/README.md)

## Author

Aliye Nezhad

## License

The analysis code and project documentation are available under the [MIT License](LICENSE). The [data notes](data/README.md) describe the survey sources.
