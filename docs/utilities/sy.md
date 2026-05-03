# Rclone Sync (`sy.sh`)

## Overview

`sy.sh` is an advanced wrapper for Rclone, providing a streamlined interface for synchronizing local directories with remote storage or external drives. It features an extensive filtering system to exclude unnecessary system and development bloat.

## Key Features

- **Bidirectional Sync**: Supports both `PUSH` (Local to Remote) and `PULL` (Remote to Local) modes.
- **Smart Filtering**: Includes a massive list of pre-configured exclusions (e.g., `node_modules`, `.cache`, `.git`, browser caches).
- **USB Support**: Automatically detects and configures external USB drives as synchronization targets.
- **Minimal Mode**: Optionally restricts synchronization to critical directories only (`Documents`, `rclone` config, `keepassxc` config).
- **Performance Optimized**: Uses high-concurrency flags (`--transfers 32`, `--checkers 64`) for maximum throughput.

## Usage

### Syntax

```bash
./sy.sh [OPTIONS]
```

### Options

- `-h, --help`: Display help menu.
- `-m, --minimal`: Enable minimal mode (restricted inclusions).
- `-p, --pull`: Reverse synchronization direction (Remote -> Local).
- `-f, --from <dir>`: Set source directory (Default: `$HOME`).
- `-t, --to <dest>`: Set destination target (Default: `GDrive:`).
- `-u, --usb [name]`: Use a USB drive as the destination.
- `-F, --filter <file>`: Append custom Rclone filter rules from a file.

## Examples

**Backup Home to Google Drive:**
```bash
./sy.sh
```

**Restore Documents from Google Drive (Minimal):**
```bash
./sy.sh -m -p
```

**Backup to an external USB drive named "STORAGE":**
```bash
./sy.sh -u STORAGE
```

## Internal Exclusions

The script automatically filters out:
- System files (`.ssh` keys, trash, sockets).
- Browser caches and temporary data.
- Development dependencies (`node_modules`, `vendor`, `venv`).
- Compilation artifacts (`build/`, `dist/`, `.o`, `.a`).
