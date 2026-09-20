# Easy Spicetify + Marketplace installer by m1nuzz
# Admin-tolerant, non-interactive, always installs the latest version.
#
# Run from a NORMAL PowerShell ideally, but works even if everything
# on your system launches as admin (no abort prompt like the official script).
#
# Usage (latest Spicetify + Marketplace):
#   iwr -useb https://raw.githubusercontent.com/m1nuzz/spicetify-easy-install/main/install.ps1 | iex
#
# With options (download file first):
#   .\install.ps1 -v 2.44.0          # pin specific version
#   .\install.ps1 -NoMarketplace     # skip Marketplace

param(
    [string]$v = "",
    [switch]$NoMarketplace
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$spicetifyFolder = "$env:LOCALAPPDATA\spicetify"
$spicetifyExe = Join-Path $spicetifyFolder 'spicetify.exe'

function Write-Ok { Write-Host ' > OK' -ForegroundColor Green }
function Write-Fail { Write-Host ' > ERROR' -ForegroundColor Red }

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Repair-Permissions {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    # Grant Builtin Users (SID S-1-5-32-545, language-independent) full control recursively.
    # This prevents the classic black/blank Spotify window when files were touched as admin
    # but Spotify itself runs as a normal user.
    try { & icacls "$Path" /grant:r "*S-1-5-32-545:(OI)(CI)F" /T /C /Q 2>$null | Out-Null } catch {}
}

function Invoke-Sp {
    param([string[]]$SpArgs)
    $full = @()
    if ($script:UseBypass) { $full += '--bypass-admin' }
    $full += $SpArgs
    # Capture stdout/stderr so it does NOT leak into the function's output stream
    # (otherwise callers get an array instead of the exit code). Echo via Write-Host.
    $output = (& $spicetifyExe @full 2>&1 | Out-String)
    $code = $LASTEXITCODE
    if (-not [string]::IsNullOrWhiteSpace($output)) { Write-Host $output.TrimEnd() }
    return $code
}

function Get-SpOutput {
    param([string[]]$SpArgs)
    $full = @()
    if ($script:UseBypass) { $full += '--bypass-admin' }
    $full += $SpArgs
    $out = (& $spicetifyExe @full 2>&1 | Out-String).Trim()
    return @{ Output = $out; ExitCode = $LASTEXITCODE }
}

# --- Checks (no abort on admin, unlike official installer) ---
Write-Host 'Checking PowerShell version...' -NoNewline
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-Fail
    throw "PowerShell 5.1+ required. You have $($PSVersionTable.PSVersion)."
}
Write-Ok

$script:UseBypass = Test-IsAdmin
if ($script:UseBypass) {
    Write-Host 'WARNING: running as administrator.' -ForegroundColor Yellow
    Write-Host 'Official installer would abort here. Continuing with --bypass-admin + permission fix.' -ForegroundColor Yellow
} else {
    Write-Host 'Admin check...' -NoNewline
    Write-Ok
}

# --- Resolve arch ---
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
elseif ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { $arch = 'x64' }
else { $arch = 'x32' }

# --- Resolve version (latest by default) ---
if ($v -ne '' -and $v -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version '$v'. Expected format: 1.2.3"
}
if ([string]::IsNullOrWhiteSpace($v)) {
    Write-Host 'Fetching latest spicetify version...' -NoNewline
    $latest = Invoke-RestMethod -Uri 'https://api.github.com/repos/spicetify/cli/releases/latest' -UseBasicParsing
    $targetVersion = ($latest.tag_name -replace '^v', '').Trim()
    Write-Host " v$targetVersion" -ForegroundColor Cyan
} else {
    $targetVersion = $v
}

if ([string]::IsNullOrWhiteSpace($targetVersion)) { throw 'Could not resolve Spicetify version.' }

# --- Download + install CLI binary (direct, no interactive prompts) ---
Write-Host "Downloading spicetify v$targetVersion ($arch)..." -NoNewline
$zipUrl = "https://github.com/spicetify/cli/releases/download/v$targetVersion/spicetify-$targetVersion-windows-$arch.zip"
$tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) 'spicetify-easy.zip'
Invoke-WebRequest -Uri $zipUrl -UseBasicParsing -OutFile $tmpZip
Write-Ok

Write-Host 'Installing spicetify...' -NoNewline
if (-not (Test-Path $spicetifyFolder)) { New-Item -ItemType Directory -Path $spicetifyFolder -Force | Out-Null }
Expand-Archive -Path $tmpZip -DestinationPath $spicetifyFolder -Force
Remove-Item -Path $tmpZip -Force -ErrorAction SilentlyContinue
Write-Ok

# --- PATH ---
Write-Host 'Adding spicetify to PATH...' -NoNewline
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -notlike "*$spicetifyFolder*") {
    [Environment]::SetEnvironmentVariable('PATH', "$userPath;$spicetifyFolder", 'User')
}
if (($env:PATH -split ';') -notcontains $spicetifyFolder) { $env:PATH = "$env:PATH;$spicetifyFolder" }
Write-Ok

if (-not (Test-Path -LiteralPath $spicetifyExe -PathType Leaf)) { throw "Install failed: $spicetifyExe not found." }
Repair-Permissions $spicetifyFolder

$verOut = (Get-SpOutput @('-v')).Output
Write-Host "Installed: $verOut" -ForegroundColor Green

# --- Spotify presence check (warn only, stay lightweight) ---
$spotifyExe = "$env:APPDATA\Spotify\Spotify.exe"
if (-not (Test-Path $spotifyExe) -and -not (Get-Command spotify -ErrorAction SilentlyContinue)) {
    Write-Host 'WARNING: Spotify.exe not found at %APPDATA%\Spotify. Install Spotify first, then re-run this script (backup/apply needs it).' -ForegroundColor Yellow
}

# --- Marketplace (latest, non-interactive) ---
if (-not $NoMarketplace) {
    Write-Host 'Installing Marketplace (latest)...' -ForegroundColor Cyan

    $ud = (Get-SpOutput @('path', 'userdata')).Output
    if ([string]::IsNullOrWhiteSpace($ud) -or -not (Test-Path $ud)) { $ud = "$env:APPDATA\spicetify" }
    $marketApp = Join-Path $ud 'CustomApps\marketplace'
    $marketTheme = Join-Path $ud 'Themes\marketplace'

    Remove-Item -Path $marketApp, $marketTheme -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $marketApp, $marketTheme -ItemType Directory -Force | Out-Null

    $mZip = Join-Path $marketApp 'marketplace.zip'
    Invoke-WebRequest -Uri 'https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip' -UseBasicParsing -OutFile $mZip
    Expand-Archive -Path $mZip -DestinationPath $marketApp -Force
    $dist = Join-Path $marketApp 'marketplace-dist'
    if (Test-Path $dist) {
        Move-Item -Path "$dist\*" -Destination $marketApp -Force
        Remove-Item -Path $dist -Recurse -Force
    }
    Remove-Item -Path $mZip -Force -ErrorAction SilentlyContinue

    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini' -UseBasicParsing -OutFile (Join-Path $marketTheme 'color.ini')

    Invoke-Sp @('config', 'custom_apps', 'spicetify-marketplace-', '-q') | Out-Null
    Invoke-Sp @('config', 'custom_apps', 'marketplace') | Out-Null
    Invoke-Sp @('config', 'inject_css', '1', 'replace_colors', '1') | Out-Null

    $curTheme = (Get-SpOutput @('config', 'current_theme')).Output
    if ([string]::IsNullOrWhiteSpace($curTheme) -or $curTheme -eq 'none' -or $curTheme -eq 'marketplace') {
        Invoke-Sp @('config', 'current_theme', 'marketplace') | Out-Null
    } else {
        Write-Host "Keeping your current theme '$curTheme' (placeholder not forced)." -ForegroundColor Yellow
    }

    Write-Host 'Running backup + apply...' -ForegroundColor Cyan
    $code = Invoke-Sp @('backup')
    if ($code -ne 0) { throw "spicetify backup failed with exit code $code." }
    $code = Invoke-Sp @('apply')
    if ($code -ne 0) { throw "spicetify apply failed with exit code $code." }

    # Fix ownership/ACLs so a non-elevated Spotify can read files touched as admin.
    Repair-Permissions $ud
    Repair-Permissions "$env:APPDATA\Spotify"
    Repair-Permissions $spicetifyFolder

    Write-Host 'Marketplace installed!' -ForegroundColor Green
} else {
    Write-Host 'Running backup + apply (no Marketplace)...' -ForegroundColor Cyan
    $code = Invoke-Sp @('backup')
    if ($code -ne 0) { throw "spicetify backup failed with exit code $code." }
    $code = Invoke-Sp @('apply')
    if ($code -ne 0) { throw "spicetify apply failed with exit code $code." }
    Repair-Permissions "$env:APPDATA\Spotify"
}

Write-Host ''
Write-Host 'Done! Restart Spotify. Marketplace should appear in the sidebar.' -ForegroundColor Green
Write-Host 'If Spotify shows a black window: fully close Spotify, re-run this script, restart Spotify.' -ForegroundColor DarkGray
