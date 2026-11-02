--- Installs a pip package or Python git repository, with an optional patch.
---
--- Tool name format:  PACKAGE_SPEC[|PATCH_SOURCE]
---   PACKAGE_SPEC  – PyPI package name (e.g. "black") or pip git URL
---                   (e.g. "git+https://github.com/user/repo.git")
---   PATCH_SOURCE  – optional patch source, separated from PACKAGE_SPEC by "|":
---                   gist:USER/GIST_ID          – fetches raw content of a Gist
---                   https://…  or  http://…    – direct URL to a .diff/.patch file
---                   /absolute/path             – local patch file (used as-is)
---
--- The tool is installed into an isolated virtualenv at install_path/venv.
--- BackendExecEnv adds install_path/venv/bin to PATH.
---
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
--- Quote a string for safe use as a single POSIX shell argument.
--- @param s string
--- @return string
local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- Build the raw URL for a Gist patch source ("USER/GIST_ID[/FILENAME]").
--- GitHub serves raw gists at .../USER/GIST_ID/raw[/FILENAME].
--- @param gist_path string
--- @return string
local function gist_raw_url(gist_path)
    local user, id, filename = gist_path:match("^([^/]+)/([^/]+)/?(.*)$")
    if not user then
        error("Invalid Gist spec, expected gist:USER/GIST_ID[/FILENAME]: " .. gist_path)
    end
    local url = "https://gist.githubusercontent.com/" .. user .. "/" .. id .. "/raw"
    if filename ~= "" then
        url = url .. "/" .. filename
    end
    return url
end

--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx) -- luacheck: ignore
    local tool = ctx.tool
    local version = ctx.version
    local install_path = ctx.install_path

    if not tool or tool == "" then
        error("Tool name cannot be empty")
    end
    if not install_path or install_path == "" then
        error("Install path cannot be empty")
    end

    local strings = require("strings")
    local cmd = require("cmd")
    local http = require("http")
    local log = require("log")

    -- -------------------------------------------------------------------------
    -- Parse the tool spec
    -- -------------------------------------------------------------------------
    local parts = strings.split(tool, "|")
    local package_spec = strings.trim_space(parts[1])
    local patch_source = nil
    if #parts > 1 then
        local ps = strings.trim_space(parts[2])
        if ps ~= "" then
            patch_source = ps
        end
    end

    local is_git = strings.has_prefix(package_spec, "git+")

    -- -------------------------------------------------------------------------
    -- Prepare the install directory and create a virtual environment
    -- -------------------------------------------------------------------------
    cmd.exec("mkdir -p " .. q(install_path))
    local venv_path = install_path .. "/venv"
    log.info("Creating virtual environment at " .. venv_path)
    cmd.exec("python3 -m venv " .. q(venv_path))
    local pip = q(venv_path .. "/bin/pip")

    -- -------------------------------------------------------------------------
    -- Determine whether we need to apply a patch
    -- -------------------------------------------------------------------------
    if patch_source then
        -- Work from source: download/clone → apply patch → pip install .
        local src_dir = install_path .. "/src"
        cmd.exec("mkdir -p " .. q(src_dir))

        if is_git then
            -- Clone a Python git repository
            -- pip git-URL format: git+https://host/repo.git[@ref]
            local git_url = package_spec:sub(5) -- strip leading "git+"
            -- Strip any embedded @ref; we will check out the correct ref later
            local url_base = git_url:match("^([^@]+)") or git_url
            -- Determine the revision to check out (version > embedded ref)
            local ref = git_url:match("@(.+)$")
            if version and version ~= "HEAD" and version ~= "latest" then
                ref = version
            end

            log.info("Cloning " .. url_base)
            cmd.exec("git clone " .. q(url_base) .. " " .. q(src_dir))
            if ref and ref ~= "" then
                log.info("Checking out " .. ref)
                cmd.exec("git -C " .. q(src_dir) .. " checkout " .. q(ref))
            end
        else
            -- Download the PyPI source distribution (.tar.gz or .zip)
            local package_name = package_spec:match("^([%w][%w%-%._%+]*)")
            if not package_name then
                error("Invalid package name: " .. package_spec)
            end
            package_name = package_name:gsub("[^%w]+$", "")

            local version_spec = ""
            if version and version ~= "HEAD" and version ~= "latest" then
                version_spec = "==" .. version
            end

            log.info("Downloading source for " .. package_name .. version_spec)
            cmd.exec(
                pip
                    .. " download --no-deps --no-binary :all: -d "
                    .. q(src_dir)
                    .. " "
                    .. q(package_name .. version_spec)
            )

            -- Find the downloaded archive and decompress it
            local archive = cmd.exec("find " .. q(src_dir) .. " -maxdepth 1 -name '*.tar.gz' | head -1")
            archive = strings.trim_space(archive)
            if archive == "" then
                archive = cmd.exec("find " .. q(src_dir) .. " -maxdepth 1 -name '*.zip' | head -1")
                archive = strings.trim_space(archive)
            end
            if archive == "" then
                error("No source archive found for " .. package_name .. version_spec)
            end

            local extract_dir = src_dir .. "/extracted"
            cmd.exec("mkdir -p " .. q(extract_dir))
            local archiver = require("archiver")
            archiver.decompress(archive, extract_dir)

            -- pip source distributions unpack to a single PACKAGE-VERSION/ dir
            local extracted =
                cmd.exec("find " .. q(extract_dir) .. " -maxdepth 1 -mindepth 1 -type d | head -1")
            extracted = strings.trim_space(extracted)
            if extracted ~= "" then
                src_dir = extracted
            else
                src_dir = extract_dir
            end
        end

        -- ---------------------------------------------------------------------
        -- Obtain the patch file
        -- ---------------------------------------------------------------------
        local patch_file -- path to the .diff/.patch file on disk

        if strings.has_prefix(patch_source, "gist:") then
            -- Format: gist:USER/GIST_ID  or  gist:USER/GIST_ID/FILENAME
            local gist_path = patch_source:sub(6) -- strip "gist:"
            local raw_url = gist_raw_url(gist_path)
            log.info("Downloading patch from Gist: " .. raw_url)
            patch_file = install_path .. "/patch.diff"
            local ok, dl_err = pcall(http.download_file, { url = raw_url }, patch_file)
            if not ok then
                error("Failed to download patch from Gist '" .. gist_path .. "': " .. tostring(dl_err))
            end
        elseif strings.has_prefix(patch_source, "https://") or strings.has_prefix(patch_source, "http://") then
            log.info("Downloading patch from URL: " .. patch_source)
            patch_file = install_path .. "/patch.diff"
            local ok, dl_err = pcall(http.download_file, { url = patch_source }, patch_file)
            if not ok then
                error("Failed to download patch from URL '" .. patch_source .. "': " .. tostring(dl_err))
            end
        else
            -- Treat as a local file path; use it directly
            local file = require("file")
            if not file.exists(patch_source) then
                error("Local patch file not found: " .. patch_source)
            end
            patch_file = patch_source
        end

        -- ---------------------------------------------------------------------
        -- Apply the patch
        -- ---------------------------------------------------------------------
        log.info("Applying patch " .. patch_file .. " to " .. src_dir)
        cmd.exec("patch -p1 -d " .. q(src_dir) .. " < " .. q(patch_file))

        -- ---------------------------------------------------------------------
        -- Install the patched package into the virtualenv
        -- ---------------------------------------------------------------------
        log.info("Installing patched package from " .. src_dir)
        cmd.exec(pip .. " install " .. q(src_dir))
    else
        -- No patch – install directly with pip
        if is_git then
            local install_spec = package_spec
            -- Append version as @ref only when not already present and it is meaningful
            if version and version ~= "HEAD" and version ~= "latest" then
                if not install_spec:match("@[^/]+") then
                    install_spec = install_spec .. "@" .. version
                end
            end
            log.info("Installing from git: " .. install_spec)
            cmd.exec(pip .. " install " .. q(install_spec))
        else
            local package_name = package_spec:match("^([%w][%w%-%._%+]*)")
            if not package_name then
                error("Invalid package name: " .. package_spec)
            end
            package_name = package_name:gsub("[^%w]+$", "")

            local version_spec = ""
            if version and version ~= "HEAD" and version ~= "latest" then
                version_spec = "==" .. version
            end

            log.info("Installing " .. package_name .. version_spec)
            cmd.exec(pip .. " install " .. q(package_name .. version_spec))
        end
    end

    return {}
end
