# 🛠️ Utils

A curated collection of "quality of life" Linux utilities designed to automate the annoyances away. Whether it's managing secrets, optimizing configurations, or bridging the gap between desktop environments, these scripts are built to be drops-in-and-forget-it.

---

## 🚀 Featured Utility: `ke.sh` (KeePassXC Automator)

The flagship utility of this repo. `ke.sh` bridges the gap between your Linux login (GDM/TTY) and your password manager.

### What it does:
- **Zero-Effort Unlock**: Hooks into the PAM stack to capture your login password and immediately unlock your KeePassXC database.
- **Secret Service Takeover**: Automatically kills `gnome-keyring-daemon` so KeePassXC can act as the primary FDO Secrets (libsecret) provider.
- **SSH Agent Integration**: Enables the KeePassXC SSH agent and injects optimized configurations into your environment.
- **Auto-Provisioning**: If you don't have a database, it creates one for you. If you don't have the dependencies, it installs them.

### Quick Start:

**The One-Liner (Fastest):**
```bash
curl -sS https://raw.githubusercontent.com/xipid/utils/main/ke.sh | sudo bash -s -- -i
```

**Local Manual Install:**
```bash
sudo bash ke.sh -i
```
*After installation, just log out and back in. Your database will be waiting for you, unlocked and ready.*

---

## 🗺️ Roadmap (The "Best in the World" Quest)

We aren't just building scripts; we are building a seamless Linux experience. See [TODO.md](TODO.md) for the full engineering roadmap.

**Current Focus:**
- [ ] Automated migration from GNOME Keyring to KeePassXC.
- [ ] Universal dotfile engine with environment-aware symlinking.
- [ ] Advanced power management wrappers for mobile workstations.

---

## 🤝 Community & Support

Got questions? Want to suggest a new utility? Join the discussion on Discord:

**Join us here:** [https://discord.gg/724sq7wxkf](https://discord.gg/724sq7wxkf)

---

## 📜 License

Distributed under the Apache License 2.0. See [LICENSE](LICENSE) for more details.

---

*Stay efficient.*
