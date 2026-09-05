#Requires -Version 5.1
<#
.SYNOPSIS
  Activates BetterDesk desktop build environment for the current PowerShell session (Windows x64).

.DESCRIPTION
  Sets PATH / VCPKG_ROOT / LIBCLANG_PATH for tools installed under C:\tools (and optional
  "C:\Program Files\LLVM"). Optionally persists the same values to the User environment
  with -Persist.

.EXAMPLE
  . .\scripts\activate_desktop_env_windows.ps1
  . .\scripts\activate_desktop_env_windows.ps1 -Persist
#>
param(
    [switch]$Persist
)

$FlutterBin = 'C:\tools\flutter-3.24.5\bin'
$VcpkgRoot = 'C:\tools\vcpkg'
$LlvmCandidates = @(
    'C:\tools\LLVM-15.0.6\bin',
    'C:\Program Files\LLVM\bin'
)

function Test-LibClang([string]$binDir) {
    return (Test-Path (Join-Path $binDir 'libclang.dll'))
}

$llvmBin = $LlvmCandidates | Where-Object { Test-LibClang $_ } | Select-Object -First 1

$env:VCPKG_ROOT = $VcpkgRoot
$env:VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
# Keep cargo artifacts in the repo so Flutter CMake / build.py pick up a fresh librustdesk.dll
# (Cursor sandbox may otherwise redirect CARGO_TARGET_DIR to a temp cache).
$RepoRoot = Split-Path -Parent $PSScriptRoot
$env:CARGO_TARGET_DIR = Join-Path $RepoRoot 'target'
if ($llvmBin) {
    $env:LIBCLANG_PATH = $llvmBin
} else {
    Write-Warning "libclang.dll not found under C:\tools\LLVM-15.0.6 or C:\Program Files\LLVM. Install LLVM 15+ and re-run."
}

$prefix = @($FlutterBin, $VcpkgRoot)
if ($llvmBin) { $prefix += $llvmBin }
$env:Path = (($prefix + ($env:Path -split ';' | Where-Object { $_ -and ($prefix -notcontains $_) })) -join ';')

Write-Host "VCPKG_ROOT=$env:VCPKG_ROOT"
if ($env:LIBCLANG_PATH) { Write-Host "LIBCLANG_PATH=$env:LIBCLANG_PATH" }
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    Write-Host "flutter: $((flutter --version 2>&1 | Select-Object -First 1))"
} else {
    Write-Warning "flutter not on PATH (expected at $FlutterBin)"
}
if (Get-Command rustc -ErrorAction SilentlyContinue) {
    Write-Host "rustc: $(rustc --version)"
}

if ($Persist) {
    [Environment]::SetEnvironmentVariable('VCPKG_ROOT', $VcpkgRoot, 'User')
    if ($llvmBin) {
        [Environment]::SetEnvironmentVariable('LIBCLANG_PATH', $llvmBin, 'User')
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    foreach ($p in $prefix) {
        $parts = $userPath -split ';' | Where-Object { $_ -ne '' }
        if ($parts -notcontains $p) {
            $userPath = if ($userPath) { "$p;$userPath" } else { $p }
        }
    }
    [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
    Write-Host 'Persisted VCPKG_ROOT, LIBCLANG_PATH (if found), and PATH to User environment. Open a new terminal for other apps.'
}

Write-Host 'Next: powershell -ExecutionPolicy Bypass -File .\scripts\check_desktop_env_windows.ps1'
Write-Host 'Build: python build.py --flutter --hwcodec --vram --skip-portable-pack'
