## 15_check_tax_cap.R: compare estimate_tax_cap() with each county's published tax_capac,
## for every county-year that has one. Writes docs/tax_capacity_check.csv.
##
## Pairing: Dakota and Carver publish tax_capac one year behind their market value, so
## their file-t tax_capac is compared with the estimate from file t-1. Every other county
## is compared within the same file. Exempt parcels (Dakota publishes a tax_capac for
## them) and parcels with no published tax_capac (0 or NA) are left out.

source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))

lagged   <- c("Dakota", "Carver")   # tax_capac lags the value by one year
counties <- c("Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington")
cols     <- c("pin", "use_class1", "homestead", "emv_total", "tax_year", "tax_capac")
gaps     <- read.csv(file.path(PARCEL_HOME, "docs", "known_gaps.csv"))

rows <- list()
for (cty in counties) for (yr in 2006:2025) {
  if (any(gaps$layer == "polygons" & gaps$county == cty & gaps$year == yr & gaps$column == "tax_capac")) next
  pub <- read_parcels(yr, cty, cols = c("pin", "tax_capac"), geometry = "none")
  src <- if (cty %in% lagged) yr - 1 else yr
  est <- suppressMessages(estimate_tax_cap(read_parcels(src, cty, cols = cols, geometry = "none")))
  est$published <- pub$tax_capac[match(est$pin, pub$pin)]
  ok  <- !is.na(est$tax_capac_est) & !is.na(est$published) & est$published > 0 & !(est$prop_type %in% "EX")
  d   <- est[ok, ]
  if (nrow(d) < 1000) next
  rel <- d$tax_capac_est / d$published - 1
  res <- function(sel) c(round(mean(abs(rel[sel]) < .01), 3), sum(sel))
  rows[[length(rows) + 1]] <- data.frame(
    county = cty, file_year = yr, value_from_file = src,
    payable_year = paste(sort(unique(d$payable_year)), collapse = "/"),
    parcels = nrow(d), within_1pct = round(mean(abs(rel) < .01), 3), within_5pct = round(mean(abs(rel) < .05), 3),
    total_ratio = round(sum(d$tax_capac_est) / sum(d$published), 3),
    homestead_res_within_1pct = res(d$prop_type %in% c("R", "RL", "X", "Y") & d$homestead_status == "homestead")[1],
    comm_ind_ratio = round(median((d$tax_capac_est / d$published)[d$prop_type %in% c("C", "I")]), 3))
  cat(cty, yr, "\n")
}
out <- do.call(rbind, rows)
write.csv(out, file.path(PARCEL_HOME, "docs", "tax_capacity_check.csv"), row.names = FALSE)
print(out, row.names = FALSE)
