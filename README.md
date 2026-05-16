# mise-pipx-patch

A [mise](https://github.com/jdx/mise) backend plugin that installs pip packages and Python git repositories into isolated virtual environments, with optional support for applying patches from a **GitHub Gist**, a **direct URL**, or a **local file** before installation.

## Quick Start

```bash
# Install the plugin
mise plugin install pipx-patch https://github.com/nakayama900/mise-pipx-patch

# Install a PyPI package
mise use pipx-patch:black@latest

# Install a PyPI package with a patch from a GitHub Gist
mise use 'pipx-patch:black|gist:nakayama900/abc123def456@23.1.0'

# Install from a git repository with a patch from a URL
mise use 'pipx-patch:git+https://github.com/psf/black|https://example.com/my.patch@HEAD'
```

## Tool Name Format

```
PACKAGE_SPEC[|PATCH_SOURCE]
```

| Part | Description |
|------|-------------|
| `PACKAGE_SPEC` | PyPI package name (e.g. `black`) or pip git URL (e.g. `git+https://github.com/user/repo.git`) |
| `\|PATCH_SOURCE` | *(optional)* Patch to apply before installing, separated by a `\|` character |

### Supported patch sources

| Format | Example | Description |
|--------|---------|-------------|
| `gist:USER/GIST_ID` | `gist:nakayama900/abc123` | Fetches the raw content of a GitHub Gist |
| `gist:USER/GIST_ID/FILENAME` | `gist:nakayama900/abc123/fix.patch` | Fetches a specific file from a Gist |
| `https://…` | `https://example.com/fix.diff` | Downloads a patch from any HTTPS URL |
| `/absolute/path` | `/home/user/patches/fix.diff` | Uses a local patch file |

### Examples in `mise.toml`

```toml
[tools]
# Plain PyPI installation (no patch)
"pipx-patch:black" = "latest"
"pipx-patch:httpie" = "3.2.1"

# PyPI package with a patch from a GitHub Gist
"pipx-patch:black|gist:nakayama900/abc123def456" = "23.1.0"

# PyPI package with a patch from a URL
"pipx-patch:requests|https://gist.githubusercontent.com/user/id/raw/fix.patch" = "2.31.0"

# PyPI package with a local patch file
"pipx-patch:mypackage|/home/user/patches/mypackage-fix.diff" = "1.2.3"

# Python git repository (no patch)
"pipx-patch:git+https://github.com/psf/black" = "HEAD"

# Python git repository with a patch from a Gist
"pipx-patch:git+https://github.com/psf/black|gist:nakayama900/abc123" = "HEAD"
```

## How It Works

1. **`BackendListVersions`** – Queries the [PyPI JSON API](https://pypi.org/pypi/PACKAGE/json) to list all published versions.  For git repositories, returns `["HEAD"]` so you can always check out any branch or tag.

2. **`BackendInstall`** – Creates an isolated Python virtual environment at `install_path/venv`, then:
   - *Without a patch*: runs `pip install PACKAGE==VERSION` (or `pip install git+URL@REF`).
   - *With a patch*: downloads the source distribution (or clones the git repo), downloads the patch, applies it with `patch -p1`, and then runs `pip install .` from the patched source.

3. **`BackendExecEnv`** – Adds `install_path/venv/bin` to `PATH` so that installed scripts (e.g. `black`, `http`, …) are immediately available.

## Requirements

- Python 3 with the `venv` module (standard library)
- `pip` (bundled with Python 3.4+)
- `git` (only when installing from git repositories)
- `patch` (only when applying patches; available on all Unix-like systems)

## Development

### Link the plugin locally

```bash
mise plugin link --force pipx-patch .
```

### Run the test suite

```bash
mise run test
```

### Lint

```bash
mise run lint
```

### Format Lua code

```bash
mise run format
```

## Files

| File | Purpose |
|------|---------|
| `metadata.lua` | Plugin metadata |
| `hooks/backend_list_versions.lua` | Lists available PyPI versions |
| `hooks/backend_install.lua` | Installs the tool (with optional patch) |
| `hooks/backend_exec_env.lua` | Adds the venv bin dir to PATH |
| `mise-tasks/test` | Integration test script |

## License

MIT
