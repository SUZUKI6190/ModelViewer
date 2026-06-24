# Prepare bindbc-imgui / cimgui for ModelViewer on Windows.
#
# Note: dub stores downloaded packages under the user profile (e.g.
# C:\Users\<you>\.dub\packages), NOT inside the project folder.
# That location is normal; this script resolves it automatically.
$ErrorActionPreference = "Stop"

function Get-DubHome {
    if ($env:DUB_HOME) {
        return $env:DUB_HOME.TrimEnd('\', '/')
    }
    return Join-Path $env:USERPROFILE ".dub"
}

function Find-BindbcImguiPackage {
    $searchRoots = @(
        (Join-Path (Get-DubHome) "packages")
    )
    if ($env:LOCALAPPDATA) {
        $searchRoots += (Join-Path $env:LOCALAPPDATA "dub\packages")
    }

    foreach ($root in ($searchRoots | Select-Object -Unique)) {
        if (-not (Test-Path $root)) { continue }

        $versionRoot = Join-Path $root "bindbc-imgui"
        if (-not (Test-Path $versionRoot)) { continue }

        foreach ($ver in (Get-ChildItem $versionRoot -Directory | Sort-Object Name -Descending)) {
            $candidate = Join-Path $ver.FullName "bindbc-imgui"
            if (Test-Path (Join-Path $candidate "dub.json")) {
                return (Resolve-Path $candidate).Path
            }
        }
    }

    return $null
}

function Ensure-ProjectCimgui {
    param(
        [string]$ProjectDeps,
        [string]$SourceDir
    )

    $header = Join-Path $ProjectDeps "cimgui.h"
    if (Test-Path $header) { return }

    $parent = Split-Path $ProjectDeps -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    if ($SourceDir -and (Test-Path (Join-Path $SourceDir "cimgui.h"))) {
        if (Test-Path $ProjectDeps) {
            Remove-Item -Recurse -Force $ProjectDeps
        }
        Write-Host "Linking deps\cimgui -> $SourceDir"
        cmd /c mklink /J "$ProjectDeps" "$SourceDir" | Out-Null
        return
    }

    if (Test-Path $ProjectDeps) {
        Remove-Item -Recurse -Force $ProjectDeps
    }

    Write-Host "Cloning cimgui (tag 1.79dock) into deps\cimgui ..."
    git clone --depth 1 --branch 1.79dock https://github.com/Inochi2D/cimgui.git $ProjectDeps
    Push-Location $ProjectDeps
    git submodule update --init --recursive
    Pop-Location
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$ProjectDeps = Join-Path $RootDir "deps\cimgui"

Push-Location $RootDir
try {
    Write-Host "Project root: $RootDir"
    Write-Host "DUB home:     $(Get-DubHome)"
    Write-Host "Fetching dependencies (dub fetch)..."
    dub fetch
}
finally {
    Pop-Location
}

$ImguiPkg = Find-BindbcImguiPackage
if (-not $ImguiPkg) {
    Write-Host "bindbc-imgui not in cache yet; running dub build to download it..."
    Push-Location $RootDir
    try {
        dub build --config=parser-test
    }
    finally {
        Pop-Location
    }
    $ImguiPkg = Find-BindbcImguiPackage
}

if ($ImguiPkg) {
    Write-Host "Found bindbc-imgui at: $ImguiPkg"

    $DubJson = Join-Path $ImguiPkg "dub.json"
    $content = Get-Content $DubJson -Raw
    if ($content -notmatch '"bindbc-glfw"') {
        Write-Host "Patching bindbc-imgui to depend on bindbc-glfw..."
        $content = $content.Replace(
            '"bindbc-sdl": "~>0.21.4"',
            '"bindbc-sdl": "~>0.21.4",' + [Environment]::NewLine + "`t`t""bindbc-glfw"": ""~>0.13.0"""
        )
        Set-Content -Path $DubJson -Value $content -NoNewline
    }

    $PackageCimgui = Join-Path $ImguiPkg "deps\cimgui"
    if (-not (Test-Path (Join-Path $PackageCimgui "CMakeLists.txt"))) {
        Write-Host "Cloning cimgui into bindbc-imgui package..."
        git clone --depth 1 --branch 1.79dock https://github.com/Inochi2D/cimgui.git $PackageCimgui
        Push-Location $PackageCimgui
        git submodule update --init --recursive
        Pop-Location
    }

    Ensure-ProjectCimgui -ProjectDeps $ProjectDeps -SourceDir $PackageCimgui

    $LibOut = Join-Path $ImguiPkg "libs\x86_64\win32\Static\DynamicCRT\cimgui.lib"
    if (-not (Test-Path $LibOut)) {
        Write-Host "Building static cimgui (Visual Studio 2022)..."
        $BuildDir = Join-Path $ImguiPkg "deps\build_windows_x64_cimguiStatic_DynamicCRT"
        cmake -G "Visual Studio 17 2022" -Ax64 -DSTATIC_CIMGUI= -DIMGUI_FREETYPE=no `
            -S (Join-Path $ImguiPkg "deps") -B $BuildDir
        cmake --build $BuildDir --config Release
    }
}
else {
    Write-Warning "bindbc-imgui package directory was not found under $(Get-DubHome)\packages."
    Write-Warning "Continuing with project-local deps\cimgui only."
    Ensure-ProjectCimgui -ProjectDeps $ProjectDeps -SourceDir $null
}

if (-not (Test-Path (Join-Path $ProjectDeps "cimgui.h"))) {
    throw "Failed to prepare deps\cimgui. Ensure git and network access are available."
}

Write-Host "Setup complete. deps\cimgui is ready."
Write-Host "Next: dub build --config=application"
