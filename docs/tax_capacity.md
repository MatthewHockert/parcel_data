# Estimating net tax capacity

**Warning: one year's class rates for every year.** `estimate_tax_cap()` prices every parcel with Hennepin County's class rate table for the **2025 assessment (taxes payable 2026)**. Minnesota changes class rates and tier limits over time, so a 2010 parcel is priced at 2025 rates. Only the homestead market value exclusion follows the year. Use the estimate to fill gaps, for example Ramsey, whose published `tax_capac` is 0 for 2005-2020 and blank for 2021 (see `docs/known_gaps.csv`). Where a county published `tax_capac`, prefer it.

## Use

```r
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
p <- read_parcels(2005:2020, "Ramsey", cols = c("pin", "use_class1", "homestead", "emv_total"))
p <- estimate_tax_cap(p)   # adds prop_type, homestead_status, payable_year, tmv_est, tax_capac_est
```

```python
from read_parcels import read_parcels, estimate_tax_cap
p = estimate_tax_cap(read_parcels(list(range(2005, 2021)), "Ramsey",
                                  cols=["pin", "use_class1", "homestead", "emv_total"]))
```

`homestead_exclusion = FALSE` skips step 4 below. `value =` picks another value column.

## Steps

1. **Property type.** `use_class1` is looked up in `docs/use_class_map.csv`, which maps each county's labels to a property type in the rate table. Labels no rule covers get no estimate.
2. **Homestead.** `Y`, `Yes`, `1` are homestead. `P`, `Fractional` are partial homesteads, priced as homestead. `N`, `No`, `0` are non-homestead. Anything else (Washington's codes 2, 3, 5, 7, 9, or blank) is unknown and priced as non-homestead.
3. **Payable year.** The taxes-payable year the market value is for: the file year for Hennepin and Ramsey, the file year plus one for the other counties. Found by fitting each county's published `tax_capac` (below). The files' `tax_year` field is not used, because Anoka's 2024 file says 2024 while its values fit payable 2025.
4. **Taxable market value.** Market value (`emv_total`) less the homestead market value exclusion in force for that payable year, for homesteaded class 1a and 1b property and the farm house (FF) (Minn. Stat. 273.13, subd. 35):
   - payable 2011 and earlier: none (the homestead credit then was a credit against tax, not part of tax capacity)
   - payable 2012-2024: 40% of value up to $76,000, then $30,400 less 9% of the value above $76,000, zero from $413,800
   - payable 2025 on: 40% up to $95,000, then $38,000 less 9% above $95,000, zero from $517,200

   Farms (F, FP) get no exclusion.
5. **Tax capacity by tier.** Homestead: the first `limit_bdp` at the blind/disabled rate, the next `limit_base1` at the base rate, the rest at the over-base rate. Non-homestead: the first `limit_base1` at the base rate, the rest at the over-base rate. Exempt property is 0.

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

`code/15_check_tax_cap.R` compares the estimate with every county-year that published `tax_capac`, written to `docs/tax_capacity_check.csv`. Exempt parcels and parcels with no published value are left out. Dakota and Carver publish `tax_capac` one year behind their market value, so their file-t `tax_capac` is compared with the estimate from file t-1.

Median across each county's years:

| County | Years | Within 1% | Homestead residential within 1% | Total estimate / published | Commercial-industrial estimate / published |
|---|---|---|---|---|---|
| Hennepin | 2006-2025 | 93.1% | 98.0% | 0.987 | 1.000 |
| Anoka | 2006-2025 | 90.2% | 98.4% | 0.950 | 1.000 |
| Washington | 2012-2025 | 89.0% | 93.0% | 1.012 | 1.000 |
| Dakota | 2006-2025 | 87.2% | 96.0% | 1.116 | 1.558 |
| Carver | 2006-2025 | 85.8% | 96.3% | 1.088 | 1.561 |
| Ramsey | 2022-2025 | 9.0% | 6.0% | 0.780 | 0.972 |

Scott publishes no usable `tax_capac` in any year, so it has no check.

## Why counties differ

What was found when Dakota and Carver first came out loose (2026-11-11), in order of size:

1. **Homestead exclusion by year.** The first version applied the payable-2025 exclusion to every year. Payable 2012-2024 used the smaller $76,000 / $413,800 exclusion, and payable 2011 and earlier had none. With the year-specific exclusion, homestead residential matches within 1% for 93-98% of parcels in every county with published values.
2. **Value timing.** Each county's file pairs a market value with a different taxes-payable year (step 3). Dakota and Carver also publish `tax_capac` one year behind their value.
3. **Farm homesteads.** The first version applied the homestead exclusion to whole farms. It now applies only to the farm house (FF).
4. **Fiscal disparities (not fixed).** Dakota (2012 on), Carver (2010 on) and Anoka (2018-2020) publish commercial-industrial `tax_capac` about one third lower than the class rates give, a tight ratio of about 1.55 across parcels. That fits the tax capacity left after each parcel's contribution to the metro fiscal disparities pool. The estimate is gross tax capacity, the same as Hennepin's published figure. This is why Dakota's and Carver's totals run 9-12% high.
5. **Dakota exempt parcels.** About 7,000 Dakota parcels labelled "Exempt" (`tax_exempt` = Y) carry a published `tax_capac` above 0 at a 2% rate. The estimate gives them 0, and the check leaves them out.
6. **Suspect published values.** Ramsey's published `tax_capac` for 2022-2025 does not behave like net tax capacity. In 2022 a $181,900 homestead shows 3,470, about twice the class-rate value, and no pairing of years or exclusion fits. Carver's 2018, 2020 and 2021 files fit no pairing either. Treat those published values with caution.
7. **Early years (not fixed).** Hennepin 2006-2008 match less well (53-81% within 1%). This is likely limited market value, which capped taxable value growth until it was repealed for the 2009 assessment and is not in the parcel files.
