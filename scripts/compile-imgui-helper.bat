@echo off
setlocal enabledelayedexpansion

if not exist "deps\cimgui\cimgui.h" (
  echo ERROR: deps\cimgui not found. Run scripts\setup-bindbc-imgui.ps1 first.
  exit /b 1
)

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo ERROR: vswhere not found. Install Visual Studio 2022 with the C++ workload.
  exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%i"

if not defined VSINSTALL (
  echo ERROR: Visual Studio 2022 with C++ build tools was not found.
  exit /b 1
)

call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Failed to initialize the MSVC build environment.
  exit /b 1
)

cl /nologo /EHsc /c /I"deps\cimgui" /Fo"source\c\imgui_helper.obj" "source\c\imgui_helper.cpp"
exit /b %ERRORLEVEL%
