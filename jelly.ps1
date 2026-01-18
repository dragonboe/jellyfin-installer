# Jellyfin and Docker automated installer for Windows 11 / Linux / macOS
# Script by emy <3

#region OS Detection
$IsWindows = $IsLinux = $IsMacOS = $false
if ($PSVersionTable.Platform -eq "Unix") {
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        $IsMacOS = $true
    } else {
        $IsLinux = $true
    }
} else {
    $IsWindows = $true
}
#endregion

#region helpers
$LogFile = Join-Path ([System.IO.Path]::GetTempPath()) "jellyfin_install.log"

function Write-Log($msg, $level = "INFO") {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$level] $msg"
    $logLine | Out-File $LogFile -Append -Encoding utf8
}

function Write-Info($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
    Write-Log $msg "INFO"
}

function Write-Warn($msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
    Write-Log $msg "WARN"
}

function Write-ErrorMsg($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
    Write-Log $msg "ERROR"
}

function Write-Success($msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
    Write-Log $msg "SUCCESS"
}

function Pause {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Require-Admin {
    if ($IsWindows) {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-ErrorMsg "This script must be run as Administrator."
            Write-Info "Please right-click the script/terminal and select 'Run as administrator'."
            exit 1
        }
    } else {
        $uid = id -u
        if ($uid -ne 0) {
            Write-ErrorMsg "This script must be run as root (sudo)."
            Write-Info "Please run: sudo pwsh $($MyInvocation.MyCommand.Path)"
            exit 1
        }
    }
}
#endregion

#region drive selection
function Get-AvailableDrives($minFreeGB) {
    if ($IsWindows) {
        return Get-PSDrive -PSProvider FileSystem | Where-Object { 
            $_.Free -gt ($minFreeGB * 1GB) -and $_.Root -notmatch '^\\\\' 
        }
    } else {
        # On Unix, we check commonly used mount points or just return the current user's home and /
        $paths = @()
        $paths += [PSCustomObject]@{ Name = "Home"; Root = $HOME; Free = (Get-Item $HOME).AvailableFreeSpace }
        if (Test-Path "/mnt") {
            Get-ChildItem "/mnt" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $paths += [PSCustomObject]@{ Name = $_.Name; Root = $_.FullName; Free = (Get-Item $_.FullName).AvailableFreeSpace }
            }
        }
        return $paths | Where-Object { $_.Free -gt ($minFreeGB * 1GB) }
    }
}

function Display-Drives($drives) {
    $systemDrive = if ($IsWindows) { $env:SystemDrive } else { "/" }
    $i = 1
    foreach ($d in $drives) {
        $freeGB = [math]::Round($d.Free / 1GB, 1)
        $isSystem = if ($IsWindows -and $d.Root.StartsWith($systemDrive)) { " [SYSTEM]" } elseif (-not $IsWindows -and $d.Root -eq "/") { " [SYSTEM]" } else { "" }
        
        Write-Host "$i) $($d.Name) ($($d.Root)): " -NoNewline -ForegroundColor White
        Write-Host "$freeGB GB free$isSystem" -ForegroundColor Green
        $i++
    }
    Write-Host "$i) Enter custom path..." -ForegroundColor Cyan
}

function Select-MediaDrive {
    Write-Host "`n--- Step 1: Media Storage ---" -ForegroundColor Magenta
    Write-Info "Select a location for your movies, TV shows, and music."
    
    $drives = Get-AvailableDrives 5
    Display-Drives $drives
    
    $maxChoice = $drives.Count + 1
    $choice = ""
    while ($choice -notmatch '^\d+$' -or $choice -lt 1 -or $choice -gt $maxChoice) {
        $choice = Read-Host "`nSelect option (1-$maxChoice)"
    }

    if ($choice -eq $maxChoice) {
        $selectedPath = Read-Host "Enter absolute path"
    } else {
        $selectedPath = $drives[$choice - 1].Root
    }

    $selectedPath = $selectedPath.TrimEnd([IO.Path]::DirectorySeparatorChar)
    Write-Success "Selected path: $selectedPath"
    
    $folderName = Read-Host "Enter media folder name [Default: Media]"
    if ([string]::IsNullOrWhiteSpace($folderName)) { $folderName = "Media" }
    
    $mediaPath = Join-Path $selectedPath $folderName
    
    try {
        if (-not (Test-Path $mediaPath)) {
            New-Item -ItemType Directory -Path $mediaPath -Force -ErrorAction Stop | Out-Null
            Write-Success "Created: $mediaPath"
        }
        
        $subdirs = @("Movies", "TV Shows", "Music", "Photos", "Home Videos")
        foreach ($dir in $subdirs) {
            $path = Join-Path $mediaPath $dir
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
        Write-Info "Organized subfolders ready."
    } catch {
        Write-ErrorMsg "Path Error: $_"
        exit 1
    }
    
    return $mediaPath
}

function Select-JellyfinDataDrive {
    Write-Host "`n--- Step 2: Jellyfin Data & Config ---" -ForegroundColor Magenta
    Write-Info "Select a location for Jellyfin's database and cache (SSD recommended)."
    
    $drives = Get-AvailableDrives 10
    Display-Drives $drives
    
    $maxChoice = $drives.Count + 1
    $choice = ""
    while ($choice -notmatch '^\d+$' -or $choice -lt 1 -or $choice -gt $maxChoice) {
        $choice = Read-Host "`nSelect option (1-$maxChoice)"
    }

    if ($choice -eq $maxChoice) {
        $selectedPath = Read-Host "Enter absolute path"
    } else {
        $selectedPath = $drives[$choice - 1].Root
    }

    $selectedPath = $selectedPath.TrimEnd([IO.Path]::DirectorySeparatorChar)
    Write-Success "Jellyfin data path: $selectedPath"
    
    return $selectedPath
}
#endregion

#region virtualization
$rebootRequired = $false

#region virtualization
$script:rebootRequired = $false

function Enable-Virtualization {
    if (-not $IsWindows) { return }
    Write-Host "`n--- Virtualization Features ---" -ForegroundColor Magenta
    
    $features = @("Microsoft-Hyper-V", "VirtualMachinePlatform", "HypervisorPlatform")
    $missingFeatures = @()

    foreach ($f in $features) {
        $check = dism /online /get-featureinfo /featurename:$f
        if ($check -match "Disabled") { $missingFeatures += $f }
    }

    if ($missingFeatures.Count -eq 0) {
        Write-Success "All virtualization features are already enabled."
        return
    }

    Write-Info "Enabling missing features: $($missingFeatures -join ', ')"
    foreach ($f in $missingFeatures) {
        dism /online /enable-feature /featurename:$f /all /norestart | Out-Null
    }
    
    bcdedit /set hypervisorlaunchtype auto | Out-Null
    $script:rebootRequired = $true
    Write-Warn "REBOOT REQUIRED: Virtualization features enabled."
}
#endregion

#region installs
function Install-WSL {
    if (-not $IsWindows) { return }
    Write-Host "`n--- WSL2 Installation ---" -ForegroundColor Magenta
    
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        Write-Success "WSL is already installed."
        wsl --set-default-version 2 | Out-Null
        return
    }

    Write-Info "WSL is missing. Installing now..."
    try {
        wsl --install -d Ubuntu --no-launch | Out-Null
        Write-Success "WSL2 installed."
        wsl --set-default-version 2 | Out-Null
    } catch {
        Write-ErrorMsg "WSL Installation failed: $_"
        Write-Info "Try running 'wsl --install' manually in a new terminal."
    }
}

function Install-Docker {
    Write-Host "`n--- Docker Installation ---" -ForegroundColor Magenta
    
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        Write-Success "Docker is already installed."
        return
    }

    if ($IsWindows) {
        Write-Info "Installing Docker Desktop via winget..."
        winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker Desktop installed."
            Write-Warn "Launch Docker Desktop manually and wait for it to start."
        }
    } elseif ($IsMacOS) {
        if (Get-Command brew -ErrorAction SilentlyContinue) {
            Write-Info "Installing Docker via Homebrew..."
            brew install --cask docker
        } else {
            Write-ErrorMsg "Homebrew not found. Install from https://brew.sh or download Docker Desktop from https://docker.com"
        }
    } elseif ($IsLinux) {
        Write-Info "Installing Docker via official script..."
        try {
            Invoke-RestMethod -Uri https://get.docker.com | Out-File get-docker.sh
            sh get-docker.sh
            Remove-Item get-docker.sh
            Write-Success "Docker Engine installed. Ensure your user is in the 'docker' group."
        } catch {
            Write-ErrorMsg "Docker installation failed. Please follow: https://docs.docker.com/engine/install/"
        }
    }
}

function Configure-DockerDataRoot($basePath) {
    if (-not $IsWindows) {
        Write-Info "Docker data-root configuration is currently automated for Windows only."
        Write-Info "On Linux/macOS, modify /etc/docker/daemon.json if you need a custom data-root."
        return
    }
    Write-Host "`n--- Docker Storage Configuration ---" -ForegroundColor Magenta
    
    $dockerRoot = Join-Path $basePath "Docker\data"
    $configDir = "$env:ProgramData\Docker\config"
    $configFile = Join-Path $configDir "daemon.json"

    # Check if already configured
    if (Test-Path $configFile) {
        $currentConfig = Get-Content $configFile | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($currentConfig -and $currentConfig."data-root" -eq $dockerRoot) {
            Write-Success "Docker data-root is already configured to $dockerRoot"
            return
        }
    }

    try {
        if (-not (Test-Path $dockerRoot)) { New-Item -ItemType Directory -Path $dockerRoot -Force | Out-Null }
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

        $config = @{ "data-root" = ($dockerRoot -replace '\\', '\\') }
        $config | ConvertTo-Json | Out-File $configFile -Encoding utf8 -Force
        
        Write-Success "Docker data-root set to: $dockerRoot"
        Write-Warn "This change requires a Docker Desktop restart to take effect."
    } catch {
        Write-ErrorMsg "Failed to configure Docker storage: $_"
    }
}
#endregion

#region jellyfin
function Install-Jellyfin($jellyfinDataDrive, $mediaPath) {
    Write-Host "`n--- Jellyfin Container Setup ---" -ForegroundColor Magenta
    
    $jfBase   = Join-Path $jellyfinDataDrive "jellyfin"
    $jfConfig = Join-Path $jfBase "config"
    $jfCache  = Join-Path $jfBase "cache"
    $jfLogs   = Join-Path $jfBase "logs"

    Write-Info "Configuring paths:"
    Write-Info "  Data: $jfBase"
    Write-Info "  Media: $mediaPath"

    # Create directories
    try {
        $paths = @($jfConfig, $jfCache, $jfLogs)
        foreach ($p in $paths) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
        Write-Success "Jellyfin directories ready."
    } catch {
        Write-ErrorMsg "Failed to create directories: $_"
        return
    }

    # Docker Check
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg "Docker not found in PATH. Please install Docker Desktop."
        return
    }

    $dockerCheck = docker info 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Docker is not running. Please start Docker Desktop."
        return
    }

    # Container Check
    $existing = docker ps -a --filter "name=jellyfin" --format "{{.Names}}"
    if ($existing -eq "jellyfin") {
        Write-Warn "A container named 'jellyfin' already exists."
        $action = Read-Host "Keep existing container or Recreacte? (K/R) [Default: K]"
        if ($action -eq 'R' -or $action -eq 'r') {
            Write-Info "Removing existing container..."
            docker rm -f jellyfin | Out-Null
        } else {
            Write-Success "Keeping existing container. Starting it if stopped..."
            docker start jellyfin | Out-Null
            return
        }
    }

    Write-Info "Pulling latest Jellyfin image..."
    docker pull jellyfin/jellyfin

    Write-Info "Launching Jellyfin container..."
    docker run -d `
        --name jellyfin `
        --restart unless-stopped `
        -p 8096:8096 `
        -v "${jfConfig}:/config" `
        -v "${jfCache}:/cache" `
        -v "${jfLogs}:/logs" `
        -v "${mediaPath}:/media" `
        jellyfin/jellyfin

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Jellyfin is now running at http://localhost:8096"
    } else {
        Write-ErrorMsg "Failed to start Jellyfin container. Check Docker logs."
    }
}
#endregion

#region main
Clear-Host
Require-Admin

Write-Host "=============================================" -ForegroundColor Magenta
Write-Host "    Jellyfin + Docker Automated Installer" -ForegroundColor Magenta
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host "    Created by emy <3 | Enhanced Version" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host ""

# System state detection
Write-Info "Scanning system state..."

Write-Host "Detected OS:" -ForegroundColor White
Write-Host "  Windows  " -NoNewline -ForegroundColor (if ($IsWindows) { "Green" } else { "Gray" })
if ($IsWindows) { Write-Host "(Active)" -ForegroundColor Green } else { Write-Host "" }

Write-Host "  Linux    " -NoNewline -ForegroundColor (if ($IsLinux) { "Green" } else { "Gray" })
if ($IsLinux)   { Write-Host "(Active)" -ForegroundColor Green } else { Write-Host "" }

Write-Host "  MacOS    " -NoNewline -ForegroundColor (if ($IsMacOS) { "Green" } else { "Gray" })
if ($IsMacOS)   { Write-Host "(Active)" -ForegroundColor Green } else { Write-Host "" }
Write-Host ""

# Check components based on OS
$hasDocker = if (Get-Command docker -ErrorAction SilentlyContinue) { "Installed" } else { "MISSING" }
$dockerRunning = if ($hasDocker -eq "Installed" -and (docker info 2>$null)) { "Running" } else { "Stopped" }

if ($IsWindows) {
    $hasWSL = if (Get-Command wsl -ErrorAction SilentlyContinue) { "Installed" } else { "MISSING" }
}

Write-Host "System Summary:" -ForegroundColor White
if ($IsWindows) {
    Write-Host "  WSL2:    " -NoNewline; Write-Host $hasWSL -ForegroundColor (if ($hasWSL -eq "Installed") { "Green" } else { "Red" })
}
Write-Host "  Docker:  " -NoNewline; Write-Host $hasDocker -ForegroundColor (if ($hasDocker -eq "Installed") { "Green" } else { "Red" })
Write-Host "  Service: " -NoNewline; Write-Host $dockerRunning -ForegroundColor (if ($dockerRunning -eq "Running") { "Green" } else { "Red" })
Write-Host ""

# Drive Selection
$mediaPath = Select-MediaDrive
$jellyfinDataDrive = Select-JellyfinDataDrive

Write-Host "`n--- Installation Menu ---" -ForegroundColor Magenta
Write-Host "1  Full Automatic Setup (Recommended)" -ForegroundColor Green
if ($IsWindows) {
    Write-Host "2  Enable Virtualization & WSL2 Only" -ForegroundColor Cyan
}
Write-Host "3  Install/Configure Docker Desktop/Engine Only" -ForegroundColor Cyan
Write-Host "4  Install/Reinstall Jellyfin Container Only" -ForegroundColor Cyan
Write-Host "0  Exit" -ForegroundColor Gray
Write-Host ""

# forgot to add this but here it is.
$choice = Read-Host "Select an option"

switch ($choice) {
    "1" {
        Enable-Virtualization
        if ($rebootRequired) { break }
        Install-WSL
        Install-Docker
        Configure-DockerDataRoot $jellyfinDataDrive
        Install-Jellyfin $jellyfinDataDrive $mediaPath
    }
    "2" {
        Enable-Virtualization
        if ($rebootRequired) { break }
        Install-WSL
    }
    "3" {
        Install-Docker
        Configure-DockerDataRoot $jellyfinDataDrive
    }
    "4" {
        Install-Jellyfin $jellyfinDataDrive $mediaPath
    }
    "0" { exit }
    default { Write-ErrorMsg "Invalid selection." }
}

if ($rebootRequired) {
    Write-Host "`n=============================================" -ForegroundColor Red
    Write-Host "           REBOOT REQUIRED" -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Red
    Write-Warn "System features were enabled that require a restart."
    Write-Info "1. Restart your computer."
    Write-Info "2. Run this script again to complete the setup."
    Write-Host ""
    Pause
} elseif ($choice -in "1","4") {
    Write-Host "`n=============================================" -ForegroundColor Green
    Write-Host "           SETUP SUCCESSFUL" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Success "Jellyfin is ready!"
    Write-Host "Access URL: http://localhost:8096" -ForegroundColor Cyan
    Write-Host "Media Path: $mediaPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Container Management Commands:" -ForegroundColor Yellow
    Write-Host "  Start:   docker start jellyfin"
    Write-Host "  Stop:    docker stop jellyfin"
    Write-Host "  Logs:    docker logs -f jellyfin"
    Write-Host ""
    Pause
}
#endregion
