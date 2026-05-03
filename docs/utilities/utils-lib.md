# Shared Library (`utils.sh`)

## Overview

`utils.sh` serves as the core functional library for the repository. It contains the primary logic for the GitHub release resolution and package installation systems, which are exposed via the `ghr.sh` and `ipkg.sh` entry points.

## Exported Functions

### `ghr(repo, [regex])`

Fetches the latest release asset URL for a given GitHub repository.

- **Arguments**:
    - `repo`: Repository handle (e.g., `xipid/utils`).
    - `regex`: Regex for asset matching (optional).
- **Returns**: Echoes the URL to stdout.

### `ipkg(source_path, [asset_regex])`

Installs a package from various sources.

- **Arguments**:
    - `source_path`: GitHub handle, URL, or local file.
    - `asset_regex`: Regex for matching GitHub assets (optional).

## Internal Functions

### `_link_binary(target_dir, name, bin_base)`

An internal helper function used by `ipkg` to:
1.  Scan the installation directory for executables.
2.  Create symlinks in the designated binary directory.
3.  Install and patch `.desktop` files for desktop environment integration.

## Usage in Scripts

To use these functions in your own scripts, source the library:

```bash
source ./utils.sh
```
