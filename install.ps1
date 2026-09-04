<#
.SYNOPSIS
  Copies the Oxygen Pro 61 Rich REAPER Integration into a REAPER resource folder.

.DESCRIPTION
  Run from the repo folder in PowerShell 7 (pwsh) or Windows PowerShell 5:

      .\install.ps1 -ReaperResourcePath "D:\REAPER"            # portable install (folder that holds reaper.ini)
      .\install.ps1                                             # defaults to %APPDATA%\REAPER (non-portable install)

  It copies the ReaLearn presets, the ReaScripts and appends the watcher start-up block to Scripts\__startup.lua
  (creating the file if needed). It never overwrites an existing controllers.json: the first-time setup script
  inside REAPER writes that one with the right device numbers for the machine.

  REAPER may be running while you copy files, but restart it afterwards.
#>
param(
    [string]$ReaperResourcePath = (Join-Path $env:APPDATA "REAPER")
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path (Join-Path $ReaperResourcePath "reaper.ini"))) {
    Write-Host "No reaper.ini in '$ReaperResourcePath'. Pass -ReaperResourcePath <folder that contains reaper.ini>." -ForegroundColor Yellow
    exit 1
}

$presetDst  = Join-Path $ReaperResourcePath "Data\helgoboss\realearn\presets\main\oxygen-pro-61"
$scriptDst  = Join-Path $ReaperResourcePath "Scripts\Oxygen Pro"
$startup    = Join-Path $ReaperResourcePath "Scripts\__startup.lua"
$ctlDst     = Join-Path $ReaperResourcePath "Helgoboss\ReaLearn\controllers.json"

New-Item -ItemType Directory -Force $presetDst | Out-Null
New-Item -ItemType Directory -Force $scriptDst | Out-Null
Copy-Item (Join-Path $repo "realearn\presets\main\oxygen-pro-61\*.luau") $presetDst -Force
foreach ($sub in @("fcb1010", "exquis")) {
    $d = Join-Path $ReaperResourcePath "Data\helgoboss\realearn\presets\main\$sub"
    New-Item -ItemType Directory -Force $d | Out-Null
    Copy-Item (Join-Path $repo "realearn\presets\main\$sub\*.luau") $d -Force
}
Copy-Item (Join-Path $repo "reaper\Scripts\Oxygen Pro\*.lua") $scriptDst -Force
New-Item -ItemType Directory -Force (Join-Path $scriptDst "oxygen_editor") | Out-Null
Copy-Item (Join-Path $repo "reaper\Scripts\Oxygen Pro\oxygen_editor\*") (Join-Path $scriptDst "oxygen_editor") -Force
Write-Host "Copied ReaLearn presets -> $presetDst"
Write-Host "Copied ReaScripts       -> $scriptDst"

$snippet = Get-Content (Join-Path $repo "reaper\Scripts\__startup.oxygen-snippet.lua") -Raw
$marker  = ">>> Oxygen Pro 61 LED unlock"
if (Test-Path $startup) {
    if ((Get-Content $startup -Raw) -match [regex]::Escape($marker)) {
        Write-Host "Scripts\__startup.lua already starts the watcher; left unchanged."
    } else {
        Add-Content -Path $startup -Value ("`r`n" + $snippet)
        Write-Host "Appended the watcher start-up block to Scripts\__startup.lua"
    }
} else {
    Set-Content -Path $startup -Value $snippet
    Write-Host "Created Scripts\__startup.lua with the watcher start-up block"
}

if (-not (Test-Path $ctlDst)) {
    New-Item -ItemType Directory -Force (Split-Path $ctlDst) | Out-Null
    Copy-Item (Join-Path $repo "realearn\controllers.template.json") $ctlDst
    Write-Host "Wrote a template controllers.json (device numbers are placeholders until the setup script runs)"
} else {
    Write-Host "controllers.json exists; left unchanged (the setup script rewrites it)."
}

Write-Host ""
Write-Host "Next, inside REAPER:" -ForegroundColor Cyan
Write-Host "  1. Actions > Show action list > New action > Load ReaScript > Scripts\Oxygen Pro\Oxygen Pro - First time setup.lua, run it (it also registers the Editor as an action)."
Write-Host "  2. Tick the MIDI device boxes it lists (MIDIIN3 control-only, Oxygen Pro 61 input+control, MIDIOUT3 output)."
Write-Host "  3. In the Helgobox window: Menu > Instance > Enable global control."
Write-Host "  4. Restart REAPER. The pads sweep green when the keyboard is armed."
