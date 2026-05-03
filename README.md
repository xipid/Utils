# Utils: High-Performance Linux Shell Utilities

A professional suite of shell utilities designed to automate system administration, enhance workflows, and streamline package management on Linux systems.

## Documentation

Comprehensive documentation for all utilities is available in the `docs/` directory.

- **[Introduction](docs/intro.md)**: Overview and philosophy.
- **[KeePassXC Automator](docs/utilities/ke.md)**: Secure PAM integration for KeePassXC.
- **[Rclone Sync](docs/utilities/sy.md)**: Advanced Rclone wrapper with smart filtering.
- **[Package Installer](docs/utilities/ipkg.md)**: Universal installer for multiple formats and sources.
- **[Full Documentation Index](docs/SUMMARY.md)**: GitBook-style navigation.

## Core Utilities

| Utility | Description | Entry Point |
| :--- | :--- | :--- |
| **KeePassXC Automator** | Bridges system login with KeePassXC database unlocking. | `ke.sh` |
| **Rclone Sync** | Optimizes remote synchronization with robust exclusion rules. | `sy.sh` |
| **Package Installer** | Automates software installation from GitHub, URLs, and archives. | `ipkg.sh` |
| **GitHub Resolver** | Programmatically resolves GitHub release asset URLs. | `ghr.sh` |
| **QEMU Wrapper** | Facilitates cross-architecture execution via compiled wrappers. | `wrap.sh` |

## Installation

Utilities can be run directly from the repository. For utilities like `ke.sh` that require system integration, use the installation flag:

```bash
sudo ./ke.sh -i
```

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

---

*Precision Automation for Linux Systems.*

