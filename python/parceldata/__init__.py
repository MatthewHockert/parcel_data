"""parceldata: read the Twin Cities regional parcels, 2005-2025 (Python twin of the R package).

    from parceldata import read_parcels, download_parcels
    download_parcels(2016)
    p = read_parcels(2016, "Ramsey", cols=["pin", "emv_total"])
"""
from ._paths import parcel_data_dir
from .read_parcels import read_parcels
from .download_parcels import download_parcels
from .parcel_columns import parcel_columns
from .estimate_tax_cap import estimate_tax_cap
from .collapse_condos import collapse_condos

__all__ = ["read_parcels", "download_parcels", "parcel_columns", "estimate_tax_cap",
           "collapse_condos", "parcel_data_dir"]
__version__ = "1.0.0"
