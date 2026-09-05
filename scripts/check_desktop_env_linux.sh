#!/usr/bin/env bash
# Checks local prerequisites for building the BetterDesk / RustDesk Flutter desktop client on Linux x64.
# Read-only; does not install packages. Versions aligned with CI (Flutter 3.24.5, Rust 1.75, vcpkg commit).

set -uo pipefail

EXPECTED_FLUTTER="3.24.5"
EXPECTED_RUST="1.75"
EXPECTED_VCPKG_COMMIT="9e593bb18ea69cc5095e012465dcd675a822ed0d"
EXPECTED_TRIPLET="x64-linux"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

failures=0
warnings=0

ok()   { printf '[OK]  %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }
info() { printf '[INFO] %s\n' "$*"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

info "Repo root: ${REPO_ROOT}"
info "Expected: Flutter ${EXPECTED_FLUTTER}, Rust ${EXPECTED_RUST}, vcpkg ${EXPECTED_VCPKG_COMMIT}"
echo

# --- Git / submodule ---
if have_cmd git; then
  ok "git: $(git --version)"
else
  fail "git not found on PATH"
fi

if [[ -f libs/hbb_common/Cargo.toml && -f libs/hbb_common/src/config.rs ]]; then
  ok "submodule libs/hbb_common present (Cargo.toml + config.rs)"
else
  fail "libs/hbb_common incomplete — run: git submodule update --init --recursive"
fi

# --- Python ---
if have_cmd python3; then
  ok "Python: $(python3 --version 2>&1)"
elif have_cmd python; then
  ok "Python: $(python --version 2>&1)"
else
  fail "Python 3 not found (needed for build.py)"
fi

# --- Rust ---
if have_cmd rustc; then
  rustc_ver="$(rustc --version 2>&1)"
  if [[ "${rustc_ver}" == *"${EXPECTED_RUST}"* ]]; then
    ok "rustc: ${rustc_ver}"
  else
    warn "rustc: ${rustc_ver} (CI uses ${EXPECTED_RUST} — rustup toolchain install ${EXPECTED_RUST})"
  fi
else
  fail "rustc not found — install rustup and toolchain ${EXPECTED_RUST}"
fi

if have_cmd cargo; then
  ok "cargo: $(cargo --version 2>&1)"
else
  fail "cargo not found"
fi

if have_cmd rustup; then
  if rustup target list --installed 2>/dev/null | grep -qx 'x86_64-unknown-linux-gnu'; then
    ok "rustup target x86_64-unknown-linux-gnu installed"
  else
    warn "target x86_64-unknown-linux-gnu not listed — run: rustup target add x86_64-unknown-linux-gnu"
  fi
  if ! rustup toolchain list 2>/dev/null | grep -q '1\.75'; then
    warn "toolchain 1.75 not installed — run: rustup toolchain install 1.75"
  fi
else
  warn "rustup not found (harder to pin Rust ${EXPECTED_RUST})"
fi

# --- Flutter ---
if have_cmd flutter; then
  flutter_line="$(flutter --version 2>&1 | head -n 1)"
  if flutter --version 2>&1 | grep -q "${EXPECTED_FLUTTER}"; then
    ok "Flutter: ${flutter_line}"
  else
    warn "Flutter: ${flutter_line} (CI uses ${EXPECTED_FLUTTER})"
  fi
else
  fail "flutter not found on PATH"
fi

# --- VCPKG_ROOT ---
if [[ -z "${VCPKG_ROOT:-}" ]]; then
  fail "VCPKG_ROOT is not set"
elif [[ ! -d "${VCPKG_ROOT}" ]]; then
  fail "VCPKG_ROOT points to missing path: ${VCPKG_ROOT}"
else
  ok "VCPKG_ROOT=${VCPKG_ROOT}"
  if [[ -x "${VCPKG_ROOT}/vcpkg" ]]; then
    ok "vcpkg binary found"
  else
    fail "vcpkg executable not found under VCPKG_ROOT (run ./bootstrap-vcpkg.sh)"
  fi
  if [[ -d "${VCPKG_ROOT}/.git" ]] || git -C "${VCPKG_ROOT}" rev-parse HEAD >/dev/null 2>&1; then
    head="$(git -C "${VCPKG_ROOT}" rev-parse HEAD 2>/dev/null || true)"
    if [[ "${head}" == "${EXPECTED_VCPKG_COMMIT}" ]]; then
      ok "vcpkg commit matches CI (${EXPECTED_VCPKG_COMMIT})"
    elif [[ -n "${head}" ]]; then
      warn "vcpkg commit is ${head} (CI expects ${EXPECTED_VCPKG_COMMIT})"
    else
      warn "could not read vcpkg git HEAD"
    fi
  else
    warn "VCPKG_ROOT does not look like a git checkout; cannot verify commit"
  fi
  if [[ -d "${VCPKG_ROOT}/installed/${EXPECTED_TRIPLET}" ]]; then
    ok "vcpkg installed triplet present: ${EXPECTED_TRIPLET}"
  else
    warn "installed/${EXPECTED_TRIPLET} not found — from repo root: \"\${VCPKG_ROOT}/vcpkg\" install --triplet ${EXPECTED_TRIPLET} --x-install-root=\"\${VCPKG_ROOT}/installed\""
  fi
fi

# --- libclang ---
if [[ -n "${LIBCLANG_PATH:-}" ]]; then
  if [[ -d "${LIBCLANG_PATH}" ]]; then
    ok "LIBCLANG_PATH=${LIBCLANG_PATH}"
  else
    fail "LIBCLANG_PATH points to missing path: ${LIBCLANG_PATH}"
  fi
else
  warn "LIBCLANG_PATH is not set (bindgen may still find system libclang)"
fi

if have_cmd clang; then
  ok "clang: $(clang --version 2>&1 | head -n 1)"
else
  warn "clang not on PATH"
fi

if have_cmd cmake; then
  ok "cmake: $(cmake --version 2>&1 | head -n 1)"
else
  warn "cmake not on PATH"
fi

# --- Key apt packages (Debian/Ubuntu) ---
REQUIRED_PKGS=(
  build-essential
  clang
  cmake
  nasm
  ninja-build
  pkg-config
  libgtk-3-dev
  libasound2-dev
  libpulse-dev
  libva-dev
  libclang-dev
  libgstreamer1.0-dev
  libxcb-randr0-dev
  libxdo-dev
  libssl-dev
)

if have_cmd dpkg-query; then
  missing=()
  for pkg in "${REQUIRED_PKGS[@]}"; do
    if dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q 'install ok installed'; then
      :
    else
      missing+=("${pkg}")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "required apt packages installed (${#REQUIRED_PKGS[@]} checked)"
  else
    warn "missing apt packages: ${missing[*]}"
    warn "see docs/BUILD_DESKTOP.md for the full apt-get install list"
  fi

  if dpkg-query -W -f='${Status}' libopus-dev 2>/dev/null | grep -q 'install ok installed'; then
    warn "libopus-dev is installed — can conflict with vcpkg opus; remove with: sudo apt-get remove -y libopus-dev"
  else
    ok "libopus-dev not installed (good for vcpkg opus)"
  fi
else
  warn "dpkg-query not available — skip apt package checks (non-Debian?)"
fi

# Optional pkg-config probes
if have_cmd pkg-config; then
  for mod in gtk+-3.0 libpulse; do
    if pkg-config --exists "${mod}" 2>/dev/null; then
      ok "pkg-config ${mod}"
    else
      warn "pkg-config module ${mod} not found"
    fi
  done
fi

echo
if [[ "${failures}" -gt 0 ]]; then
  printf 'Result: %s failure(s), %s warning(s). Fix FAIL items before building.\n' "${failures}" "${warnings}"
  echo "See docs/BUILD_DESKTOP.md"
  exit 1
fi
printf 'Result: all required checks passed (%s warning(s)).\n' "${warnings}"
echo "Smoke-build: python3 ./build.py --flutter --hwcodec"
echo "Artifact: flutter/build/linux/x64/release/bundle/"
exit 0
