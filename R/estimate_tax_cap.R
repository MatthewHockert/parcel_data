## estimate_tax_cap(x): estimate each parcel's net tax capacity from its market value,
## property type and homestead status, using ONE year's class rates for every year.
##   p <- read_parcels(2005:2020, "Ramsey", cols = c("pin", "use_class1", "homestead", "emv_total"))
##   p <- estimate_tax_cap(p)          # adds prop_type, homestead_status, tmv_est, tax_capac_est
##
## WARNING: the rates are Hennepin County's table for the 2025 assessment (taxes payable
## 2026, docs/class_rates_hennepin_2025.csv). Minnesota changes class rates, tier limits
## and the homestead market value exclusion over time, so earlier years are priced as if
## 2025 law applied. Use it to fill gaps (e.g. Ramsey, whose tax_capac is 0 for 2005-2020),
## not as the county's own figure. Where the county published tax_capac, prefer it.
##
## Steps, per parcel:
##   1. prop_type: use_class1 looked up in docs/use_class_map.csv (code/14_use_class_map.py).
##      Unmapped labels get NA.
##   2. homestead_status: Y / Yes / 1 = homestead, P / Fractional = partial (priced as
##      homestead), N / No / 0 = non-homestead, anything else = unknown (priced as
##      non-homestead).
##   3. tmv_est: taxable market value. Market value (emv_total) less the 2025 homestead
##      market value exclusion for homesteaded class 1a / 1b / 2a-house property when
##      homestead_exclusion = TRUE: 40% of value up to $95,000, then $38,000 less 9% of the
##      value above $95,000, zero from $517,200 (Minn. Stat. 273.13, subd. 35).
##   4. tax_capac_est: tmv_est priced by tier. Homestead: first limit_bdp at the
##      blind/disabled rate, next limit_base1 at the base rate, the rest at the over-base
##      rate. Non-homestead: first limit_base1 (limit_bdp + limit_base1 for 1b types) at the
##      base rate, the rest at the over-base rate. Exempt = 0.

estimate_tax_cap <- function(x, value = "emv_total", homestead_exclusion = TRUE) {
  need <- c("county", "use_class1", "homestead", value)
  miss <- setdiff(need, names(x))
  if (length(miss)) stop("estimate_tax_cap needs columns: ", paste(miss, collapse = ", "),
                         ' (read with names = "standardized")')
  rates <- utils::read.csv(file.path(PARCEL_HOME, "docs", "class_rates_hennepin_2025.csv"),
                           stringsAsFactors = FALSE)
  umap  <- utils::read.csv(file.path(PARCEL_HOME, "docs", "use_class_map.csv"),
                           stringsAsFactors = FALSE)
  message("estimate_tax_cap: Hennepin 2025-assessment class rates applied to every year; ",
          "earlier years are priced as if 2025 law applied")

  key <- paste(x$county, x$use_class1, sep = "\r")
  pt  <- umap$prop_type[match(key, paste(umap$county, umap$use_class1, sep = "\r"))]
  pt[pt == ""] <- NA
  r   <- rates[match(pt, rates$prop_type), ]

  h <- toupper(trimws(as.character(x$homestead)))
  status <- ifelse(h %in% c("Y", "YES", "1"), "homestead",
            ifelse(h %in% c("P", "FRACTIONAL"), "partial",
            ifelse(h %in% c("N", "NO", "0"), "non-homestead", "unknown")))
  hm <- status %in% c("homestead", "partial") & !is.na(r$hmstd_base1_rate)

  v <- as.numeric(x[[value]])
  excl <- 0
  if (isTRUE(homestead_exclusion)) {
    elig <- hm & substr(r$class_homestead, 1, 2) %in% c("1a", "1b", "2a")
    e <- ifelse(v <= 95000, 0.40 * v, pmax(0, 38000 - 0.09 * (v - 95000)))
    excl <- ifelse(elig & !is.na(v), e, 0)
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
  x$tmv_est <- ifelse(is.na(pt), NA, tmv)
  x$tax_capac_est <- est
  x
}
