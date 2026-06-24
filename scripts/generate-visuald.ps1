# Generate Visual Studio / VisualD solution from dub.json (Windows).
param(
    [ValidateSet("application", "parser-test")]
    [string]$Config = "application"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path

Push-Location $RootDir
try {
    Write-Host "Project root: $RootDir"
    Write-Host "Configuration: $Config"

    if (-not (Test-Path "deps\cimgui\cimgui.h")) {
        Write-Host "deps\cimgui not found. Running setup..."
        & (Join-Path $ScriptDir "setup-bindbc-imgui.ps1")
    }

    if ($Config -eq "application") {
        Write-Host "Compiling imgui_helper.cpp (required for VisualD builds)..."
        & (Join-Path $ScriptDir "compile-imgui-helper.bat")
        if ($LASTEXITCODE -ne 0) { throw "imgui_helper compile failed" }
    }

    Write-Host "Fetching dub dependencies..."
    dub fetch

    if ($Config -eq "application") {
        Write-Host "Pre-building bindbc-imgui via dub (first time may take several minutes)..."
        dub build --config=application
    }

    Write-Host "Generating VisualD project files..."
    dub generate visuald --config=$Config

    Write-Host ""
    Write-Host "Generated:"
    Write-Host "  modelviewer.sln"
    Write-Host "  .dub\*.visualdproj"
    Write-Host ""
    Write-Host "Open modelviewer.sln in Visual Studio with VisualD installed."
    Write-Host ""
    Write-Host "Notes:"
    Write-Host "  - Prefer 'dub build --config=$Config' for reliable builds."
    Write-Host "  - Re-run this script after dub.json changes."
    Write-Host "  - Working directory for debugging: project root (data\cube.geo.xml relative path)."
}
finally {
    Pop-Location
}
