# 1393 household survey data

The Statistical Center of Iran collected the Household Expenditure and Income Survey. The analysis uses five files from the 1393 round (2014–15). [Survey background](https://m-hoseini.github.io/HEIS/introduction.html)

| File under `data/raw/` | Role |
| --- | --- |
| `R93.rar`, `U93.rar` | Rural and urban household summary workbooks with household identifiers, demographics, total and food expenditure, economic rank, and sampling weights. |
| `R93P3S06.rds`, `U93P3S06.rds` | Rural and urban Table 6 medical records. `DYCOL01` is the item code, `DYCOL02` is the acquisition method and `DYCOL03` is the monthly amount. |
| `93.rar` | Original Access database containing the Table 6 medical records and `MahMorajeh`, the household interview month. |

The two medical extracts match all 68,217 Table 6 records in the Access archive on household identifier, item code, acquisition method, and amount. The comparison converts the original item codes to the numeric form used in the extracts. The archive also links the interview month to every household in the workbooks and to every medical record. [Linkage counts](../outputs/diagnostics/access_linkage.csv)

The extracted workbooks, Access database, and record-level linkage files are used in a temporary directory. The linkage table reports aggregate counts. The survey archives and extracts can be checked against their recorded hashes. [SHA-256 hashes](raw.sha256)

The estimates use nominal expenditure amounts. An item-level price adjustment requires the 1393 item-to-CPI crosswalk and monthly item price indices. The official strata and primary sampling-unit identifiers are needed for full survey-design variance estimation. [Survey processing notes](https://m-hoseini.github.io/HEIS/cleaning-data.html)
