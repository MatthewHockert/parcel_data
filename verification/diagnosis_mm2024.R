## diagnosis_mm2024.R (2026-11-08): read-only. Compare the matthew_maps 2024 gdb
## (download dated 2025-12-16) with the store's 2024 gdb (housing_reform copy,
## dated 2025-01-24) for every layer: rows, PIN sets, owner/taxpayer names.
suppressMessages({library(sf); library(dplyr)})
A <- "/Users/matthewhockert/Desktop/Personal Info/matthew_maps_saint_paul/Archive/fgdb_plan_regonal_parcels_2024/plan_regonal_parcels_2024.gdb"
B <- "/Users/matthewhockert/research/parcel_data/data/raw/2024/plan_regonal_parcels_2024.gdb"
la <- st_layers(A); lb <- st_layers(B)
cat("layers mm:", sort(la$name), "\nlayers store:", sort(lb$name), "\n")
print(data.frame(layer = la$name, rows_mm = la$features, rows_store = lb$features[match(la$name, lb$name)]))
nm_cols <- c("OWNER_NAME", "OWNER_MORE", "TAX_NAME", "TAX_ADD_L1", "OWN_ADD_L1")
blank <- function(x) is.na(x) | trimws(x) == ""
res <- list()
for (ly in sort(intersect(la$name, lb$name))) {
  flds <- names(st_read(A, query = sprintf("SELECT * FROM \"%s\" LIMIT 1", ly), quiet = TRUE))
  cols <- intersect(c("PIN", nm_cols), flds)
  q <- sprintf("SELECT %s FROM \"%s\"", paste(cols, collapse = ", "), ly)
  a <- st_drop_geometry(st_read(A, query = q, quiet = TRUE)); b <- st_drop_geometry(st_read(B, query = q, quiet = TRUE))
  for (cl in setdiff(cols, "PIN")) {
    ua <- a[!duplicated(a$PIN), ]; ub <- b[!duplicated(b$PIN), ]
    sh <- intersect(ua$PIN, ub$PIN); x <- ua[[cl]][match(sh, ua$PIN)]; y <- ub[[cl]][match(sh, ub$PIN)]
    differ <- !(blank(x) & blank(y)) & (blank(x) != blank(y) | trimws(x) != trimws(y)); differ[is.na(differ)] <- TRUE
    res[[length(res) + 1]] <- data.frame(layer = ly, col = cl, rows_mm = nrow(a), rows_store = nrow(b),
      pins_mm_only = length(setdiff(ua$PIN, ub$PIN)), pins_store_only = length(setdiff(ub$PIN, ua$PIN)),
      blank_mm = round(mean(blank(a[[cl]])), 4), blank_store = round(mean(blank(b[[cl]])), 4),
      differ_shared = sum(differ), mm_blank_store_not = sum(blank(x) & !blank(y)),
      store_blank_mm_not = sum(blank(y) & !blank(x)))
    if (ly == "Parcels2024Ramsey" && cl %in% c("OWNER_NAME", "TAX_NAME")) {
      i <- head(which(differ), 6)
      cat("\nRamsey", cl, "examples (PIN | mm | store):\n"); print(data.frame(PIN = sh[i], mm = x[i], store = y[i]))
      cat("top mm values:\n"); print(head(sort(table(a[[cl]]), decreasing = TRUE), 5))
    }
  }
}
out <- bind_rows(res); options(width = 250); print(out, row.names = FALSE)
write.csv(out, "/Users/matthewhockert/research/parcel_data/verification/diagnosis_mm2024_results.csv", row.names = FALSE)
