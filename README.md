# Household Catastrophic Health Expenditure in Iran

How common is catastrophic health spending in Iran, and how does it vary with household economic rank, place of residence, and demographics? I use the 1393 Household Expenditure and Income Survey (2014–15) to study this question across 38,189 households.

## Data

I link medical spending records from Table 6 of the survey to the rural and urban household workbooks. The two extracts match 68,217 records in the original Access database. Households without a Table 6 entry stay in the sample with zero recorded spending in that module. Of the 38,275 households in the workbooks, 86 are excluded because their food expenditure is missing. [Data notes](data/README.md)

| Field | Use in the analysis |
| --- | --- |
| Table 6 medical records | Monthly spending on purchased medical items |
| `GHazineh` and `VKhorak` | Total and food expenditure, treated as annual amounts |
| `C11` | Economic rank in ten categories |
| `C01`, `A01`, `A02`, and `A03` | Household size and the gender, age, and literacy of the household head |
| `weight` | Household sampling weight |

The original definition of `C11` is uncertain, so I use the label economic rank.

## Measuring catastrophic expenditure

The out-of-pocket measure includes purchased medical items (`DYCOL02 = 1`). I multiply monthly amounts by 12 to put them on the same basis as household expenditure. Capacity to pay is total spending less the smaller of actual food expenditure and estimated subsistence expenditure. A household is classified as facing catastrophic expenditure when its out-of-pocket spending reaches **40%** of its capacity to pay. [Xu et al. (2003)](https://doi.org/10.1016/S0140-6736(03)13861-5)

I estimate subsistence spending separately for rural and urban households. Within each group, the subsistence line is the weighted mean of equivalized food spending among households that spend strictly between 45% and 55% of their total expenditure on food. Food spending is equivalized by dividing by household size raised to 0.56. Multiplying that line by each household's equivalence factor gives its subsistence expenditure. [Yazdi-Feyzabadi et al. (2018)](https://doi.org/10.1186/s12939-018-0743-y)

## Empirical approach

The main specification is a survey-weighted logistic regression with economic rank, residence, household size, and the age, gender, and literacy of the household head. The estimates describe conditional associations. The additional specifications use the urban subsample, province fixed effects, and an interaction between economic rank and residence. For larger households, the results give outcome counts by rank because some groups have few cases.

I check thresholds of 30% and 50% and estimate an alternative subsistence line using households in the 45th–55th percentile of total expenditure. [Ghiasvand et al. (2015)](https://doi.org/10.5812/ircmj.30974)

A separate comparison shows how the estimate changes when it includes medical items acquired through noncash methods.

## Results and limitations

At the 40% threshold, **1.79%** of households face catastrophic expenditure in the nominal analysis. The weighted share is higher in rural areas.

| Residence | Households | Estimated share | Published 2014 share |
| --- | ---: | ---: | ---: |
| All | 38,189 | 1.79% | 3.15% |
| Rural | 19,334 | 2.50% | 4.38% |
| Urban | 18,855 | 1.54% | 2.69% |

The weighted monthly averages for total and food expenditure agree with the published figures at their reported precision. Out-of-pocket spending and the estimated subsistence line differ. The published sample also includes two more urban households. An item-level price adjustment requires the 1393 item-to-CPI crosswalk and monthly price indices. [Published comparison, Tables 1–3](https://doi.org/10.1186/s12939-018-0743-y) · [HEIS processing notes](https://m-hoseini.github.io/HEIS/cleaning-data.html)

The baseline uses household weights and treats households as independent sampling units. A separate calculation clusters standard errors by province to show how inference changes. Estimating variance for the full survey design requires the original strata and primary sampling-unit identifiers. [HEIS sample design](https://m-hoseini.github.io/HEIS/introduction.html)

## Repository structure

| Path | Contents |
| --- | --- |
| [`code/`](code) | [Main R analysis](code/Health_Expenditure_Analysis.R), [source-data checks](code/audit_source_data.R), and [result validation](code/validate_reproduction.R). |
| [`data/`](data) | [1393 survey files](data/raw), [source notes](data/README.md), and [input hashes](data/raw.sha256). |
| [`outputs/`](outputs) | Saved results and the [guide to the output files](outputs/README.md). |
| [`outputs/tables/`](outputs/tables) | Sample statistics, regression tables, and coefficient estimates. |
| [`outputs/figures/`](outputs/figures) | Catastrophic expenditure prevalence by economic rank. |
| [`outputs/diagnostics/`](outputs/diagnostics) | Survey linkage checks, published comparisons, and sensitivity results. |
| [`pixi.toml`](pixi.toml) and [`pixi.lock`](pixi.lock) | The reproduction command and locked R environment. |
| [`.github/`](.github) | Repository workflow and run helpers. |

## Reproducing the results

Install Pixi 0.84.2 or later on x86-64 Linux. On Windows, run the commands inside WSL2. The source files are included and the lockfile specifies R 4.4.3 and the required packages. The first run downloads the environment from conda-forge. [Pixi releases](https://github.com/prefix-dev/pixi/releases)

```bash
git clone https://github.com/aliye-nezhad/household-catastrophic-health-expenditure-R.git
cd household-catastrophic-health-expenditure-R
pixi run --locked reproduce
```

The command prints the path to the full results under `reproduced/run-*/`. For the results in this repository, start with the [sample workbook](outputs/tables/summary_statistics.xlsx), [main regression](outputs/tables/regression_results.docx), and [economic-rank figure](outputs/figures/figure1_economic_quintile_CHE.png). The [results guide](outputs/README.md) links the coefficient estimates, sensitivity tables, and published comparison.

## Author

Aliye Nezhad

## License

The analysis code and project documentation are available under the [MIT License](LICENSE). The [data notes](data/README.md) describe the survey sources.
