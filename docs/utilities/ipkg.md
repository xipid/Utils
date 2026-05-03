# Package Installer (`ipkg.sh`)

## Overview

`ipkg.sh` is a universal software installer that abstracts away the complexity of installing applications from various sources. It handles downloading, extraction, and system integration.

## Key Features

- **Multi-Source Support**: Installs from GitHub repositories, direct URLs, local archives, RPMs, and Flatpaks.
- **Auto-Resolution**: Automatically fetches the latest release assets from GitHub when a repository handle (e.g., `user/repo`) is provided.
- **System Integration**: Automatically creates symlinks in the system path and installs `.desktop` files for menu integration.
- **Privilege Awareness**: Supports both global installation (to `/opt` and `/usr/local/bin`) and user-local installation (to `~/.opt` and `~/.local/bin`).

## Usage

### Syntax

```bash
./ipkg.sh <source> [regex]
```

### Parameters

- `<source>`: Can be a GitHub handle (`owner/repo`), a URL, a git clone URL, or a local file path.
- `[regex]`: Optional regex to match a specific asset name when installing from GitHub releases.

## Examples

**Install from GitHub (latest release):**
```bash
./ipkg.sh xipid/utils
```

**Install a specific architecture from GitHub:**
```bash
./ipkg.sh some-user/project "x86_64"
```

**Install from a URL:**
```bash
./ipkg.sh https://example.com/software.tar.gz
```

## Technical Logic

1.  **Resolution**: If a GitHub handle is provided, it uses the `ghr` utility to find the download URL.
2.  **Environment Check**: Determines whether to install globally (if run as root) or locally.
3.  **Extraction**: Archives are extracted into a dedicated directory in the `.opt` folder.
4.  **Linking**: Executables are symlinked to the binary path, and `.desktop` files are updated with absolute paths before being installed.
