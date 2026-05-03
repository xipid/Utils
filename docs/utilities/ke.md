# KeePassXC Automator (`ke.sh`)

## Overview

`ke.sh` is a specialized utility designed to bridge the gap between Linux system authentication and the KeePassXC password manager. It automates the process of unlocking your password database during the login sequence.

## Key Features

- **PAM Integration**: Hooks into the PAM (Pluggable Authentication Modules) stack to capture the login password.
- **Automated Unlock**: Uses the captured password to immediately unlock the KeePassXC database upon session start.
- **Secret Service Management**: Automatically terminates `gnome-keyring-daemon` to allow KeePassXC to serve as the primary Secret Service provider.
- **Auto-Provisioning**: Automatically downloads or creates a database if one is not found.
- **Dependency Resolution**: Detects the package manager and installs required dependencies (`keepassxc`, `libsecret`, etc.).

## Installation

To install the utility and configure PAM integration, run:

```bash
sudo ./ke.sh -i
```

## Usage

### Modes of Operation

- `-i`: Installation mode (requires root).
- `-u <user>`: PAM mode (used internally by the PAM stack).
- `-d`: Desktop autostart mode (launched within the user session).

### Configuration

The utility looks for configuration and database files in:
- `~/.config/keepassxc/keepassxc.ini`
- `~/.config/keepassxc/master.kdbx`

## Technical Details

The script stashes the password in secure shared memory (`/dev/shm`) with restricted permissions (`600`) and a self-destruct timer (120 seconds) to ensure security while allowing the desktop application to access it for unlocking.
