# 1393 HEIS inputs

The Household Expenditure and Income Survey was collected by the Statistical Center of Iran. The 1393 round spans 2014–15. The pipeline uses the five frozen inputs below and verifies their SHA-256 hashes against `data/raw.sha256`. [HEIS documentation](https://m-hoseini.github.io/HEIS/introduction.html)

| File under `data/raw/` | Role |
| --- | --- |
| `R93.rar`, `U93.rar` | Rural and urban household summary workbooks. The analysis uses `ADDRESS`, demographic fields, `GHazineh`, `VKhorak`, `C11`, `C11New` and `weight`. |
| `R93P3S06.rds`, `U93P3S06.rds` | Rural and urban Table 6 medical records. `DYCOL01` is the item code, `DYCOL02` is the acquisition method and `DYCOL03` is the monthly amount. |
| `93.rar` | Original Access database containing the Table 6 medical records and `MahMorajeh`, the household interview month. |

The Access audit compares the entire four-field Table 6 record multiset against the RDS files and verifies the interview-month link for households and medical records. The RDS files store item codes numerically, so the comparison normalizes the Access text codes before sorting. Private temporary directories hold the extracted workbooks, database and record-level audit files during each run. The results contain aggregate tables and database metadata.

The nominal analysis uses the workbooks' household expenditure totals and the committed medical extracts. The 1393 item-to-CPI crosswalk, monthly item price indices and official design identifiers are outstanding inputs for the price and variance comparisons. [Hoseini's processing notes](https://m-hoseini.github.io/HEIS/cleaning-data.html)
