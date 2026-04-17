# 🗺️ Roadmap: The Quest for the Best Linux Utils

This is the engineering roadmap for `xipid/utils`. Our goal is to create a suite of tools that make Linux management feel like a superpower.

## 🔐 Security & Secrets
- [ ] **Secret Management Migration**: Automatically migrate existing keys from GNOME Keyring/KWallet to KeePassXC (as requested).
- [ ] **Hardening Suite**: A one-click script to optimize `sysctl` for security, disable unused services (avahi, cups, etc.), and set up a state-of-the-art UFW configuration.
- [ ] **Wireguard Killswitch**: A lightweight wrapper for Wireguard that ensures no traffic leaks if the tunnel drops, with a clean CLI tray notifier.

## ⚙️ System Automation
- [ ] **Universal Dotfiles (`xi-dot`)**: A symlinking engine that supports templates (e.g., using `jinja2` or similar) to allow different configurations for "Server", "Workstation", and "Laptop" from a single source.
- [ ] **ZRAM Optimizer**: Automatic detection of RAM capacity to set up the ideal ZRAM/Swap priority configuration for performance-heavy users.
- [ ] **Theme Sync**: A daemon that watches for system-wide Dark Mode changes (GNOME/KDE) and automatically updates GTK themes, terminal colors, and even VS Code settings.

## 🔋 Performance & Power
- [ ] **Power Profiles Pro**: Intelligent switching between `balanced` and `power-saver` based on active processes (e.g., if `steam` is running, stay in performance; if only `vim` is running on battery, go ultra-save).
- [ ] **Log Vacuum**: A smart cleanup tool for `journald`, `/var/log`, and cache directories that triggers when disk space hits a threshold.

## 💻 Developer Experience
- [ ] **QuickStack**: Instantly spin up a local development environment (Postgres, Redis, Mongo) using Podman/Docker with a single command, sharing common network and volume defaults.
- [ ] **SSH Config Manager**: A tool to manage complex SSH configurations, including jumping through bastions and managing multiple keys per host.

## 🎨 Aesthetic Polish
- [ ] **XI-Prompt**: A fast, minimal shell prompt (compatible with Bash/Zsh) that shows exactly what you need (git status, exit code, job count) without the bloat.

---

*Contributions are welcome! If you have an idea that belongs in the "Best in the World" category, open an issue or join the Discord.*