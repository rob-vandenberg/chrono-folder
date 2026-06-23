__version__ = "const.py 0.0.5"
# v0.0.5: Rename fileType to fileNameExt; add fileType (category), fileWidth, fileHeight
# v0.0.4: Add CONF_MAX_PHOTOS, DEFAULT_MAX_PHOTOS, ATTR_MAX_PHOTOS, DEBOUNCE_SECONDS
# v0.0.3: Add ATTR_FOLDER, ATTR_FILESPEC, ATTR_RECURSE sensor attributes
# v0.0.2: Drop FILE_FOLDER, add FILE_PATH and FILE_URL
# v0.0.1: Initial release

# ─── Domain ───────────────────────────────────────────────────────────────────
DOMAIN = "chrono_folder"

# ─── Config entry keys ────────────────────────────────────────────────────────
CONF_LABEL      = "label"
CONF_FOLDER     = "folder"
CONF_FILESPEC   = "filespec"
CONF_RECURSE    = "recurse"
CONF_MAX_PHOTOS = "max_photos"

# ─── Defaults ─────────────────────────────────────────────────────────────────
DEFAULT_FILESPEC   = "*.*"
DEFAULT_RECURSE    = False
DEFAULT_MAX_PHOTOS = 200

# ─── Watcher debounce ─────────────────────────────────────────────────────────
DEBOUNCE_SECONDS = 10

# ─── Sensor attribute keys ────────────────────────────────────────────────────
ATTR_FILES      = "files"
ATTR_LABEL      = "label"
ATTR_FOLDER     = "folder"
ATTR_FILESPEC   = "filespec"
ATTR_RECURSE    = "recurse"
ATTR_MAX_PHOTOS = "maxPhotos"

# ─── Per-file field names ─────────────────────────────────────────────────────
FILE_PATH       = "filePath"
FILE_URL        = "fileURL"
FILE_NAME       = "fileName"
FILE_NAME_EXT   = "fileNameExt"
FILE_TYPE       = "fileType"
FILE_DATE       = "fileDate"
FILE_TIME       = "fileTime"
FILE_SIZE       = "fileSize"
FILE_WIDTH      = "fileWidth"
FILE_HEIGHT     = "fileHeight"

# ─── EXIF prefix ──────────────────────────────────────────────────────────────
EXIF_PREFIX     = "exif"
