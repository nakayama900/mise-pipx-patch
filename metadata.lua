-- metadata.lua
-- Backend plugin metadata and configuration
-- Documentation: https://mise.jdx.dev/backend-plugin-development.html

PLUGIN = { -- luacheck: ignore
    -- Required: Plugin name (will be the backend name users reference)
    name = "pipx-patch",

    -- Required: Plugin version (not the tool versions)
    version = "1.0.0",

    -- Required: Brief description of the backend and tools it manages
    description = "A mise backend plugin that installs pip packages and Python git repositories with optional patches from Gist or local files",

    -- Required: Plugin author/maintainer
    author = "nakayama900",

    -- Optional: Plugin homepage/repository URL
    homepage = "https://github.com/nakayama900/mise-pipx-patch",

    -- Optional: Plugin license
    license = "MIT",

    -- Optional: Important notes for users
    notes = {
        "Requires Python 3 with pip and venv modules to be installed",
        "Patch source is appended to the tool name with a | separator",
        "Supported patch sources: gist:USER/ID, https://... URL, /absolute/path",
    },
}
