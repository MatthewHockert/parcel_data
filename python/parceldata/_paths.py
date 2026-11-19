"""Where the lookup tables and the downloaded parcel files live (Python twin of R/paths.R).

Lookup tables ship inside the installed package (parceldata/extdata). Run from a clone
instead, they are read from <clone>/inst/extdata.

Parcel files (what download_parcels() saves and read_parcels() reads) go to the first of:
  1. the folder set with parcel_data_dir("F:/parcels") in this session
  2. <PARCEL_HOME>/data, if the PARCEL_HOME environment variable is set
  3. the per-user data folder R uses, tools::R_user_dir("parceldata", "data"), so R and
     Python share one copy: Windows %APPDATA%/R/data/R/parceldata, Mac
     ~/Library/Application Support/org.R-project.R/R/parceldata, Linux
     ~/.local/share/R/parceldata
"""
import os
import sys

_PKG = os.path.dirname(os.path.abspath(__file__))
_state = {"dir": None}


def _table(name):
    for d in (os.path.join(_PKG, "extdata"),                                       # installed package
              os.path.join(os.path.dirname(os.path.dirname(_PKG)), "inst", "extdata")):  # clone
        f = os.path.join(d, name)
        if os.path.exists(f):
            return f
    raise FileNotFoundError(f"lookup table not found: {name}")


def _user_data_dir():
    # the same rule as R's tools::R_user_dir(package, "data")
    p = os.environ.get("R_USER_DATA_DIR") or os.environ.get("XDG_DATA_HOME")
    if not p:
        if os.name == "nt":
            p = os.path.join(os.environ["APPDATA"], "R", "data")
        elif sys.platform == "darwin":
            p = os.path.join(os.path.expanduser("~"), "Library", "Application Support", "org.R-project.R")
        else:
            p = os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(p, "R", "parceldata")


def parcel_data_dir(dir=None):
    """Return the folder parcel files are saved in and read from, or set it for this session."""
    if dir is not None:
        _state["dir"] = os.path.abspath(os.path.expanduser(dir))
        return _state["dir"]
    if _state["dir"]:
        return _state["dir"]
    home = os.environ.get("PARCEL_HOME")
    if home:
        return os.path.join(home, "data")
    return _user_data_dir()


def _store(layer="polygons", quiet=False):
    """Store folder for a layer: <data dir>/standardized_polygons or standardized_points.

    The polygon store was first named "standardized", and the Zenodo zips still unzip to
    that name, so year folders found under the old name are moved across here. Called by
    read_parcels() and download_parcels(). Python twin of .parcel_store() in R/paths.R.
    """
    import warnings
    data_dir = parcel_data_dir()
    if layer == "points":
        return os.path.join(data_dir, "standardized_points")
    old = os.path.join(data_dir, "standardized")
    new = os.path.join(data_dir, "standardized_polygons")
    if not os.path.isdir(old):
        return new

    moved = False
    try:
        if not os.path.isdir(new):
            os.rename(old, new)                      # whole folder in one step
            moved = True
        else:
            for yr in sorted(d for d in os.listdir(old) if d.startswith("year=")):
                if not os.path.isdir(os.path.join(new, yr)):   # a year already in the new folder is left alone
                    os.rename(os.path.join(old, yr), os.path.join(new, yr))
                    moved = True
            if not set(os.listdir(old)) - {".DS_Store"}:
                import shutil
                shutil.rmtree(old)
    except OSError:
        pass                                         # e.g. files open on Windows: handled below
    if moved and not quiet:
        print(f"polygon files moved from {old} to {new}")
    if os.path.isdir(old):
        warnings.warn(f"{old} still holds files that were not moved to {new}; move or delete them by hand")
    return new if os.path.isdir(new) else old        # rename failed: keep reading the old folder
