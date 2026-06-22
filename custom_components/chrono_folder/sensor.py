from __future__ import annotations

import asyncio
import fnmatch
import logging
import os
import threading
from datetime import datetime
from typing import Any

from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import (
    DOMAIN,
    CONF_LABEL,
    CONF_FOLDER,
    CONF_FILESPEC,
    CONF_RECURSE,
    CONF_MAX_PHOTOS,
    DEFAULT_MAX_PHOTOS,
    DEBOUNCE_SECONDS,
    ATTR_FILES,
    ATTR_LABEL,
    ATTR_FOLDER,
    ATTR_FILESPEC,
    ATTR_RECURSE,
    ATTR_MAX_PHOTOS,
    FILE_PATH,
    FILE_URL,
    FILE_NAME,
    FILE_DATE,
    FILE_TIME,
    FILE_SIZE,
    FILE_TYPE,
    EXIF_PREFIX,
)

__version__ = "sensor.py 0.0.12"
# v0.0.12: Normalize exifDateTimeOriginal/Digitized to use '-' in date portion;
#           add derived exifDateOriginal, exifTimeOriginal, exifDateDigitized,
#           exifTimeDigitized fields
# v0.0.11: Add asyncio.Lock around all _files mutations to prevent races
#           between full rescans and incremental watcher updates
# v0.0.10: Incremental watcher updates with 10s debounce; hard max_photos cap;
#           at-cap deletes trigger full rescan to backfill from disk;
#           remove unused callback import and unused _refresh_lock
# v0.0.9: Fix os.path.join with leading-slash relative_folder - strip before joining
# v0.0.8: Expose folder, filespec and recurse as sensor attributes
# v0.0.7: Drop folderName, add filePath and fileURL; folder input now relative to www
# v0.0.6: Format integers without decimal point, floats/IFDRational with decimal point
# v0.0.5: Clean EXIF values - strip nulls/whitespace, nan to n/a, all values as strings,
#          split known tuple fields into named sub-fields
# v0.0.4: Fix NoEntitySpecifiedError - guard async_write_ha_state until entity is registered
# v0.0.3: Move imports above version info to fix SyntaxError
# v0.0.2: Support multiple filespec patterns separated by semicolons
# v0.0.1: Initial release

_LOGGER = logging.getLogger(__name__)

# ─── Watchdog import (optional — graceful fallback if not yet installed) ───────
try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
    WATCHDOG_AVAILABLE = True
except ImportError:
    WATCHDOG_AVAILABLE = False
    _LOGGER.warning("chrono_folder: watchdog not available, filesystem watch disabled")

# ─── Pillow import (optional — graceful fallback if not yet installed) ─────────
try:
    from PIL import Image
    from PIL.ExifTags import TAGS, GPSTAGS
    PILLOW_AVAILABLE = True
except ImportError:
    PILLOW_AVAILABLE = False
    _LOGGER.warning("chrono_folder: Pillow not available, EXIF extraction disabled")


# ─── Platform setup ───────────────────────────────────────────────────────────

async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up Chrono Folder sensor from a config entry."""
    sensor = ChronoFolderSensor(hass, entry)
    async_add_entities([sensor], update_before_add=True)


# ─── EXIF helpers ─────────────────────────────────────────────────────────────

def _to_camel(tag: str) -> str:
    """Convert an EXIF tag name to camelCase with exif prefix.
    Example: 'DateTimeOriginal' -> 'exifDateTimeOriginal'
             'GPS GPSLatitude'  -> 'exifGPSLatitude'
    """
    tag = tag.strip().replace(" ", "")
    if tag:
        tag = tag[0].upper() + tag[1:]
    return f"{EXIF_PREFIX}{tag}"


def _clean_str(value: Any) -> str:
    """Convert any value to a clean string.
    Strips null bytes and whitespace. Replaces nan with 'n/a'.
    """
    s = str(value).replace("\x00", "").strip()
    if s.lower() == "nan":
        return "n/a"
    return s


def _clean_scalar(value: Any) -> str:
    """Clean a scalar EXIF value to a safe string.
    Integers are formatted without decimal point.
    Floats and IFDRational values are formatted with decimal point.
    """
    try:
        if isinstance(value, int) and not isinstance(value, bool):
            return str(value)
        if hasattr(value, 'numerator'):
            # IFDRational — always format as float.
            f = float(value)
            return "n/a" if str(f).lower() == "nan" else _clean_str(f)
        if isinstance(value, float):
            return "n/a" if str(value).lower() == "nan" else _clean_str(value)
    except Exception:
        pass
    return _clean_str(value)


def _clean_tuple(value: tuple | list) -> str:
    """Convert a tuple/list EXIF value to a clean string representation."""
    parts = []
    for v in value:
        try:
            if hasattr(v, 'numerator'):
                f = float(v)
                parts.append("n/a" if str(f).lower() == "nan" else _clean_str(f))
            else:
                parts.append(_clean_str(v))
        except Exception:
            parts.append(_clean_str(v))
    return f"({', '.join(parts)})"


def _split_lens_specification(value: tuple | list, result: dict, base_key: str) -> None:
    """Split LensSpecification tuple into 4 named fields."""
    names = ["MinFocalLength", "MaxFocalLength", "MinAperture", "MaxAperture"]
    for i, name in enumerate(names):
        try:
            v = value[i] if i < len(value) else None
            if v is None:
                result[f"{base_key}{name}"] = ""
            elif hasattr(v, 'numerator'):
                f = float(v)
                result[f"{base_key}{name}"] = "n/a" if str(f).lower() == "nan" else _clean_str(f)
            else:
                result[f"{base_key}{name}"] = _clean_str(v)
        except Exception:
            result[f"{base_key}{name}"] = ""


def _split_white_point(value: tuple | list, result: dict, base_key: str) -> None:
    """Split WhitePoint tuple into X and Y fields."""
    names = ["X", "Y"]
    for i, name in enumerate(names):
        try:
            v = value[i] if i < len(value) else None
            result[f"{base_key}{name}"] = _clean_scalar(v) if v is not None else ""
        except Exception:
            result[f"{base_key}{name}"] = ""


def _split_primary_chromaticities(value: tuple | list, result: dict, base_key: str) -> None:
    """Split PrimaryChromaticities into RedX/Y, GreenX/Y, BlueX/Y."""
    names = ["RedX", "RedY", "GreenX", "GreenY", "BlueX", "BlueY"]
    for i, name in enumerate(names):
        try:
            v = value[i] if i < len(value) else None
            result[f"{base_key}{name}"] = _clean_scalar(v) if v is not None else ""
        except Exception:
            result[f"{base_key}{name}"] = ""


def _split_ycbcr_coefficients(value: tuple | list, result: dict, base_key: str) -> None:
    """Split YCbCrCoefficients into Y, Cb, Cr fields."""
    names = ["YCoefficient", "CbCoefficient", "CrCoefficient"]
    for i, name in enumerate(names):
        try:
            v = value[i] if i < len(value) else None
            result[f"{base_key}{name}"] = _clean_scalar(v) if v is not None else ""
        except Exception:
            result[f"{base_key}{name}"] = ""


def _split_reference_black_white(value: tuple | list, result: dict, base_key: str) -> None:
    """Split ReferenceBlackWhite into 6 named fields."""
    names = ["RefBlackY", "RefWhiteY", "RefBlackCb", "RefWhiteCb", "RefBlackCr", "RefWhiteCr"]
    for i, name in enumerate(names):
        try:
            v = value[i] if i < len(value) else None
            result[f"{base_key}{name}"] = _clean_scalar(v) if v is not None else ""
        except Exception:
            result[f"{base_key}{name}"] = ""


# Map of tag names that have known tuple splits.
_TUPLE_SPLITTERS = {
    "LensSpecification":      _split_lens_specification,
    "WhitePoint":             _split_white_point,
    "PrimaryChromaticities":  _split_primary_chromaticities,
    "YCbCrCoefficients":      _split_ycbcr_coefficients,
    "ReferenceBlackWhite":    _split_reference_black_white,
}


def _dms_to_decimal(dms: tuple, ref: str) -> float | None:
    """Convert GPS DMS tuple to decimal degrees."""
    try:
        degrees = float(dms[0])
        minutes = float(dms[1])
        seconds = float(dms[2])
        decimal = degrees + minutes / 60.0 + seconds / 3600.0
        if ref in ("S", "W"):
            decimal = -decimal
        return round(decimal, 7)
    except Exception:
        return None


def _split_exif_datetime(result: dict, key: str, date_key: str, time_key: str) -> None:
    """Convert a 'YYYY:MM:DD HH:MM:SS' EXIF datetime value in-place to use
    '-' in the date portion, and add separate date/time fields derived from it.
    No-op if the key is not present or does not match the expected format.
    """
    value = result.get(key)
    if not value or value == "n/a":
        return

    parts = value.split(" ", 1)
    if len(parts) != 2:
        return

    date_part, time_part = parts
    date_part_fixed = date_part.replace(":", "-")

    result[key]      = f"{date_part_fixed} {time_part}"
    result[date_key] = date_part_fixed
    result[time_key] = time_part


def _extract_exif(path: str) -> dict[str, Any]:
    """Extract all EXIF data from an image file using Pillow.
    Returns a dict of camelCased exif* keys, all values as clean strings.
    Empty dict if Pillow unavailable or file has no EXIF.
    """
    if not PILLOW_AVAILABLE:
        return {}

    result: dict[str, Any] = {}
    try:
        img = Image.open(path)
        raw_exif = img._getexif()  # noqa: SLF001
        if not raw_exif:
            return {}

        gps_info_raw: dict | None = None

        for tag_id, value in raw_exif.items():
            tag_name = TAGS.get(tag_id, str(tag_id))

            # Handle GPS block separately.
            if tag_name == "GPSInfo":
                gps_info_raw = value
                continue

            # Skip binary/bytes values.
            if isinstance(value, bytes):
                continue

            key = _to_camel(tag_name)

            if isinstance(value, (tuple, list)):
                # Store clean string representation of the full tuple.
                result[key] = _clean_tuple(value)
                # Also split known tuples into named sub-fields.
                splitter = _TUPLE_SPLITTERS.get(tag_name)
                if splitter:
                    splitter(value, result, key)
            else:
                result[key] = _clean_scalar(value)

        # Process GPS block.
        if gps_info_raw:
            gps: dict[str, Any] = {}
            for gps_tag_id, gps_value in gps_info_raw.items():
                gps_tag_name = GPSTAGS.get(gps_tag_id, str(gps_tag_id))
                gps[gps_tag_name] = gps_value

            lat = _dms_to_decimal(gps.get("GPSLatitude"), gps.get("GPSLatitudeRef", ""))
            lon = _dms_to_decimal(gps.get("GPSLongitude"), gps.get("GPSLongitudeRef", ""))

            if lat is not None:
                result[_to_camel("GPSLatitude")]  = str(lat)
            if lon is not None:
                result[_to_camel("GPSLongitude")] = str(lon)

            # Expose all other GPS sub-tags as clean strings.
            for gps_tag_name, gps_value in gps.items():
                if isinstance(gps_value, bytes):
                    continue
                key = _to_camel(f"GPS{gps_tag_name}")
                if isinstance(gps_value, (tuple, list)):
                    result[key] = _clean_tuple(gps_value)
                else:
                    result[key] = _clean_scalar(gps_value)

        # Split DateTimeOriginal and DateTimeDigitized into separate
        # date/time fields, and normalize the date portion to use '-'.
        _split_exif_datetime(
            result, _to_camel("DateTimeOriginal"),
            _to_camel("DateOriginal"), _to_camel("TimeOriginal"),
        )
        _split_exif_datetime(
            result, _to_camel("DateTimeDigitized"),
            _to_camel("DateDigitized"), _to_camel("TimeDigitized"),
        )

    except Exception as err:
        _LOGGER.debug("chrono_folder: EXIF extraction failed for %s: %s", path, err)

    return result


def _build_file_entry(
    full_path: str,
    www_path: str,
    relative_folder: str,
    exif_cache: dict[str, Any],
) -> dict[str, Any]:
    """Build a single file entry dict for the sensor attribute."""
    stat      = os.stat(full_path)
    mtime     = datetime.fromtimestamp(stat.st_mtime)
    filename  = os.path.basename(full_path)
    _, ext    = os.path.splitext(filename)
    cache_key = f"{full_path}:{stat.st_mtime}:{stat.st_size}"

    # Derive the relative subfolder for this file (relevant when recursing).
    rel_dir      = os.path.relpath(os.path.dirname(full_path), www_path)
    file_url_path = rel_dir.replace(os.sep, "/")

    # Use cached EXIF if file has not changed.
    if cache_key not in exif_cache:
        exif_cache[cache_key] = _extract_exif(full_path)
    exif_data = exif_cache[cache_key]

    entry: dict[str, Any] = {
        FILE_PATH: full_path,
        FILE_URL:  f"/local/{file_url_path}/{filename}",
        FILE_NAME: filename,
        FILE_DATE: mtime.strftime("%Y-%m-%d"),
        FILE_TIME: mtime.strftime("%H:%M:%S"),
        FILE_SIZE: stat.st_size,
        FILE_TYPE: ext.lstrip(".").lower(),
    }
    entry.update(exif_data)
    return entry


def _matches_filespec(filename: str, filespec: str) -> bool:
    """Return True if filename matches any semicolon-separated pattern in filespec."""
    patterns = [p.strip() for p in filespec.split(";") if p.strip()]
    if not patterns:
        patterns = ["*.*"]
    return any(fnmatch.fnmatch(filename.lower(), p.lower()) for p in patterns)


def _scan_folder(
    www_path: str,
    relative_folder: str,
    filespec: str,
    recurse: bool,
    max_photos: int,
    exif_cache: dict[str, Any],
) -> list[dict[str, Any]]:
    """Scan the folder and return the file list, capped at max_photos.
    filespec may contain multiple patterns separated by semicolons.
    """
    folder   = os.path.join(www_path, relative_folder.lstrip("/"))
    patterns = [p.strip() for p in filespec.split(";") if p.strip()]
    if not patterns:
        patterns = ["*.*"]

    def _matches(filename: str) -> bool:
        return any(fnmatch.fnmatch(filename.lower(), p.lower()) for p in patterns)

    results: list[dict[str, Any]] = []

    if recurse:
        for root, _dirs, files in os.walk(folder):
            for filename in files:
                if _matches(filename):
                    full_path = os.path.join(root, filename)
                    try:
                        results.append(_build_file_entry(full_path, www_path, relative_folder, exif_cache))
                    except Exception as err:
                        _LOGGER.debug("chrono_folder: skipping %s: %s", full_path, err)
    else:
        try:
            entries = os.listdir(folder)
        except OSError as err:
            _LOGGER.error("chrono_folder: cannot list folder %s: %s", folder, err)
            return []
        for filename in entries:
            if _matches(filename):
                full_path = os.path.join(folder, filename)
                if os.path.isfile(full_path):
                    try:
                        results.append(_build_file_entry(full_path, www_path, relative_folder, exif_cache))
                    except Exception as err:
                        _LOGGER.debug("chrono_folder: skipping %s: %s", full_path, err)

    results.sort(key=lambda e: e[FILE_NAME])

    if len(results) > max_photos:
        _LOGGER.warning(
            "chrono_folder: folder %s contains %d matching files, "
            "truncating to max_photos=%d",
            folder, len(results), max_photos,
        )
        results = results[:max_photos]

    return results


def _build_single_entry_by_path(
    full_path: str,
    www_path: str,
    relative_folder: str,
    exif_cache: dict[str, Any],
) -> dict[str, Any] | None:
    """Build a single file entry for one specific file path.
    Returns None if the file no longer exists or cannot be read.
    """
    try:
        if not os.path.isfile(full_path):
            return None
        return _build_file_entry(full_path, www_path, relative_folder, exif_cache)
    except Exception as err:
        _LOGGER.debug("chrono_folder: could not build entry for %s: %s", full_path, err)
        return None


# ─── Watchdog event handler ───────────────────────────────────────────────────

class _FolderEventHandler(FileSystemEventHandler if WATCHDOG_AVAILABLE else object):
    """Watchdog event handler that reports specific file changes.
    queue_change_callback is called with (event_type, path) for every
    non-directory create/modify/delete/move event. event_type is one of
    'created', 'modified', 'deleted'. For moves, both a 'deleted' (old path)
    and a 'created' (new path) are reported.
    """

    def __init__(self, queue_change_callback) -> None:
        if WATCHDOG_AVAILABLE:
            super().__init__()
        self._queue_change = queue_change_callback

    def on_created(self, event) -> None:  # noqa: ANN001
        if not event.is_directory:
            self._queue_change("created", event.src_path)

    def on_modified(self, event) -> None:  # noqa: ANN001
        if not event.is_directory:
            self._queue_change("modified", event.src_path)

    def on_deleted(self, event) -> None:  # noqa: ANN001
        if not event.is_directory:
            self._queue_change("deleted", event.src_path)

    def on_moved(self, event) -> None:  # noqa: ANN001
        if not event.is_directory:
            self._queue_change("deleted", event.src_path)
            self._queue_change("created", event.dest_path)


# ─── Sensor entity ────────────────────────────────────────────────────────────

class ChronoFolderSensor(SensorEntity):
    """Sensor that exposes folder contents as an attribute."""

    _attr_has_entity_name = True
    _attr_icon            = "mdi:folder-multiple-image"

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self._hass            = hass
        self._entry            = entry
        self._label            = entry.data[CONF_LABEL]
        self._relative_folder  = entry.data[CONF_FOLDER]
        self._www_path         = hass.config.path("www")
        self._abs_folder       = os.path.join(self._www_path, self._relative_folder.lstrip("/"))
        self._filespec         = entry.data[CONF_FILESPEC]
        self._recurse          = entry.data[CONF_RECURSE]
        self._max_photos       = entry.data.get(CONF_MAX_PHOTOS, DEFAULT_MAX_PHOTOS)
        self._files:           list[dict[str, Any]] = []
        self._exif_cache:      dict[str, Any]       = {}
        self._observer:        Any                  = None

        # Pending watcher changes, collected between debounce windows.
        # Maps full_path -> latest event_type ('created'/'modified'/'deleted').
        self._pending_changes: dict[str, str] = {}
        self._pending_lock     = threading.Lock()
        self._debounce_timer:  threading.Timer | None = None
        self._scan_lock        = asyncio.Lock()

        self._attr_unique_id = f"{DOMAIN}_{entry.entry_id}"
        self._attr_name      = self._label

    # ── HA lifecycle ──────────────────────────────────────────────────────────

    async def async_added_to_hass(self) -> None:
        """Start filesystem watcher when entity is added."""
        await self._async_refresh()
        if WATCHDOG_AVAILABLE:
            await self._hass.async_add_executor_job(self._start_watcher)

    async def async_will_remove_from_hass(self) -> None:
        """Stop filesystem watcher and cancel any pending debounce timer."""
        if self._debounce_timer is not None:
            self._debounce_timer.cancel()
            self._debounce_timer = None
        if self._observer is not None:
            await self._hass.async_add_executor_job(self._stop_watcher)

    # ── Watcher ───────────────────────────────────────────────────────────────

    def _start_watcher(self) -> None:
        """Start watchdog observer in executor thread."""
        handler        = _FolderEventHandler(self._queue_change)
        self._observer = Observer()
        self._observer.schedule(handler, self._abs_folder, recursive=self._recurse)
        self._observer.start()
        _LOGGER.debug("chrono_folder: watching %s", self._abs_folder)

    def _stop_watcher(self) -> None:
        """Stop watchdog observer."""
        if self._observer is not None:
            self._observer.stop()
            self._observer.join()
            self._observer = None
            _LOGGER.debug("chrono_folder: stopped watching %s", self._abs_folder)

    def _queue_change(self, event_type: str, full_path: str) -> None:
        """Called from the watchdog thread for every relevant file event.
        Records the latest event type per path and (re)starts the debounce
        timer. Runs entirely on the watchdog thread.
        """
        filename = os.path.basename(full_path)
        if not _matches_filespec(filename, self._filespec):
            return

        with self._pending_lock:
            self._pending_changes[full_path] = event_type
            if self._debounce_timer is not None:
                self._debounce_timer.cancel()
            self._debounce_timer = threading.Timer(
                DEBOUNCE_SECONDS, self._on_debounce_elapsed
            )
            self._debounce_timer.daemon = True
            self._debounce_timer.start()

    def _on_debounce_elapsed(self) -> None:
        """Called on the debounce timer thread once changes have settled.
        Hands off the pending changes to the HA event loop for processing.
        """
        with self._pending_lock:
            changes = self._pending_changes
            self._pending_changes = {}
            self._debounce_timer = None

        if not changes:
            return

        self._hass.loop.call_soon_threadsafe(
            lambda: self._hass.async_create_task(self._async_process_changes(changes))
        )

    # ── Incremental change processing ───────────────────────────────────────

    async def _async_process_changes(self, changes: dict[str, str]) -> None:
        """Apply a batch of debounced file changes incrementally.
        Falls back to a full rescan if any deletion occurs while the list
        is at the max_photos cap, so a freed slot can be backfilled from disk.
        """
        async with self._scan_lock:
            deletes = [p for p, t in changes.items() if t == "deleted"]
            creates_or_modifies = [p for p, t in changes.items() if t != "deleted"]

            at_cap = len(self._files) >= self._max_photos
            deleting_existing = any(
                any(e[FILE_PATH] == p for e in self._files) for p in deletes
            )

            if at_cap and deleting_existing:
                # A slot may free up beyond the current cap - only a full
                # rescan can correctly determine the backfill candidate.
                # Call the internal helper directly - the lock is already held.
                await self._async_refresh_locked()
                return

            # Remove deleted files.
            if deletes:
                delete_set = set(deletes)
                self._files = [e for e in self._files if e[FILE_PATH] not in delete_set]

            # Add or update created/modified files, respecting the hard cap.
            for full_path in creates_or_modifies:
                existing_index = next(
                    (i for i, e in enumerate(self._files) if e[FILE_PATH] == full_path),
                    None,
                )
                entry = await self._hass.async_add_executor_job(
                    _build_single_entry_by_path,
                    full_path,
                    self._www_path,
                    self._relative_folder,
                    self._exif_cache,
                )
                if entry is None:
                    # File vanished or unreadable between event and processing.
                    if existing_index is not None:
                        del self._files[existing_index]
                    continue

                if existing_index is not None:
                    self._files[existing_index] = entry
                elif len(self._files) < self._max_photos:
                    self._files.append(entry)
                # else: at cap, new file is silently not added (hard limit).

            self._files.sort(key=lambda e: e[FILE_NAME])

        if self.hass is not None and self.entity_id:
            self.async_write_ha_state()

    # ── Scan ──────────────────────────────────────────────────────────────────

    async def _async_refresh_locked(self) -> None:
        """Run folder scan and update self._files.
        Caller must already hold self._scan_lock. Does not write HA state -
        callers are responsible for that after the lock is released.
        """
        files = await self._hass.async_add_executor_job(
            _scan_folder,
            self._www_path,
            self._relative_folder,
            self._filespec,
            self._recurse,
            self._max_photos,
            self._exif_cache,
        )
        self._files = files

    async def _async_refresh(self) -> None:
        """Run folder scan in executor and update state, holding self._scan_lock
        so this cannot interleave with incremental watcher updates.
        Only calls async_write_ha_state when the entity is already registered.
        """
        async with self._scan_lock:
            await self._async_refresh_locked()
        if self.hass is not None and self.entity_id:
            self.async_write_ha_state()

    async def async_update(self) -> None:
        """Called by HA for a manual refresh."""
        async with self._scan_lock:
            await self._async_refresh_locked()

    # ── State and attributes ──────────────────────────────────────────────────

    @property
    def native_value(self) -> int:
        """State is the number of files currently in the list."""
        return len(self._files)

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        """Expose config parameters and file list as attributes."""
        return {
            ATTR_LABEL:      self._label,
            ATTR_FOLDER:     self._relative_folder,
            ATTR_FILESPEC:   self._filespec,
            ATTR_RECURSE:    self._recurse,
            ATTR_MAX_PHOTOS: self._max_photos,
            ATTR_FILES:      self._files,
        }
