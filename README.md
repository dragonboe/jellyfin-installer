# 🎬 Jellyfin & Docker Installer (Multi-Platform)

An automated, cross-platform PowerShell script to install and configure [Jellyfin Media Server](https://jellyfin.org/) using [Docker](https://www.docker.com/) on **Windows 11**, **Linux**, and **macOS**.

![Windows](https://img.shields.io/badge/Windows-11-blue)
![Linux](https://img.shields.io/badge/Linux-Any-orange)
![macOS](https://img.shields.io/badge/macOS-Any-lightgrey)
![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-blueviolet)

---

## 📖 Overview

This universal installer eliminates the complexity of setting up a private media server regardless of your operating system. It automatically handles OS detection, package management (Winget/Brew/Apt), and container orchestration.

### ✨ Key Features
- 🌍 **Universal Support**: Native logic for Windows, Linux, and macOS.
- 🚀 **State-Aware Logic**: Automatically detects existing Docker installations and skips redundant steps.
- 📂 **Flexible Location**: Select custom drives or paths for media and configuration data.
- 🛡️ **Secure Execution**: High-trust implementation using direct CLI commands and robust error handling.
- 📝 **Detailed Logging**: Every action is recorded to your system's temp directory for transparency.

---

## 🚀 Quick Start

### Prerequisites
- **PowerShell 7+** (Required for Linux/macOS. Pre-installed on Windows).
- **Administrator/Root Privileges**.
- **Internet Connection**.

### Installation Steps

1. **Download the Script**
   Save the [jelly.ps1](file:///d:/aro/jelly.ps1) code to your local machine.

2. **Run the Installer**
   Open your terminal as Administrator (or use `sudo` on Linux/Mac) and run:
   ```powershell
   # On Windows:
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\jelly.ps1

   # On Linux/macOS:
   sudo pwsh ./jelly.ps1
   ```

3. **Follow the Menu**
   The script will highlight your detected OS and guide you through the setup.

---

## 📁 Storage Structure

The script organizes your data consistently across platforms:

```text
/Selected/Path/
├── 📁 Media/                  # Your cinema library
│   ├── 📁 Movies/
│   ├── 📁 TV Shows/
│   ├── 📁 Music/
│   └── 📁 Photos/
└── 📁 jellyfin/              # System metadata (SSD highly recommended)
    ├── 📁 config/
    ├── 📁 cache/
    └── 📁 logs/
```

---

## 🌐 Post-Installation

Access your server at [http://localhost:8096](http://localhost:8096).

### Management Commands
```powershell
# Lifecycle
docker restart jellyfin
docker stop jellyfin
docker start jellyfin

# Monitoring
docker logs -f jellyfin
docker ps -a --filter "name=jellyfin"
```

---

## ❓ FAQ & Troubleshooting

**Which OS is supported?**
- **Windows**: Full automation including WSL2 and Virtualization features.
- **macOS**: Uses [Homebrew](https://brew.sh/) to manage Docker Desktop.
- **Linux**: Targets Debian/Ubuntu via the official Docker convenience script.

**Permission Errors?**
- **Windows**: Right-click PowerShell -> Run as Administrator.
- **Unix**: Always prefix the command with `sudo`.

---

## 🤝 Community & Support

Created with ❤️ by **emy**. 
Licensed under [MIT](https://opensource.org/licenses/MIT).
