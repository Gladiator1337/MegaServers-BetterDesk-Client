#Requires -Version 5.1
<#
.SYNOPSIS
  Checks local prerequisites for building the BetterDesk / RustDesk Flutter desktop client on Windows x64.

.DESCRIPTION
  Read-only verification against CI versions (Flutter 3.24.5, Rust 1.75, vcpkg commit, LLVM).
  Does not install anything. Run from anywhere; resolves repo root from this script's location.
#>

$ErrorActionPreference = 'Continue'

$ExpectedFlutter = '3.24.5'
$ExpectedRustMajorMinor = '1.75'
$ExpectedVcpkgCommit = '9e593bb18ea69cc5095e012465dcd675a822ed0d'
$ExpectedTripletHint = 'x64-windows-static'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $RepoRoot

$failures = 0
$warnings = 0

function Write-Ok([string]$msg) { Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow; $script:warnings++ }
function Write-Fail([string]$msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:failures++ }
function Write-Info([string]$msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }

Write-Info "Repo root: $RepoRoot"
Write-Info "Expected: Flutter $ExpectedFlutter, Rust $ExpectedRustMajorMinor, vcpkg $ExpectedVcpkgCommit"
Write-Host ""

# --- Git / submodule ---
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ok "git: $(git --version)"
} else {
    Write-Fail "git not found on PATH"
}

$hbbCargo = Join-Path $RepoRoot 'libs\hbb_common\Cargo.toml'
$configRs = Join-Path $RepoRoot 'libs\hbb_common\src\config.rs'
if ((Test-Path $hbbCargo) -and (Test-Path $configRs)) {
    Write-Ok "submodule libs/hbb_common present (Cargo.toml + config.rs)"
} else {
    Write-Fail "libs/hbb_common incomplete - run: git submodule update --init --recursive"
}

# --- Python ---
$python = $null
foreach ($name in @('python', 'python3', 'py')) {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
        $python = $name
        break
    }
}
if ($python) {
    $pyVer = & $python --version 2>&1
    Write-Ok "Python: $pyVer ($python)"
} else {
    Write-Fail "Python 3 not found (needed for build.py)"
}

# --- Rust ---
if (Get-Command rustc -ErrorAction SilentlyContinue) {
    $rustcVer = (rustc --version 2>&1).ToString()
    if ($rustcVer -match $ExpectedRustMajorMinor) {
        Write-Ok "rustc: $rustcVer"
    } else {
        Write-Warn "rustc: $rustcVer (CI uses $ExpectedRustMajorMinor - install: rustup toolchain install $ExpectedRustMajorMinor)"
    }
} else {
    Write-Fail "rustc not found - install rustup and toolchain $ExpectedRustMajorMinor"
}

if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Write-Ok "cargo: $(cargo --version 2>&1)"
} else {
    Write-Fail "cargo not found"
}

if (Get-Command rustup -ErrorAction SilentlyContinue) {
    $targets = rustup target list --installed 2>&1 | Out-String
    if ($targets -match 'x86_64-pc-windows-msvc') {
        Write-Ok "rustup target x86_64-pc-windows-msvc installed"
    } else {
        Write-Warn "target x86_64-pc-windows-msvc not listed - run: rustup target add x86_64-pc-windows-msvc"
    }
    $has175 = (rustup toolchain list 2>&1 | Out-String) -match '1\.75'
    if (-not $has175) {
        Write-Warn "toolchain 1.75 not installed - run: rustup toolchain install 1.75"
    }
} else {
    Write-Warn "rustup not found (harder to pin Rust $ExpectedRustMajorMinor)"
}

# --- Flutter ---
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    $flutterOut = (flutter --version 2>&1 | Out-String)
    $flutterLine = ($flutterOut -split "`n" | Select-Object -First 1).Trim()
    if ($flutterOut -match [regex]::Escape($ExpectedFlutter)) {
        Write-Ok "Flutter: $flutterLine"
    } else {
        Write-Warn "Flutter: $flutterLine (CI uses $ExpectedFlutter)"
    }
} else {
    Write-Fail "flutter not found on PATH"
}

# --- VCPKG_ROOT ---
$vcpkgRoot = $env:VCPKG_ROOT
if ([string]::IsNullOrWhiteSpace($vcpkgRoot)) {
    Write-Fail "VCPKG_ROOT is not set"
} elseif (-not (Test-Path $vcpkgRoot)) {
    Write-Fail "VCPKG_ROOT points to missing path: $vcpkgRoot"
} else {
    Write-Ok "VCPKG_ROOT=$vcpkgRoot"
    $vcpkgExe = Join-Path $vcpkgRoot 'vcpkg.exe'
    if (-not (Test-Path $vcpkgExe)) {
        $vcpkgExe = Join-Path $vcpkgRoot 'vcpkg'
    }
    if (Test-Path $vcpkgExe) {
        Write-Ok "vcpkg binary found"
    } else {
        Write-Fail "vcpkg executable not found under VCPKG_ROOT (run bootstrap-vcpkg.bat)"
    }
    Push-Location $vcpkgRoot
    try {
        $head = (git rev-parse HEAD 2>&1).ToString().Trim()
        if ($head -eq $ExpectedVcpkgCommit) {
            Write-Ok "vcpkg commit matches CI ($ExpectedVcpkgCommit)"
        } elseif ($head -match '^[0-9a-f]{7,40}$') {
            Write-Warn "vcpkg commit is $head (CI expects $ExpectedVcpkgCommit)"
        } else {
            Write-Warn "could not read vcpkg git HEAD (not a git checkout?)"
        }
    } finally {
        Pop-Location
    }
    $installedTriplet = Join-Path $vcpkgRoot "installed\$ExpectedTripletHint"
    if (Test-Path $installedTriplet) {
        Write-Ok "vcpkg installed triplet present: $ExpectedTripletHint"
    } else {
        Write-Warn "installed\$ExpectedTripletHint not found - from repo root run: vcpkg install --triplet $ExpectedTripletHint --x-install-root=%VCPKG_ROOT%\installed"
    }
}

# --- LLVM / LIBCLANG_PATH ---
$libclang = $env:LIBCLANG_PATH
if ([string]::IsNullOrWhiteSpace($libclang)) {
    Write-Warn "LIBCLANG_PATH is not set (bindgen may fail). Point it at LLVM 15 bin, e.g. C:\Program Files\LLVM\bin"
} elseif (Test-Path $libclang) {
    $clangDll = Join-Path $libclang 'libclang.dll'
    if (Test-Path $clangDll) {
        Write-Ok "LIBCLANG_PATH=$libclang (libclang.dll found)"
    } else {
        Write-Warn "LIBCLANG_PATH=$libclang but libclang.dll not found there"
    }
} else {
    Write-Fail "LIBCLANG_PATH points to missing path: $libclang"
}

if (Get-Command clang -ErrorAction SilentlyContinue) {
    Write-Ok "clang: $(clang --version 2>&1 | Select-Object -First 1)"
} else {
    Write-Warn "clang not on PATH (CI uses LLVM 15.0.6)"
}

# --- Visual Studio / MSVC hint ---
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) {
        Write-Ok "Visual Studio C++ tools: $vsPath"
    } else {
        Write-Warn "vswhere found no VC Tools x64 - install VS 2022 workload 'Desktop development with C++'"
    }
} else {
    Write-Warn "vswhere.exe not found - cannot verify Visual Studio C++ workload"
}

Write-Host ""
if ($failures -gt 0) {
    Write-Host "Result: $failures failure(s), $warnings warning(s). Fix FAIL items before building." -ForegroundColor Red
    Write-Host "See docs/BUILD_DESKTOP.md" -ForegroundColor Cyan
    exit 1
}
Write-Host "Result: all required checks passed ($warnings warning(s))." -ForegroundColor Green
Write-Host "Smoke-build: python build.py --flutter --hwcodec --vram --skip-portable-pack" -ForegroundColor Cyan
Write-Host "Artifact: flutter\build\windows\x64\runner\Release\" -ForegroundColor Cyan
exit 0
