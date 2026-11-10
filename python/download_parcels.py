"""download_parcels(): fetch store years from the Zenodo deposit into PARCEL_HOME.

    from read_parcels import read_parcels, download_parcels
    download_parcels([2014, 2015])              # polygons
    download_parcels(2021, layer="points")      # published points

Zips are one per year and layer (all 7 counties); each is checked against
docs/zenodo_md5.txt, unzipped into $PARCEL_HOME/data and deleted. Years
already on disk are skipped unless overwrite=True. The Python reader returns
the published points, so points do not need the polygons.
"""
import hashlib
import os
import shutil
import tempfile
import urllib.request
import zipfile

ZENODO_RECORD = "24116899"  # DOI 10.5281/zenodo.24116899
_HOME_DEFAULT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download_parcels(years, layer="polygons",
                     base_url=f"https://zenodo.org/records/{ZENODO_RECORD}/files",
                     overwrite=False):
    if layer not in ("polygons", "points"):
        raise ValueError("layer must be 'polygons' or 'points'")
    home = os.environ.get("PARCEL_HOME", _HOME_DEFAULT)
    data_dir = os.path.join(home, "data")
    os.makedirs(data_dir, exist_ok=True)
    with open(os.path.join(home, "docs", "zenodo_md5.txt")) as f:
        md5 = dict(reversed(line.split()) for line in f if line.strip())

    store = "standardized_points" if layer == "points" else "standardized"
    for yr in [years] if isinstance(years, int) else years:
        target = os.path.join(data_dir, store, f"year={yr}")
        if os.path.isdir(target) and not overwrite:
            print(f"{yr} {layer}: already on disk, skipped")
            continue
        zip_name = f"parcels_{layer}_{yr}.zip"
        if zip_name not in md5:
            raise ValueError(f"{zip_name} is not in the deposit (years are 2005-2025)")

        url = f"{base_url}/{zip_name}" + ("?download=1" if base_url.startswith("http") else "")
        zip_path = os.path.join(tempfile.gettempdir(), zip_name)
        print(f"{yr} {layer}: downloading")
        with urllib.request.urlopen(url) as r, open(zip_path, "wb") as out:
            shutil.copyfileobj(r, out, 1 << 20)
        if _md5(zip_path) != md5[zip_name]:
            os.remove(zip_path)
            raise IOError(f"{zip_name}: checksum does not match, download again")
        if overwrite:
            shutil.rmtree(target, ignore_errors=True)
        with zipfile.ZipFile(zip_path) as z:
            z.extractall(data_dir)
        os.remove(zip_path)
    return data_dir
