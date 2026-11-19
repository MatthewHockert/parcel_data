"""download_parcels(): fetch store years from the Zenodo deposit into parcel_data_dir().

    from parceldata import read_parcels, download_parcels
    download_parcels([2014, 2015])              # polygons
    download_parcels(2021, layer="points")      # points, plus that year's polygons

Zips are one per year and layer (all 7 counties); each is checked against
inst/extdata/zenodo_md5.txt, unzipped into parcel_data_dir() (see _paths.py) and deleted. Years
already on disk are skipped unless overwrite=True. Standardized Points reads
place each point on its polygon, so points also fetch that year's polygons.
Each zip is fetched as `connections` pieces at once (see _fetch_parallel()).
"""
import hashlib
import http.client
import os
import shutil
import tempfile
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor

from tqdm import tqdm

ZENODO_RECORD = "24116899"  # DOI 10.5281/zenodo.24116899
from ._paths import _store, _table, parcel_data_dir


def _md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _remote_size(url):
    """File size in bytes from the Content-Length header, or None if the server gives none."""
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=60) as r:
            n = r.headers.get("Content-Length")
        return int(n) if n else None
    except (OSError, ValueError):
        return None


def _fetch_parallel(url, dest, size, connections, bar):
    """Fetch url as `connections` byte ranges at once, each written at its own offset in dest.

    Zenodo limits the speed of each connection, not of each user, so 8 ranges arrive about
    6 times faster than one download. The md5 check in download_parcels() confirms the file
    is the published one. Returns False (caller then downloads on one connection) if the
    server does not serve ranges or a piece fails 3 times.
    """
    edges = [size * i // connections for i in range(connections + 1)]  # byte offsets of equal pieces
    with open(dest, "wb") as f:
        f.truncate(size)

    def piece(i):
        start, end = edges[i], edges[i + 1] - 1
        for _ in range(3):
            done = 0
            try:
                req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
                with urllib.request.urlopen(req, timeout=60) as r, open(dest, "r+b") as out:
                    if r.status != 206:      # 206 = the server sent just this range
                        return False
                    out.seek(start)
                    for chunk in iter(lambda: r.read(1 << 18), b""):
                        out.write(chunk)
                        done += len(chunk)
                        bar.update(len(chunk))
                if done == end - start + 1:
                    return True
            except (OSError, http.client.HTTPException):
                pass
            bar.update(-done)                # piece failed: take its bytes back off the bar and retry
        return False

    with ThreadPoolExecutor(connections) as pool:
        return all(pool.map(piece, range(connections)))


def download_parcels(years, layer="polygons",
                     base_url=f"https://zenodo.org/records/{ZENODO_RECORD}/files",
                     overwrite=False, connections=8):
    # connections: pieces of each zip fetched at once; 1 = one plain download
    if layer not in ("polygons", "points"):
        raise ValueError("layer must be 'polygons' or 'points'")
    data_dir = parcel_data_dir()
    os.makedirs(data_dir, exist_ok=True)
    print(f"parcel files are saved in {data_dir}")
    with open(_table("zenodo_md5.txt")) as f:
        md5 = dict(reversed(line.split()) for line in f if line.strip())

    layers = ["polygons", "points"] if layer == "points" else ["polygons"]
    jobs = [(yr, ly) for yr in ([years] if isinstance(years, int) else years) for ly in layers]
    for yr, layer in jobs:
        target = os.path.join(_store(layer), f"year={yr}")
        if os.path.isdir(target) and not overwrite:
            print(f"{yr} {layer}: already on disk, skipped")
            continue
        zip_name = f"parcels_{layer}_{yr}.zip"
        if zip_name not in md5:
            raise ValueError(f"{zip_name} is not in the deposit (years are 2005-2025)")

        url = f"{base_url}/{zip_name}" + ("?download=1" if base_url.startswith("http") else "")
        zip_path = os.path.join(tempfile.gettempdir(), zip_name)
        print(f"{yr} {layer}: downloading")
        # PROGRESS BAR: tqdm() draws it and bar.update() advances it, here for the
        # one-connection download and in _fetch_parallel() for the pieces.
        # It only appears in a version installed after this was added, so
        # reinstall the package if no bar shows.
        size = _remote_size(url)
        with tqdm(total=size, unit="B", unit_scale=True, unit_divisor=1024, desc=zip_name) as bar:
            parallel = (connections > 1 and size and size >= connections << 20
                        and _fetch_parallel(url, zip_path, size, connections, bar))
            if not parallel:
                # one connection: size unknown, small file, no range support, or a piece kept failing
                bar.reset(total=size)
                with urllib.request.urlopen(url) as r, open(zip_path, "wb") as out:
                    for chunk in iter(lambda: r.read(1 << 20), b""):
                        out.write(chunk)
                        bar.update(len(chunk))
        if _md5(zip_path) != md5[zip_name]:
            os.remove(zip_path)
            raise IOError(f"{zip_name}: checksum does not match, download again")
        if overwrite:
            shutil.rmtree(target, ignore_errors=True)
        with zipfile.ZipFile(zip_path) as z:
            z.extractall(data_dir)
        _store(layer, quiet=True)  # polygon zips unzip to standardized/; this moves the year into standardized_polygons/
        os.remove(zip_path)
    return data_dir
