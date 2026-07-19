# BLS 4.0 file format

Findings from inspecting the real distribution, since the layout is not documented online.
The ETL in `tools/etl/build_bls.mjs` depends on everything here.

## Download

`https://blsdb.de/assets/uploads/BLS_4_0_2025_DE.zip` — 14.3 MB, no registration, no token
required for the asset itself.

Contents:

| File | Size | Purpose |
|---|---|---|
| `BLS_4_0_Daten_2025_DE.xlsx` | 13.4 MB | The data: 1 header row + 7,140 food rows |
| `BLS_4_0_Components_DE_EN.xlsx` | 0.02 MB | Component legend: code, DE/EN name, unit, group, formula |
| `BLS_4_0_Dokumentation_DE.pdf` | 0.45 MB | Handbook |

## Data sheet layout

Sheet name `BLS_4_0_Daten_2025_DE`, **418 columns**, single header row.

| Column | Content |
|---|---|
| 1 | `BLS Code` — 7 chars, letter + 6 digits (e.g. `C131000`) |
| 2 | `Lebensmittelbezeichnung` — German name |
| 3 | `Food name` — English name |
| 4 … 417 | 138 nutrients × 3 columns: **value**, `Datenherkunft`, `Referenz` |
| 418 | `Hinweis` — note, usually empty |

Value columns are therefore `4 + 3n`. The header caption is `"<CODE> <German name> [<unit>/100g]"`,
so the component code is `caption.split(' ')[0]` — this is how columns are mapped, rather
than relying on fixed positions.

Component codes are standard **INFOODS tagnames**: `ENERCC` (kcal), `ENERCJ` (kJ),
`PROT625`, `FAT`, `CHO`, `SUGAR`, `STARCH`, `FIBT`, `FASAT`, `FAMS`, `FAPU`, `CHORL`,
`NACL`, `NA`, `K`, `CA`, `MG`, `FE`, `ZN`, `VITA`, `VITC`, `VITD`, `VITE`, `VITB12`,
`FOL`, `WATER`, `ALC`. All values are **per 100 g edible portion**.

Numbers arrive as JS numbers via exceljs — there is no German decimal-comma parsing problem.

## Missing values — the important part

Missing data is encoded as **sentinel strings inside the value column**, not as blanks.
A naive `parseFloat` would yield `NaN`, and a naive "is the cell empty" check finds almost
nothing. Census across all 138 × 7,140 = 985,320 value cells:

| Sentinel | Count | Share | Meaning | ETL mapping |
|---|---|---|---|---|
| `"-"` | 110,083 | 11.17% | Not determined | **`NULL`** |
| `"<LOD"` | 2,733 | 0.28% | Below limit of detection | `0.0` |
| `"TR"` | 1,806 | 0.18% | Trace | `0.0` |
| `"<LOQ"` | 746 | 0.08% | Below limit of quantification | `0.0` |
| `"<LOD or <LOQ"` | 392 | 0.04% | Below one of the above | `0.0` |
| *(empty cell)* | 59 | 0.01% | Not determined | **`NULL`** |

The `NULL` vs `0.0` distinction is the one that matters: "not determined" and "measured as
essentially zero" must never be conflated, or a food with unmeasured fat would display as
fat-free.

## Completeness of the nutrients we surface

| Component | Usable numbers | Coverage |
|---|---|---|
| `ENERCC`, `CHO`, `SUGAR`, `NACL` | 7,140 | 100.0% |
| `PROT625`, `FASAT` | 7,117 | 99.7% |
| `FAT`, `FE` | 7,112 | 99.6% |
| `WATER` | 7,096 | 99.4% |
| `FIBT` | 7,087 | 99.3% |
| `ALC` | 6,964 | 97.5% |
| `VITC` | 6,720 | 94.1% |

Every food has calories, and the four headline macros are ≥99.3% complete. This is why BLS
is the primary search source rather than a supplement.

## `Datenherkunft` (data origin)

Observed values: `Analyse`, `Literatur`, `Nährstoffdatenbank`, `Formelberechnung`,
`Aggregation`. Not surfaced in the UI for now, but worth keeping in mind — a recipe-computed
value is weaker evidence than a lab analysis.

## BLS code groups

The leading letter is the food group. Distribution across 7,140 foods:

| | | | | | |
|---|---|---|---|---|---|
| `B` Brot (186) | `C` Getreide (231) | `D` Backwaren (466) | `E` Teigwaren (104) | `F` Obst (275) | `G` Gemüse (560) |
| `H` Sprossen/Pilze (142) | `K` Stärke (157) | `M` Milch/Käse (279) | `N` Kaffee/Tee (114) | `P` Alkoholika (119) | `Q` Öle/Fette (65) |
| `R` Gewürze/Salz (97) | `S` Süßwaren (253) | `T` Fisch (520) | `U` Schwein (685) | `V` sonst. Fleisch (462) | `W` Speck/Wurst (375) |
| `X` Gerichte (1,165) | `Y` Suppen/Brühen (885) | | | | |

`X` and `Y` are prepared dishes and soups — 2,050 rows, over a quarter of the database, and
directly useful for logging home-cooked meals.

## License

CC BY 4.0. Attribution is mandatory — see `README.md` for the required citation string.
