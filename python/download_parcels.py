"""Kept so older scripts that put python/ on sys.path and import download_parcels still work.
New code: pip install the package and use `from parceldata import ...` (README Setup)."""
from parceldata.download_parcels import *  # noqa: F401,F403
from parceldata import read_parcels, download_parcels, parcel_columns, estimate_tax_cap, parcel_data_dir  # noqa: F401
