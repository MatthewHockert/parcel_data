## hennepin_sprawl_verify.R: development_lpm.qmd:790. Old read: st_read(file.path(PAPER_DATA_DIR,
## "fgdb_plan_regonal_parcels_2023", "plan_regonal_parcels_2023.gdb"), layer = "Parcels2023Hennepin", quiet = TRUE),
## PAPER_DATA_DIR = ../hennepin_conservation_easements/hcra_paper/data (from _paths.R). Exact mode (2023 gdb).
suppressMessages({library(sf); library(dplyr)})
source("/Users/matthewhockert/research/parcel_data/R/read_parcels.R")
source("/Users/matthewhockert/research/parcel_data/R/verify_read.R")
p <- "/Users/matthewhockert/research/hennepin_conservation_easements/hcra_paper/data/fgdb_plan_regonal_parcels_2023/plan_regonal_parcels_2023.gdb"
old <- st_read(p, layer = "Parcels2023Hennepin", quiet = TRUE)
new <- read_parcels(years = 2023, counties = "Hennepin", names = "original")
r <- compare_reads(old, new, label = "development_lpm.qmd:790 2023 Hennepin"); r$old_path <- p; r$mode <- "exact"
write.csv(r, "/Users/matthewhockert/research/parcel_data/verification/hennepin_sprawl_results.csv", row.names = FALSE)
print(as.data.frame(r))
