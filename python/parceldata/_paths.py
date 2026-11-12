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
