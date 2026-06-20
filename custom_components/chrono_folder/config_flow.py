from __future__ import annotations

import os
import voluptuous as vol

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.helpers import selector

from .const import (
    DOMAIN,
    CONF_LABEL,
    CONF_FOLDER,
    CONF_FILESPEC,
    CONF_RECURSE,
    CONF_MAX_PHOTOS,
    DEFAULT_FILESPEC,
    DEFAULT_RECURSE,
    DEFAULT_MAX_PHOTOS,
)

__version__ = "config_flow.py 0.0.8"
# v0.0.8: Add max_photos field to config and options flow schemas;
#          coerce to int to guard against NumberSelector returning float
# v0.0.7: Store folder with exactly one leading slash, no trailing slash
# v0.0.6: Folder input is now relative to www - normalize slashes, validate against hass www path
# v0.0.5: Replace plain str/bool schema types with selectors to enable placeholder text in fields
# v0.0.4: Add options flow to allow editing existing config entries
# v0.0.3: Move imports above version info to fix SyntaxError - remove FlowResult import
# v0.0.2: Remove unique_id check on folder path - same folder with different filespecs is valid
# v0.0.1: Initial release

# ─── Validation ───────────────────────────────────────────────────────────────

def _normalize_folder(folder: str) -> str:
    """Normalize the relative folder path to exactly one leading slash,
    no trailing slash. Accepts input with or without leading/trailing slashes.
    """
    stripped = folder.strip().strip("/")
    return f"/{stripped}"


def _validate_folder(www_path: str, relative_folder: str) -> bool:
    """Return True if www_path/relative_folder exists and is a directory.
    relative_folder is stored with a leading slash; strip it before joining
    so os.path.join does not treat it as an absolute path.
    """
    return os.path.isdir(os.path.join(www_path, relative_folder.lstrip("/")))


def _text() -> selector.TextSelector:
    """Return a standard single-line text selector."""
    return selector.TextSelector(
        selector.TextSelectorConfig(type=selector.TextSelectorType.TEXT)
    )


def _bool() -> selector.BooleanSelector:
    """Return a boolean selector."""
    return selector.BooleanSelector()


def _number(min_value: int = 1) -> selector.NumberSelector:
    """Return a number selector with box mode."""
    return selector.NumberSelector(
        selector.NumberSelectorConfig(min=min_value, mode=selector.NumberSelectorMode.BOX)
    )


# ─── Config flow ──────────────────────────────────────────────────────────────

class ChronoFolderConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Config flow for Chrono Folder."""

    VERSION = 1

    @staticmethod
    def async_get_options_flow(config_entry):
        """Return the options flow handler."""
        return ChronoFolderOptionsFlow(config_entry)

    async def async_step_user(
        self, user_input: dict | None = None
    ):
        """Handle the initial step."""
        errors: dict[str, str] = {}

        if user_input is not None:
            folder = _normalize_folder(user_input[CONF_FOLDER])
            www    = self.hass.config.path("www")

            valid = await self.hass.async_add_executor_job(
                _validate_folder, www, folder
            )
            if not valid:
                errors[CONF_FOLDER] = "invalid_folder"
            else:
                return self.async_create_entry(
                    title=user_input[CONF_LABEL],
                    data={
                        CONF_LABEL:      user_input[CONF_LABEL],
                        CONF_FOLDER:     folder,
                        CONF_FILESPEC:   user_input.get(CONF_FILESPEC,   DEFAULT_FILESPEC),
                        CONF_RECURSE:    user_input.get(CONF_RECURSE,    DEFAULT_RECURSE),
                        CONF_MAX_PHOTOS: user_input.get(CONF_MAX_PHOTOS, DEFAULT_MAX_PHOTOS),
                    },
                )

        schema = vol.Schema(
            {
                vol.Required(CONF_LABEL):                                _text(),
                vol.Required(CONF_FOLDER):                               _text(),
                vol.Optional(CONF_FILESPEC,   default=DEFAULT_FILESPEC):   _text(),
                vol.Optional(CONF_RECURSE,    default=DEFAULT_RECURSE):    _bool(),
                vol.Optional(CONF_MAX_PHOTOS, default=DEFAULT_MAX_PHOTOS): vol.All(_number(), vol.Coerce(int)),
            }
        )

        return self.async_show_form(
            step_id="user",
            data_schema=schema,
            errors=errors,
        )


# ─── Options flow ──────────────────────────────────────────────────────────────

class ChronoFolderOptionsFlow(config_entries.OptionsFlow):
    """Options flow for editing an existing Chrono Folder entry."""

    def __init__(self, config_entry: config_entries.ConfigEntry) -> None:
        self._config_entry = config_entry

    async def async_step_init(
        self, user_input: dict | None = None
    ):
        """Handle the options step."""
        errors: dict[str, str] = {}

        if user_input is not None:
            folder = _normalize_folder(user_input[CONF_FOLDER])
            www    = self.hass.config.path("www")

            valid = await self.hass.async_add_executor_job(
                _validate_folder, www, folder
            )
            if not valid:
                errors[CONF_FOLDER] = "invalid_folder"
            else:
                return self.async_create_entry(
                    title=user_input[CONF_LABEL],
                    data={
                        CONF_LABEL:      user_input[CONF_LABEL],
                        CONF_FOLDER:     folder,
                        CONF_FILESPEC:   user_input.get(CONF_FILESPEC,   DEFAULT_FILESPEC),
                        CONF_RECURSE:    user_input.get(CONF_RECURSE,    DEFAULT_RECURSE),
                        CONF_MAX_PHOTOS: user_input.get(CONF_MAX_PHOTOS, DEFAULT_MAX_PHOTOS),
                    },
                )

        current = self._config_entry.data

        schema = vol.Schema(
            {
                vol.Required(CONF_LABEL,      default=current.get(CONF_LABEL,      "")): _text(),
                vol.Required(CONF_FOLDER,     default=current.get(CONF_FOLDER,     "")): _text(),
                vol.Optional(CONF_FILESPEC,   default=current.get(CONF_FILESPEC,   DEFAULT_FILESPEC)):   _text(),
                vol.Optional(CONF_RECURSE,    default=current.get(CONF_RECURSE,    DEFAULT_RECURSE)):    _bool(),
                vol.Optional(CONF_MAX_PHOTOS, default=current.get(CONF_MAX_PHOTOS, DEFAULT_MAX_PHOTOS)): vol.All(_number(), vol.Coerce(int)),
            }
        )

        return self.async_show_form(
            step_id="init",
            data_schema=schema,
            errors=errors,
        )
