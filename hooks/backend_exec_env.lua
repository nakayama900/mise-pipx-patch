--- Sets up the environment so that executables installed by BackendInstall are
--- available on PATH.
---
--- The tool is installed into an isolated virtualenv at install_path/venv.
--- Adding install_path/venv/bin to PATH exposes all scripts installed by pip
--- (e.g. "black", "mypy", "httpie", …).
---
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv
--- @param ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(ctx) -- luacheck: ignore
    local install_path = ctx.install_path
    local file = require("file")

    -- Point to the virtualenv's bin directory that BackendInstall created
    local bin_path = file.join_path(install_path, "venv", "bin")

    return {
        env_vars = {
            { key = "PATH", value = bin_path },
        },
    }
end
