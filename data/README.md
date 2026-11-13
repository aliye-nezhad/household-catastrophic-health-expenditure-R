# 1393 household survey data

The Statistical Center of Iran collected the Household Expenditure and Income Survey (HEIS). The analysis uses five files from the 1393 round (2014–15). [Survey background](https://m-hoseini.github.io/HEIS/introduction.html)

| File under `data/raw/` | Role |
| --- | --- |
| `R93.rar`, `U93.rar` | Rural and urban household summary workbooks with household identifiers, demographics, total and food expenditure, economic-rank fields, and sampling weights. |
| `R93P3S06.rds`, `U93P3S06.rds` | Rural and urban Table 6 medical records. `DYCOL01` is the item code, `DYCOL02` is the acquisition method, and `DYCOL03` is the monthly amount. |
| `93.rar` | Original Access database containing the Table 6 medical records and `MahMorajeh`, the household interview month. |

The two medical extracts match all 68,217 Table 6 records in the Access archive on household identifier, item code, acquisition method, and amount. The comparison standardizes the original item codes to the numeric representation used in the RDS extracts before checking the sorted records. The Access database also provides a valid interview month for all 38,275 households in the rural and urban workbooks and all 68,217 medical records. The audit checks the relationship between each household's interview month and its recorded survey quarter. [Aggregate linkage counts](../outputs/diagnostics/access_linkage.csv)

The reproduction workflow verifies the five source files against the SHA-256 values in [`raw.sha256`](raw.sha256) before extracting or analyzing them. It also records the input hashes and the Pixi lockfile hash in the run diagnostics. The household workbooks, extracted Access database, and record-level Access exports used for linkage checks are handled in temporary storage. The published diagnostics report aggregate counts and comparisons rather than the temporary household-level linkage files.

The estimates use nominal expenditure amounts. An item-level price adjustment requires the 1393 item-to-CPI crosswalk and monthly item price indices. Full survey-design variance estimation also requires the official strata and primary sampling-unit identifiers. [HEIS processing notes](https://m-hoseini.github.io/HEIS/cleaning-data.html) · [HEIS sample design](https://m-hoseini.github.io/HEIS/introduction.html)
