# Prepare bindbc-imgui / cimgui for ModelViewer on Windows.
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$ImguiPkg = Join-Path $env:USERPROFILE ".dub\packages\bindbc-imgui\0.7.0\bindbc-imgui"
$DubJson = Join-Path $ImguiPkg "dub.json"

if (-not (Test-Path $ImguiPkg)) {
    Write-Host "Fetching bindbc-imgui..."
    dub fetch bindbc-imgui@0.7.0
}

if (-not (Test-Path $DubJson)) {
    throw "bindbc-imgui package not found at $ImguiPkg"
}

$content = Get-Content $DubJson -Raw
if ($content -notmatch '"bindbc-glfw"') {
    Write-Host "Patching bindbc-imgui to depend on bindbc-glfw..."
    $content = $content.Replace(
        '"bindbc-sdl": "~>0.21.4"',
        '"bindbc-sdl": "~>0.21.4",' + [Environment]::NewLine + "`t`t""bindbc-glfw"": ""~>0.13.0"""
    )
    Set-Content -Path $DubJson -Value $content -NoNewline
}

$CimguiDir = Join-Path $ImguiPkg "deps\cimgui"
if (-not (Test-Path (Join-Path $CimguiDir "CMakeLists.txt"))) {
    Write-Host "Cloning cimgui (tag 1.79dock)..."
    git clone --depth 1 --branch 1.79dock https://github.com/Inochi2D/cimgui.git $CimguiDir
    Push-Location $CimguiDir
    git submodule update --init --recursive
    Pop-Location
}

$ProjectDeps = Join-Path $RootDir "deps\cimgui"
$ProjectDepsParent = Join-Path $RootDir "deps"
if (-not (Test-Path (Join-Path $ProjectDeps "cimgui.h"))) {
    if (-not (Test-Path $ProjectDepsParent)) {
        New-Item -ItemType Directory -Path $ProjectDepsParent | Out-Null
    }
    if (Test-Path $ProjectDeps) {
        Remove-Item -Recurse -Force $ProjectDeps
    }
    Write-Host "Linking deps\cimgui -> package cimgui headers..."
    cmd /c mklink /J "$ProjectDeps" "$CimguiDir" | Out-Null
}

$LibOut = Join-Path $ImguiPkg "libs\x86_64\win32\Static\DynamicCRT\cimgui.lib"
if (-not (Test-Path $LibOut)) {
    Write-Host "Building static cimgui (Visual Studio 2022)..."
    $BuildDir = Join-Path $ImguiPkg "deps\build_windows_x64_cimguiStatic_DynamicCRT"
    cmake -G "Visual Studio 17 2022" -Ax64 -DSTATIC_CIMGUI= -DIMGUI_FREETYPE=no `
        -S (Join-Path $ImguiPkg "deps") -B $BuildDir
    cmake --build $BuildDir --config Release
}

Write-Host "bindbc-imgui dependencies are ready."
