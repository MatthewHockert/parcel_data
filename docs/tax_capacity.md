# Estimating net tax capacity

**Warning: one year's law for every year.** `estimate_tax_cap()` prices every parcel with Hennepin County's class rate table for the **2025 assessment (taxes payable 2026)**. Minnesota changes class rates, tier limits and the homestead market value exclusion over time, so a 2010 parcel is priced as if 2025 law applied. Use the estimate to fill gaps, for example Ramsey, whose published `tax_capac` is 0 for 2005-2020 and blank for 2021 (see `docs/known_gaps.csv`). Where a county published `tax_capac`, prefer it.

## Use

```r
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
p <- read_parcels(2005:2020, "Ramsey", cols = c("pin", "use_class1", "homestead", "emv_total"))
p <- estimate_tax_cap(p)   # adds prop_type, homestead_status, tmv_est, tax_capac_est
```

```python
from read_parcels import read_parcels, estimate_tax_cap
p = estimate_tax_cap(read_parcels(list(range(2005, 2021)), "Ramsey",
                                  cols=["pin", "use_class1", "homestead", "emv_total"]))
```

`homestead_exclusion = FALSE` skips step 3 below. `value =` picks another value column.

## Steps

1. **Property type.** `use_class1` is looked up in `docs/use_class_map.csv`, which maps each county's labels to a property type in the rate table. Labels no rule covers get no estimate.
2. **Homestead.** `Y`, `Yes`, `1` are homestead. `P`, `Fractional` are partial homesteads, priced as homestead. `N`, `No`, `0` are non-homestead. Anything else (Washington's codes 2, 3, 5, 7, 9, or blank) is unknown and priced as non-homestead.
3. **Taxable market value.** Market value (`emv_total`) less the homestead market value exclusion for homesteaded class 1a, 1b and 2a house property: 40% of value up to $95,000, then $38,000 less 9% of the value above $95,000, zero from $517,200 (Minn. Stat. 273.13, subd. 35). These are the parameters in force for the 2025 assessment.
4. **Tax capacity by tier.** Homestead: the first `limit_bdp` at the blind/disabled rate, the next `limit_base1` at the base rate, the rest at the over-base rate. Non-homestead: the first `limit_base1` at the base rate, the rest at the over-base rate. Exempt property is 0.

## Files

| File | What it is | Made by |
|---|---|---|
| `docs/class_rates_hennepin_2025.csv` | Hennepin County "Property Types, State Class Codes, Prism Codes & Rates" (Report T99SS01, 2025 Assessment, Taxes Payable 2026, dated 06/30/25), transcribed by hand, every row and footnote marker. One row added: `EX`, exempt, rate 0. | Hand transcription of https://www.hennepincounty.gov/-/media/hennepinus/residents/property/taxing-district-information/2026-values-properties-types.pdf |
| `docs/use_class_map.csv` | Each county's `use_class1` label mapped to a property type, with the rule that matched and the parcel count | `code/14_use_class_map.py` (keyword rules, a judgment call: review before relying on a county) |
| `docs/known_gaps.csv` | Every published column that is entirely blank or zero in a year and county | `code/13_known_gaps.py` |

Source footnotes not modelled: commercial and industrial contiguity (note 7), the state general tax rules (notes 1-6), the 3.8M farm limit across linked PIDs (note 8), machinery value for utilities, and the referendum market value exclusions. They change the state general tax and referendum levies, not net tax capacity, except note 7.

## Mapping coverage

Share of parcel-years with a mapped property type: Hennepin 99.95%, Dakota 99.96%, Scott 99.6%, Ramsey 99.5%, Carver 99.4%, Washington 99.3%, Anoka 95.4%. Anoka's 2005 file uses bare four-digit codes that never appear with a label, so they stay unmapped.

## Check against published tax capacity

Parcels with a published `tax_capac` above 0 and an estimate (2026-11-11):

| File year | County | Priced | Within 1% | Within 5% | Total estimate / published |
|---|---|---|---|---|---|
| 2025 | Hennepin | 98.8% | 94.7% | 95.7% | 0.993 |
| 2025 | Hennepin, no homestead exclusion | 98.8% | 46.0% | 67.0% | 1.007 |
| 2024 | Hennepin | 98.9% | 44.1% | 90.2% | 0.981 |
| 2015 | Hennepin | 99.0% | 28.3% | 60.4% | 0.971 |
| 2024 | Anoka | 98.5% | 90.1% | 91.5% | 0.992 |
| 2024 | Dakota | 95.9% | 12.7% | 62.8% | 1.009 |
| 2024 | Carver | 97.9% | 26.5% | 75.2% | 1.118 |

The 2025 Hennepin match confirms the table and the exclusion. Earlier years drift as the law changed (2015 is 2.9% low in total). Dakota is right in total but loose parcel by parcel, and Carver is 12% high, so check those counties' mapping and value timing before using their estimates.
