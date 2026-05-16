--- Lists available versions for a pip package or Python git repository.
---
--- Tool name format:  PACKAGE_SPEC[|PATCH_SOURCE]
---   PACKAGE_SPEC  – a PyPI package name (e.g. "black") or a pip git URL
---                   (e.g. "git+https://github.com/user/repo.git")
---   PATCH_SOURCE  – optional; separated from PACKAGE_SPEC by "|"
---                   gist:USER/GIST_ID          – raw content of a GitHub Gist
---                   https://…  or  http://…    – direct URL to a .diff/.patch file
---                   /absolute/path             – local patch file
---
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions
--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx) -- luacheck: ignore
    local tool = ctx.tool

    if not tool or tool == "" then
        error("Tool name cannot be empty")
    end

    local strings = require("strings")
    local http = require("http")
    local json = require("json")

    -- Extract package spec (the part before the first "|")
    local parts = strings.split(tool, "|")
    local package_spec = strings.trim_space(parts[1])

    -- Git repositories do not have discrete PyPI versions; return "HEAD" as the
    -- only listable version.  Users can still pin to a specific tag / commit via
    -- the version field in mise.toml.
    if strings.has_prefix(package_spec, "git+") then
        return { versions = { "HEAD" } }
    end

    -- Extract the base package name, stripping any extras notation such as
    -- "black[d]" → "black".  The first match stops at "[" so extras are
    -- already excluded; gsub then trims any trailing non-alphanumeric chars
    -- (e.g. trailing hyphen from an invalid name).
    local package_name = package_spec:match("^([%w][%w%-%._%+]*)")
    if not package_name then
        error("Invalid package name: " .. package_spec)
    end
    package_name = package_name:gsub("[^%w]+$", "")

    -- Query the PyPI JSON API
    local resp, err = http.get({ url = "https://pypi.org/pypi/" .. package_name .. "/json" })
    if err then
        error("Failed to fetch versions for '" .. package_name .. "': " .. tostring(err))
    end

    if resp.status_code ~= 200 then
        error("Package '" .. package_name .. "' not found on PyPI (HTTP " .. resp.status_code .. ")")
    end

    local data = json.decode(resp.body)
    local versions = {}

    -- The "releases" object maps version string → array of distribution files.
    -- Only include versions that have at least one published file.
    if data.releases then
        for version_str, files in pairs(data.releases) do
            if #files > 0 then
                table.insert(versions, version_str)
            end
        end
    end

    if #versions == 0 then
        error("No versions found for '" .. package_name .. "'")
    end

    -- Try semver sort; fall back to lexicographic sort for PEP 440 versions
    -- that are not valid semver (e.g. "23.1", "1.0a1").
    local ok, sorted = pcall(function()
        local semver_mod = require("semver")
        return semver_mod.sort(versions)
    end)
    if ok and sorted then
        versions = sorted
    else
        table.sort(versions)
    end

    return { versions = versions }
end
