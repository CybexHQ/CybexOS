"""Wiz's desktop tools: what the Cybex OS tool server (mcp.py) offers the agent.

Each tool has a JSON schema for the agent, a kind and the plain words the
step list shows. The kinds decide what may run without asking:

- "look" reads and changes nothing. A question answered alongside another,
  and a routine, may use only these.
- "change" changes a preference, the wallpaper or a routine. It is recorded
  in the change log (changes.py), so it can be undone.
- "act" acts on windows and apps. It is not undoable, but nothing is lost.
- "install" adds or removes an app for this account. It asks first under
  Ask first, and is recorded so it can be undone.

`where` says who carries a tool out: the service itself, or the shell (the
quickshell client), which knows the settings schema, the windows and the
wallpaper folder. The service enforces the kinds; the agent's own
permission prompt for these tools is always answered yes (policy.py).
"""

from __future__ import annotations


SERVER = "cybexos"

LOOK, CHANGE, ACT, INSTALL = "look", "change", "act", "install"

SCHEDULE_SCHEMA = {
    "type": "object",
    "properties": {
        "kind": {"type": "string", "enum": ["daily", "weekly", "monthly", "update"],
                 "description": "daily, weekly, monthly, or update (after each kept Cybex OS update)"},
        "time": {"type": "string", "description": "HH:MM in local time, for daily, weekly and monthly"},
        "weekday": {"type": "integer", "minimum": 0, "maximum": 6, "description": "0 is Monday, for weekly"},
        "day": {"type": "integer", "minimum": 1, "maximum": 28, "description": "Day of the month, for monthly"},
    },
    "required": ["kind"],
}


def _schema(properties=None, required=()):
    schema = {"type": "object", "properties": properties or {}, "additionalProperties": False}
    if required:
        schema["required"] = list(required)
    return schema


TOOLS = {
    "desktop_status": {
        "kind": LOOK, "where": "shell", "label": "Looked at the desktop",
        "description": "The focused window, every open window (address, app, title, workspace), the "
                       "workspaces, the displays, the theme and the wallpaper.",
        "schema": _schema(),
    },
    "settings_search": {
        "kind": LOOK, "where": "shell", "label": "Looked up settings",
        "description": "Searches the Cybex OS settings by words. Each result has the settings key, its label, "
                       "its page, its current and default value and its type. Use the key with settings_set.",
        "schema": _schema({"query": {"type": "string"}}, ["query"]),
    },
    "settings_get": {
        "kind": LOOK, "where": "shell", "label": "Read your preferences",
        "description": "The current value of the given settings keys (all keys when none are given).",
        "schema": _schema({"keys": {"type": "array", "items": {"type": "string"}}}),
    },
    "settings_set": {
        "kind": CHANGE, "where": "shell", "label": "Changed a preference",
        "description": "Sets one Cybex OS setting; it applies at once and the person can undo it. The value "
                       "must be one the setting accepts: check settings_search first. Settings of the "
                       "assistant itself cannot be changed here.",
        "schema": _schema({"key": {"type": "string"}, "value": {}}, ["key", "value"]),
    },
    "wallpaper_search": {
        "kind": LOOK, "where": "service", "label": "Searched Wallhaven",
        "description": "Searches Wallhaven for general, safe wallpapers at least as large as the displays. "
                       "Pass a result's id to wallpaper_set.",
        "schema": _schema({"query": {"type": "string"}}, ["query"]),
    },
    "wallpaper_set": {
        "kind": CHANGE, "where": "shell", "label": "Set the wallpaper",
        "description": "Sets the wallpaper: a Wallhaven id from wallpaper_search (it is downloaded into the "
                       "wallpaper folder), or the file name of an image already in that folder.",
        "schema": _schema({"wallhaven": {"type": "string"}, "file": {"type": "string"}}),
    },
    "app_open": {
        "kind": ACT, "where": "shell", "label": "Opened an app",
        "description": "Opens an installed app by its name or desktop entry id.",
        "schema": _schema({"app": {"type": "string"}}, ["app"]),
    },
    "window_focus": {
        "kind": ACT, "where": "shell", "label": "Focused a window",
        "description": "Focuses the window with this address (from desktop_status).",
        "schema": _schema({"address": {"type": "string"}}, ["address"]),
    },
    "window_move": {
        "kind": ACT, "where": "shell", "label": "Moved a window",
        "description": "Moves the window with this address to a workspace number, without following it.",
        "schema": _schema({"address": {"type": "string"}, "workspace": {"type": "integer", "minimum": 1}},
                          ["address", "workspace"]),
    },
    "window_close": {
        "kind": ACT, "where": "shell", "label": "Closed a window", "always_ask": True,
        "description": "Closes the window with this address. The person is always asked first, because "
                       "the app may have unsaved work.",
        "schema": _schema({"address": {"type": "string"}}, ["address"]),
    },
    "workspace_switch": {
        "kind": ACT, "where": "shell", "label": "Switched workspace",
        "description": "Shows workspace number N on the focused display.",
        "schema": _schema({"workspace": {"type": "integer", "minimum": 1}}, ["workspace"]),
    },
    "software_search": {
        "kind": LOOK, "where": "service", "label": "Searched Flathub",
        "description": "Searches Flathub for apps this account can install. Returns ids for flatpak_install.",
        "schema": _schema({"query": {"type": "string"}}, ["query"]),
    },
    "flatpak_install": {
        "kind": INSTALL, "where": "service", "label": "Installed an app",
        "description": "Installs a Flathub app for this account only (no administrator needed) and waits "
                       "until it is done. System packages still go through cybex software stage.",
        "schema": _schema({"id": {"type": "string"}, "name": {"type": "string"}}, ["id"]),
    },
    "flatpak_remove": {
        "kind": INSTALL, "where": "service", "label": "Removed an app",
        "description": "Removes a Flathub app installed for this account.",
        "schema": _schema({"id": {"type": "string"}, "name": {"type": "string"}}, ["id"]),
    },
    "doctor_run": {
        "kind": LOOK, "where": "service", "label": "Checked this computer",
        "description": "Runs the read-only system check (cybex doctor --json) and returns its report.",
        "schema": _schema(),
    },
    "routine_list": {
        "kind": LOOK, "where": "service", "label": "Looked at your routines",
        "description": "The person's routines: saved questions Wiz asks on a schedule.",
        "schema": _schema(),
    },
    "routine_create": {
        "kind": CHANGE, "where": "service", "label": "Created a routine",
        "description": "Creates a routine: a question Wiz asks on a schedule while the person is logged in. "
                       "A routine only looks and reports; fixes wait for the person. notify is "
                       "\"attention\" (tell the person only when something needs attention) or \"always\".",
        "schema": _schema({"question": {"type": "string"}, "title": {"type": "string"},
                           "schedule": SCHEDULE_SCHEMA,
                           "notify": {"type": "string", "enum": ["attention", "always"]}},
                          ["question", "schedule"]),
    },
    "routine_delete": {
        "kind": CHANGE, "where": "service", "label": "Removed a routine",
        "description": "Removes one of the person's routines by its id.",
        "schema": _schema({"id": {"type": "string"}}, ["id"]),
    },
}

# What the person sees for each tool in the working pill, while it runs.
PRESENT = {
    "desktop_status": "Looking at the desktop", "settings_search": "Looking up settings",
    "settings_get": "Reading your preferences", "settings_set": "Changing a preference",
    "wallpaper_search": "Searching Wallhaven", "wallpaper_set": "Setting the wallpaper",
    "app_open": "Opening an app", "window_focus": "Focusing a window", "window_move": "Moving a window",
    "window_close": "Closing a window", "workspace_switch": "Switching workspace",
    "software_search": "Searching Flathub", "flatpak_install": "Installing an app",
    "flatpak_remove": "Removing an app", "doctor_run": "Checking this computer",
    "routine_list": "Looking at your routines", "routine_create": "Creating a routine",
    "routine_delete": "Removing a routine",
}


def tool_name(qualified):
    """`mcp__cybexos__settings_set` (Claude) or `settings_set` → `settings_set`, else ""."""
    name = str(qualified or "")
    prefix = f"mcp__{SERVER}__"
    if name.startswith(prefix):
        name = name[len(prefix):]
    return name if name in TOOLS else ""


def ours(qualified):
    return str(qualified or "").startswith(f"mcp__{SERVER}__")


def kind(name):
    return TOOLS[name]["kind"] if name in TOOLS else ""


def detail(name, arguments):
    """The grey part of a step: what the tool was pointed at."""
    arguments = arguments if isinstance(arguments, dict) else {}
    for key in ("key", "query", "app", "id", "wallhaven", "file", "question"):
        value = arguments.get(key)
        if isinstance(value, str) and value.strip():
            text = " ".join(value.split())
            return text if len(text) <= 48 else text[:47] + "…"
    if isinstance(arguments.get("workspace"), int):
        return f"workspace {arguments['workspace']}"
    return ""


def listing():
    """The tools/list answer of the MCP server."""
    return [{"name": name, "description": spec["description"], "inputSchema": spec["schema"],
             "annotations": {"readOnlyHint": spec["kind"] == LOOK, "title": spec["label"]}}
            for name, spec in TOOLS.items()]


def validate(name, arguments):
    """A short reason the arguments do not fit the tool's schema, or ""."""
    spec = TOOLS.get(name)
    if spec is None:
        return f"Unknown tool {name}."
    if not isinstance(arguments, dict):
        return "The arguments must be an object."
    schema = spec["schema"]
    for key in schema.get("required", []):
        if key not in arguments:
            return f"{key} is required."
    for key, value in arguments.items():
        expected = schema["properties"].get(key)
        if expected is None:
            return f"Unknown argument {key}."
        kind_name = expected.get("type")
        if kind_name == "string" and not isinstance(value, str):
            return f"{key} must be a string."
        if kind_name == "integer" and (not isinstance(value, int) or isinstance(value, bool)):
            return f"{key} must be a whole number."
        if kind_name == "array" and not isinstance(value, list):
            return f"{key} must be a list."
        if kind_name == "object" and not isinstance(value, dict):
            return f"{key} must be an object."
        if isinstance(value, str) and len(value) > 4000:
            return f"{key} is too long."
    return ""
