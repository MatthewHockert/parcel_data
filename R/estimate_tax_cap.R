## estimate_tax_cap(x): estimate each parcel's net tax capacity from its market value,
## property type and homestead status, using ONE year's class rates for every year.
##   p <- read_parcels(2005:2020, "Ramsey", cols = c("pin", "use_class1", "homestead", "emv_total"))
##   p <- estimate_tax_cap(p)   # adds prop_type, homestead_status, payable_year, tmv_est, tax_capac_est
##
## WARNING: the class rates are Hennepin County's table for the 2025 assessment (taxes
## payable 2026, docs/class_rates_hennepin_2025.csv), applied to every year. Minnesota
## changes class rates and tier limits over time, so earlier years are priced at 2025
## rates. Only the homestead exclusion follows the year (step 4). Use it to fill gaps (e.g. Ramsey, whose tax_capac is 0 for 2005-2020),
## not as the county's own figure. Where the county published tax_capac, prefer it.
##
## Steps, per parcel:
##   1. prop_type: use_class1 looked up in docs/use_class_map.csv (code/14_use_class_map.py).
##      Unmapped labels get NA.
##   2. homestead_status: Y / Yes / 1 = homestead, P / Fractional = partial (priced as
##      homestead), N / No / 0 = non-homestead, anything else = unknown (priced as
##      non-homestead).
##   3. payable_year: the taxes-payable year the parcel's market value is for, the file
##      year plus the county's offset: 0 for Hennepin and Ramsey (the value is for that
##      year's taxes), 1 for the others (the value is for the next year's taxes). Offsets
##      found by fitting the counties' published tax_capac (docs/tax_capacity.md). The
##      files' tax_year field is not used: Anoka's 2024 file says 2024, its values fit 2025.
##   4. tmv_est: taxable market value. Market value (emv_total) less the homestead market
##      value exclusion in force for payable_year, for homesteaded class 1a / 1b and the
##      farm house (FF) when homestead_exclusion = TRUE (Minn. Stat. 273.13, subd. 35):
##      none through payable 2011, 40% up to $76,000 then $30,400 less 9% above, zero from
##      $413,800 for payable 2012-2024, and 40% up to $95,000 then $38,000 less 9% above,
##      zero from $517,200 from payable 2025.
##   5. tax_capac_est: tmv_est priced by tier. Homestead: first limit_bdp at the
##      blind/disabled rate, next limit_base1 at the base rate, the rest at the over-base
##      rate. Non-homestead: first limit_base1 (limit_bdp + limit_base1 for 1b types) at the
##      base rate, the rest at the over-base rate. Exempt = 0.

estimate_tax_cap <- function(x, value = "emv_total", homestead_exclusion = TRUE) {
  need <- c("year", "county", "use_class1", "homestead", value)
  miss <- setdiff(need, names(x))
  if (length(miss)) stop("estimate_tax_cap needs columns: ", paste(miss, collapse = ", "),
                         ' (read with names = "standardized")')
  rates <- utils::read.csv(file.path(PARCEL_HOME, "docs", "class_rates_hennepin_2025.csv"),
                           stringsAsFactors = FALSE)
  umap  <- utils::read.csv(file.path(PARCEL_HOME, "docs", "use_class_map.csv"),
                           stringsAsFactors = FALSE)
  message("estimate_tax_cap: Hennepin 2025-assessment class rates applied to every year; ",
          "earlier years are priced at 2025 rates (the homestead exclusion follows the year)")

  key <- paste(x$county, x$use_class1, sep = "\r")
  pt  <- umap$prop_type[match(key, paste(umap$county, umap$use_class1, sep = "\r"))]
  pt[pt == ""] <- NA
  r   <- rates[match(pt, rates$prop_type), ]

  h <- toupper(trimws(as.character(x$homestead)))
  status <- ifelse(h %in% c("Y", "YES", "1"), "homestead",
            ifelse(h %in% c("P", "FRACTIONAL"), "partial",
            ifelse(h %in% c("N", "NO", "0"), "non-homestead", "unknown")))
  hm <- status %in% c("homestead", "partial") & !is.na(r$hmstd_base1_rate)

  # the taxes-payable year the value is for
  offset <- ifelse(x$county %in% c("Hennepin", "Ramsey"), 0, 1)
  payable <- as.numeric(as.character(x$year)) + offset

  v <- as.numeric(x[[value]])
  excl <- 0
  if (isTRUE(homestead_exclusion)) {
    elig <- hm & (substr(r$class_homestead, 1, 2) %in% c("1a", "1b") | pt %in% "FF")
    cap  <- ifelse(payable >= 2025, 95000, 76000)   # value with the largest exclusion (40%)
    e <- ifelse(v <= cap, 0.40 * v, pmax(0, 0.40 * cap - 0.09 * (v - cap)))
    excl <- ifelse(elig & !is.na(v) & payable >= 2012, e, 0)
  }
  tmv <- v - excl

  z  <- function(a) ifelse(is.na(a), 0, a)
  tier <- function(val, lim1, rate1, rate2) {   # first lim1 at rate1, rest at rate2 (rate1 if none)
    rate2 <- ifelse(is.na(rate2), rate1, rate2)
    lim1 <- ifelse(is.na(lim1), Inf, lim1)
    (pmin(val, lim1) * rate1 + pmax(val - lim1, 0) * rate2) / 100
  }
  bdp <- z(r$limit_bdp)
  est_h <- pmin(tmv, bdp) * z(r$hmstd_bdp_rate) / 100 +
           tier(pmax(tmv - bdp, 0), r$limit_base1, r$hmstd_base1_rate, r$hmstd_over_rate)
  est_n <- tier(tmv, ifelse(is.na(r$limit_base1), NA, bdp + r$limit_base1),
                r$nonhmstd_rate, r$nonhmstd_over_rate)
  est <- ifelse(hm, est_h, est_n)
  est[is.na(pt)] <- NA

  x$prop_type <- pt
  x$homestead_status <- status
  x$payable_year <- payable
  x$tmv_est <- ifelse(is.na(pt), NA, tmv)
  x$tax_capac_est <- est
  x
}
