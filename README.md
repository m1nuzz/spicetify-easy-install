# spicetify-easy-install

One-command installer for the latest [Spicetify CLI](https://github.com/spicetify/cli) + [Marketplace](https://github.com/spicetify/marketplace) on Windows.

Unlike the official installer, it does **not** abort when PowerShell runs as administrator (common when everything on the system launches elevated). It continues with `spicetify --bypass-admin` and then fixes folder ACLs so a non-elevated Spotify can still read the patched files (avoids the black/blank window issue).

## Usage

In PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/m1nuzz/spicetify-easy-install/main/install.ps1 | iex
```

That always installs the **latest** Spicetify + Marketplace, then runs `backup apply`.

## Options

Download the script first if you need options:

```powershell
iwr -useb https://raw.githubusercontent.com/m1nuzz/spicetify-easy-install/main/install.ps1 -OutFile install.ps1
.\install.ps1 -NoMarketplace     # CLI only, no Marketplace
.\install.ps1 -v 2.44.0          # pin a specific CLI version
```

## What the script does

1. Detects admin and enables `--bypass-admin` automatically instead of aborting.
2. Resolves the latest CLI version via GitHub Releases API (or uses `-v`).
3. Downloads the matching `windows-x64/arm64/x32` zip and extracts it to `%LOCALAPPDATA%\spicetify`.
4. Adds that folder to the user `PATH` (current session + persistent).
5. Downloads the latest Marketplace release into `%APPDATA%\spicetify\CustomApps\marketplace`.
6. Enables `marketplace` custom app, `inject_css`, `replace_colors` (keeps your existing theme if you already have one).
7. Runs `spicetify backup apply` with the bypass flag when needed.
8. Grants `Builtin\Users` full control on the Spicetify/Spotify data folders to prevent permission-related black screens.

## Requirements

- Windows PowerShell 5.1+
- Spotify (desktop) installed before running `backup apply`
- Internet access to `github.com`, `raw.githubusercontent.com`, `api.github.com`

## Notes

- Running everything as admin is not recommended by Spicetify upstream, but this script makes it work if your system is configured that way.
- If Spotify shows a black window after applying: fully quit Spotify, re-run the one-liner, then start Spotify again.
- To update later, just re-run the same one-liner.
