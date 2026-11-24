"""Download regional HYCOM snapshots through OPeNDAP and save NetCDF4.

Python port of get_hycom_online.m by Wenfan Wu (2021, updated Sep 2025).
Dependencies: numpy, netCDF4 (with OPeNDAP support).
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
import json
import time
import warnings

import numpy as np
from netCDF4 import Dataset, date2num, num2date


_VAR_NAMES = {
    'ssh': 'surf_el', 'temp': 'water_temp', 'salt': 'salinity',
    'uvel': 'water_u', 'vvel': 'water_v',
}
_ESPC_NAMES = {'ssh': 'ssh', 'temp': 't3z', 'salt': 's3z',
               'uvel': 'u3z', 'vvel': 'v3z'}
_BASE_URL = 'http://tds.hycom.org/thredds/dodsC/'
_FIRST = datetime(1992, 10, 2)
_SWITCH = datetime(2014, 7, 1, 12)
_ESPC_START = datetime(2024, 9, 4)
_TIME_UNITS = 'days since 1970-01-01 00:00:00'


def _as_datetime(value):
    """Convert datetime, ISO date string, or numpy.datetime64 to naive UTC."""
    if isinstance(value, np.datetime64):
        if np.isnat(value):
            raise ValueError('timeTick cannot be NaT.')
        value = value.astype('datetime64[us]').astype(datetime)
    if isinstance(value, str):
        value = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if not isinstance(value, datetime):
        raise TypeError('timeTick must be a datetime, ISO string or numpy.datetime64.')
    if value.tzinfo is not None:
        value = value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def _nominal_time(t):
    """Original daily/3-hourly time pool; ties select the earlier time."""
    last = datetime.now(timezone.utc).replace(tzinfo=None, hour=0, minute=0,
                                              second=0, microsecond=0) - timedelta(days=1)
    if not _FIRST <= t <= last:
        raise ValueError(f'Time must be within {_FIRST:%Y-%m-%d} and {last:%Y-%m-%d} 00:00 UTC.')
    if t < _SWITCH:
        midnight = t.replace(hour=0, minute=0, second=0, microsecond=0)
        candidates = [midnight, min(midnight + timedelta(days=1), _SWITCH)]
    else:
        step = timedelta(hours=3)
        lower = _SWITCH + ((t - _SWITCH) // step) * step
        candidates = [lower, min(lower + step, last)]
    return min(candidates, key=lambda x: abs(x - t))


def get_URL(timeTick):
    """Select the HYCOM product, preserving the original priority order."""
    t = _as_datetime(timeTick)
    if t < _FIRST:
        raise ValueError('No HYCOM product before 1992-10-02.')
    if t >= _ESPC_START:
        return _BASE_URL + 'ESPC-D-V02/t3z'

    # Do not reorder overlapping products: priority follows the MATLAB version.
    products = [
        (datetime(2018, 1, 1, 12), datetime(2020, 2, 19, 9), 'GLBv0.08/expt_93.0'),
        (datetime(2017, 10, 1, 12), datetime(2018, 3, 20, 9), 'GLBv0.08/expt_92.9'),
        (datetime(2017, 6, 1, 12), datetime(2017, 10, 1, 9), 'GLBv0.08/expt_57.7'),
        (datetime(2017, 2, 1, 12), datetime(2017, 6, 1, 9), 'GLBv0.08/expt_92.8'),
        (datetime(2016, 5, 1, 12), datetime(2017, 2, 1, 9), 'GLBv0.08/expt_57.2'),
        (datetime(2014, 7, 1, 12), datetime(2016, 9, 30, 9), 'GLBv0.08/expt_56.3'),
        (datetime(2018, 12, 4, 12), _ESPC_START, 'GLBy0.08/expt_93.0'),
        (datetime(2016, 4, 18), datetime(2018, 11, 20), 'GLBu0.08/expt_91.2'),
        (datetime(2014, 4, 7), datetime(2016, 4, 18), 'GLBu0.08/expt_91.1'),
        (datetime(2013, 8, 17), datetime(2014, 4, 8), 'GLBu0.08/expt_91.0'),
        (datetime(1995, 8, 1), datetime(2012, 12, 31), 'GLBu0.08/expt_19.1'),
        (datetime(2012, 1, 25), datetime(2013, 8, 20), 'GLBu0.08/expt_90.9'),
        (datetime(1992, 10, 2), datetime(1995, 7, 31), 'GLBu0.08/expt_19.0'),
    ]
    for start, end, product in products:
        if start <= t <= end:
            return _BASE_URL + product
    raise ValueError(f'No HYCOM product defined for {t!s}.')


def _get_urls(t, names, url):
    if url is not None:
        base = str(url).removesuffix('?')
        return base, {name: base for name in names}
    base = get_URL(t)
    if t >= _ESPC_START:
        root = base.rsplit('/', 1)[0]
        return (f'{base}/{t.year}',
                {name: f'{root}/{_ESPC_NAMES[name]}/{t.year}' for name in names})
    return base, {name: base for name in names}


def _array(value):
    """Decode masked values to NaN, including packed integer variables."""
    return np.ma.asarray(value, dtype=np.float64).filled(np.nan)


def _coord(ds, name):
    v = _array(ds.variables[name][:])
    if v.ndim != 1 or not v.size or not np.isfinite(v).all():
        raise ValueError(f'Invalid one-dimensional {name} coordinate.')
    return v


def _nearest_time(ds, t):
    v = ds.variables['time']
    units = getattr(v, 'units', 'hours since 2000-01-01 00:00:00')
    calendar = getattr(v, 'calendar', 'standard')
    values = _coord(ds, 'time')
    target = date2num(t, units, calendar=calendar)
    index = int(np.argmin(np.abs(values - target)))
    actual = num2date(values[index], units, calendar=calendar,
                      only_use_cftime_datetimes=False,
                      only_use_python_datetimes=True)
    return index, _as_datetime(actual)


def _longitude_slices(lon, west, east):
    """Get contiguous OPeNDAP slices in eastward order across the seam."""
    if np.any(np.diff(lon) <= 0):
        raise ValueError('HYCOM longitude must be strictly increasing.')
    # Ignore a redundant cyclic endpoint (e.g. both 0 and 360).
    n = len(lon)
    if n > 1 and np.isclose(lon[-1] - lon[0], 360.0, atol=1e-5, rtol=0):
        n -= 1
    grid = lon[:n]
    def closest(x):
        return int(np.argmin(np.abs((grid - x + 180.0) % 360.0 - 180.0)))
    i, j = closest(west), closest(east)
    full = np.isclose(abs(east - west), 360.0, atol=1e-8, rtol=0)
    if full:
        slices = [slice(i, n)] + ([slice(0, i)] if i else [])
    elif i <= j:
        slices = [slice(i, j + 1)]
    else:
        slices = [slice(i, n), slice(0, j + 1)]
    selected = np.concatenate([lon[s] for s in slices])
    # Restore the requested longitude convention; do not reorder data.
    if min(west, east) < 0:
        selected = np.where(selected > 180, selected - 360, selected)
    elif max(west, east) > 180:
        selected = np.where(selected < 0, selected + 360, selected)
    return slices, selected


def _read_variable(ds, name, itime, xslices, yslice):
    """Read only the regional hyperslabs; output (depth, lat, lon) or (lat, lon)."""
    v = ds.variables[_VAR_NAMES[name]]
    dims = ('lat', 'lon') if name == 'ssh' else ('depth', 'lat', 'lon')
    if set(v.dimensions) != set(dims + ('time',)):
        raise ValueError(f'Unexpected dimensions for {v.name}: {v.dimensions}')
    source_dims = tuple(d for d in v.dimensions if d != 'time')
    order = tuple(source_dims.index(d) for d in dims)
    blocks = []
    for xslice in xslices:
        subset = {'time': itime, 'lat': yslice, 'lon': xslice, 'depth': slice(None)}
        block = _array(v[tuple(subset[d] for d in v.dimensions)])
        blocks.append(block.transpose(order).astype(np.float32))
    return np.concatenate(blocks, axis=-1) if len(blocks) > 1 else blocks[0]


def _check_time(actual, requested, tolerance):
    if abs(actual - requested) > tolerance:
        raise ValueError(f'HYCOM data missing near {requested}; nearest data: {actual}. '
                         f'Time deviation exceeds {tolerance}.')


def save_nc(filepath, D, *, cache_key=None, source_urls=None):
    """Write the same NetCDF dimension order as the MATLAB-generated file."""
    filepath = Path(filepath)
    # Atomic replacement protects the existing cache against failed downloads/writes.
    with NamedTemporaryFile(dir=filepath.parent, suffix='.nc', delete=False) as f:
        tmp = Path(f.name)
    try:
        with Dataset(str(tmp), 'w', format='NETCDF4') as nc:
            for name, units in [('lon', 'degrees_east'), ('lat', 'degrees_north'), ('depth', 'm')]:
                nc.createDimension(name, len(D[name]))
                v = nc.createVariable(name, 'f4', (name,))
                v.units = units
                v[:] = D[name]
                if name == 'depth':
                    v.positive = 'down'
            nc.createDimension('one', 1)
            v = nc.createVariable('time', 'f8', ('one',))
            v.units = _TIME_UNITS
            v.calendar = 'standard'
            v[:] = date2num(D['time'], _TIME_UNITS)
            v = nc.createVariable('dev_time', 'f4', ('one',))
            v.units = 'hours'
            v[:] = D['dev_time']
            units = {'ssh': 'm', 'temp': 'degrees_C', 'salt': '1e-3',
                     'uvel': 'm s-1', 'vvel': 'm s-1'}
            for name in _VAR_NAMES:
                if name in D:
                    dims = ('lat', 'lon') if name == 'ssh' else ('depth', 'lat', 'lon')
                    v = nc.createVariable(name, 'f4', dims, zlib=True,
                                          complevel=4, fill_value=np.float32(np.nan))
                    v.units = units[name]
                    v[:] = D[name]
            if cache_key is not None:
                nc.hycom_cache_key = cache_key
            if source_urls is not None:
                nc.hycom_source_urls = json.dumps(source_urls, sort_keys=True)
        tmp.replace(filepath)
    finally:
        tmp.unlink(missing_ok=True)


def read_nc(filepath):
    """Read a downloaded snapshot; time is datetime, dev_time is float hours."""
    with Dataset(str(filepath)) as nc:
        D = {name: _array(v[:]).astype(np.float32) for name, v in nc.variables.items()
             if name not in ('time', 'dev_time')}
        v = nc.variables['time']
        actual = num2date(v[0], v.units, calendar=getattr(v, 'calendar', 'standard'),
                          only_use_cftime_datetimes=False, only_use_python_datetimes=True)
        D['time'] = _as_datetime(actual)
        D['dev_time'] = float(nc.variables['dev_time'][0])
    return D


def get_hycom_online(aimpath, region, timeTick, varList=None, *, url=None,
                     prefix=None, tole_time=timedelta(days=1), overwrite=False):
    """Download a single regional HYCOM snapshot and return a dictionary.

    Parameters
    ----------
    aimpath : str or Path
        Directory for NetCDF files (created automatically).
    region : sequence of 4 floats
        [west, east, south, north], longitude in [-180,180] or [0,360].
        west > east denotes a region crossing the longitude seam.
    timeTick : datetime, numpy.datetime64 or ISO string
        Requested UTC time; nearest nominal daily/3-hourly time is used.
    varList : sequence of str or str, optional
        Any of ssh, temp, salt, uvel, vvel; defaults to all five.
    url : str, optional
        Override product selection with a single OPeNDAP URL (or local NC file).
    prefix : str, optional
        Filename prefix, default W...E...S...N... (original naming convention).
    tole_time : timedelta, optional
        Maximum absolute deviation between requested and actual time (1 day).
    overwrite : bool, optional
        Force downloading instead of using a matching cached file.

    Returns
    -------
    dict
        lon, lat, depth, time (UTC datetime), dev_time (hours), requested fields.
        ssh: (lat, lon); other fields: (depth, lat, lon). Missing values: NaN.
    """
    tic = time.perf_counter()
    t = _as_datetime(timeTick)
    nominal = _nominal_time(t)
    if not isinstance(tole_time, timedelta) or tole_time < timedelta(0):
        raise ValueError('tole_time must be a nonnegative datetime.timedelta.')
    region = np.asarray(region, dtype=float)
    if region.shape != (4,) or not np.isfinite(region).all():
        raise ValueError('region must contain four finite numbers [W, E, S, N].')
    west, east, south, north = region
    if not ((-180 <= west <= 180 and -180 <= east <= 180) or
            (0 <= west <= 360 and 0 <= east <= 360)):
        raise ValueError('Use either [-180, 180] or [0, 360] for longitude bounds.')
    if not -90 <= south <= north <= 90:
        raise ValueError('Latitude bounds must satisfy -90 <= south <= north <= 90.')
    names = list(_VAR_NAMES) if varList is None else ([varList] if isinstance(varList, str) else list(varList))
    names = list(dict.fromkeys(str(v).lower() for v in names))
    if not names or any(v not in _VAR_NAMES for v in names):
        raise ValueError(f'varList must contain one or more of {list(_VAR_NAMES)}.')
    folder = Path(aimpath)
    folder.mkdir(parents=True, exist_ok=True)
    if prefix is None:
        # MATLAB round uses ties away from zero, unlike Python round.
        rounded = (np.sign(region) * np.floor(np.abs(region) + 0.5)).astype(int)
        prefix = ('W{}E{}S{}N{}'.format(*rounded)).replace('-', 'n')
    if not prefix or Path(prefix).name != prefix:
        raise ValueError('prefix must be a filename prefix, not a path.')
    aimfile = folder / f'{prefix}_{nominal:%Y%m%dT%H%MZ}.nc'
    ref_url, urls = _get_urls(nominal, names, url)
    cache_key = json.dumps({'region': region.tolist(), 'reference_url': ref_url}, sort_keys=True)

    if aimfile.exists() and not overwrite:
        try:
            with Dataset(str(aimfile)) as nc:
                matching = (getattr(nc, 'hycom_cache_key', None) == cache_key and
                            all(name in nc.variables for name in names))
                cached_urls = json.loads(getattr(nc, 'hycom_source_urls', '{}'))
                matching = matching and all(cached_urls.get(name) == urls[name] for name in names)
            if matching:
                D = read_nc(aimfile)
                _check_time(D['time'], t, tole_time)
                D['dev_time'] = (D['time'] - t).total_seconds() / 3600
                print(f'Already downloaded: {aimfile}')
                return {k: v for k, v in D.items() if k not in _VAR_NAMES or k in names}
        except (OSError, RuntimeError, ValueError, KeyError, TypeError) as exc:
            warnings.warn(f'Cannot use cached file ({exc}); downloading again.', stacklevel=2)
        else:
            warnings.warn(f'Cache metadata/variables differ; replacing {aimfile} after download.', stacklevel=2)

    print(f'Downloading HYCOM: {nominal:%Y-%m-%d %H:%M} UTC')
    print(f'Product: {ref_url}')
    with Dataset(ref_url) as ref:
        lon = _coord(ref, 'lon')
        lat = _coord(ref, 'lat')
        # Custom SSH-only datasets need not have a depth axis.
        depth = _coord(ref, 'depth') if 'depth' in ref.variables else np.array([], dtype=float)
        if not depth.size and any(name != 'ssh' for name in names):
            raise ValueError('Reference product has no depth coordinate.')
        itime, actual = _nearest_time(ref, nominal)
        _check_time(actual, t, tole_time)
        if south < lat.min() or north > lat.max():
            warnings.warn('Latitude bounds extend beyond the product grid; using nearest endpoints.', stacklevel=2)
        xslices, selected_lon = _longitude_slices(lon, west, east)
        iy = sorted([int(np.argmin(abs(lat - x))) for x in (south, north)])
        yslice = slice(iy[0], iy[1] + 1)
        D = {'lon': selected_lon.astype(np.float32), 'lat': lat[yslice].astype(np.float32),
             'depth': depth.astype(np.float32), 'time': actual,
             'dev_time': (actual - t).total_seconds() / 3600}

        def read_one(ds, name, index):
            print(f'  {name}: {_VAR_NAMES[name]}')
            return _read_variable(ds, name, index, xslices, yslice)

        for name, source in urls.items():
            if source == ref_url:
                D[name] = read_one(ref, name, itime)
                continue
            # ESPC-D-V02 stores variables separately. Do not reuse time indices
            # between files: SSH is hourly, while 3-D fields are three-hourly.
            with Dataset(source) as ds:
                for axis, original in [('lon', lon), ('lat', lat), ('depth', depth)]:
                    if axis == 'depth' and name == 'ssh':
                        continue
                    other = _coord(ds, axis)
                    if other.shape != original.shape or not np.allclose(other, original, rtol=0, atol=1e-6):
                        raise ValueError(f'{name} grid differs from reference along {axis}.')
                index, var_time = _nearest_time(ds, actual)
                if var_time != actual:
                    raise ValueError(f'{name} has no data at common time {actual}; nearest is {var_time}.')
                D[name] = read_one(ds, name, index)

    save_nc(aimfile, D, cache_key=cache_key, source_urls=urls)
    print(f'Saved: {aimfile} ({time.perf_counter() - tic:.2f} s)')
    return D
