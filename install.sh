#!/usr/bin/env bash
# SuperModelingFactory one-line installer
#
# Usage:
#   export SMF_TOKEN="github_pat_..."
#   bash <(curl -fsSL https://raw.githubusercontent.com/Kyle-J-Sun/SMF_pypi/main/install.sh)
#
# Optional environment variables:
#   SMF_TOKEN     (required) GitHub fine-grained PAT with Contents:Read on
#                            Kyle-J-Sun/SuperModelingFactory_protected
#   SMF_VERSION   (default: latest)  e.g. "v0.1.0"
#   SMF_PYTHON    (default: auto-detected)  full path to Python interpreter
#                 to install into. Auto-detection prefers conda > Homebrew
#                 > pyenv > system python3.13/3.12/3.11/3.10.
#
# What this script does:
#   1. Verifies prerequisites (token, Python, libomp on macOS).
#   2. Detects the wheel matching this machine.
#   3. Downloads it via the GitHub API (PAT-authenticated).
#   4. pip install --force-reinstall the wheel.
#   5. Smoke-imports key SMF modules to verify success.

set -euo pipefail

REPO="Kyle-J-Sun/SuperModelingFactory_protected"
PKG="supermodelingfactory"

err()  { printf "\033[31m[ERROR]\033[0m %s\n" "$*" >&2; exit 1; }
info() { printf "\033[36m[INFO ]\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m[ OK  ]\033[0m %s\n" "$*"; }

# ---------- 1. Validate token ----------
[ -n "${SMF_TOKEN:-}" ] || err "SMF_TOKEN is not set. Export your GitHub fine-grained PAT first:
  export SMF_TOKEN=\"github_pat_...\"
See https://github.com/settings/personal-access-tokens/new"

# ---------- 2. Pick Python interpreter ----------
detect_python() {
  if [ -n "${SMF_PYTHON:-}" ] && [ -x "$SMF_PYTHON" ]; then
    echo "$SMF_PYTHON"; return
  fi
  # Try arm64-safe candidates in priority order
  for candidate in \
    "$HOME/miniconda3/bin/python3.13" \
    "$HOME/miniconda3/bin/python3.12" \
    "$HOME/miniconda3/bin/python3.11" \
    "$HOME/miniconda3/bin/python3.10" \
    "$HOME/anaconda3/bin/python3.13" \
    "$HOME/anaconda3/bin/python3.12" \
    "$HOME/anaconda3/bin/python3.11" \
    "$HOME/anaconda3/bin/python3.10" \
    "/opt/homebrew/bin/python3.13" \
    "/opt/homebrew/bin/python3.12" \
    "/opt/homebrew/bin/python3.11" \
    "/opt/homebrew/bin/python3.10" \
    "/usr/local/bin/python3.13" \
    "/usr/local/bin/python3.12" \
    "/usr/local/bin/python3.11" \
    "/usr/local/bin/python3.10"
  do
    if [ -x "$candidate" ]; then
      # Skip x86_64 Pythons on arm64 hosts (avoid "Bad CPU type")
      host_arch=$(uname -m)
      py_arch=$("$candidate" -c "import platform; print(platform.machine())" 2>/dev/null || echo unknown)
      if [ "$host_arch" = "arm64" ] && [ "$py_arch" != "arm64" ]; then
        continue
      fi
      echo "$candidate"; return
    fi
  done
  err "Could not find a suitable Python 3.10-3.13 interpreter. Set SMF_PYTHON to the full path."
}

PY=$(detect_python)
PY_VERSION=$("$PY" --version 2>&1)
PY_ARCH=$("$PY" -c "import platform; print(platform.machine())")
info "Using Python: $PY ($PY_VERSION, $PY_ARCH)"

# ---------- 3. Platform / wheel name ----------
PYTAG=$("$PY" -c "import sys; print(f'cp{sys.version_info.major}{sys.version_info.minor}')")
PLATFORM=$("$PY" -c "
import platform, sys
m = platform.machine(); s = sys.platform
print(f'macosx_11_0_{m}' if s=='darwin' else
      'manylinux_2_17_x86_64.manylinux2014_x86_64.manylinux_2_28_x86_64' if s=='linux' else
      'win_amd64')
")

# ---------- 4. libomp check (macOS) ----------
if [ "$(uname -s)" = "Darwin" ]; then
  if [ ! -f "/opt/homebrew/opt/libomp/lib/libomp.dylib" ] && [ ! -f "/usr/local/opt/libomp/lib/libomp.dylib" ]; then
    info "libomp not detected. Installing via Homebrew (required by lightgbm)..."
    if ! command -v brew >/dev/null 2>&1; then
      err "Homebrew not found. Install from https://brew.sh, then re-run this script."
    fi
    brew install libomp
  fi
  ok "libomp available"
fi

# ---------- 5. Resolve version ----------
SMF_VERSION="${SMF_VERSION:-latest}"
if [ "$SMF_VERSION" = "latest" ]; then
  TAG=$(curl -fsSL -H "Authorization: token $SMF_TOKEN" \
                   -H "Accept: application/vnd.github+json" \
       "https://api.github.com/repos/$REPO/releases/latest" \
       | "$PY" -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")
else
  TAG="$SMF_VERSION"
fi
VERSION="${TAG#v}"
WHEEL="${PKG}-${VERSION}-${PYTAG}-${PYTAG}-${PLATFORM}.whl"
info "Target wheel: $WHEEL (release $TAG)"

# ---------- 6. Resolve asset ID ----------
ASSET_ID=$(curl -fsSL -H "Authorization: token $SMF_TOKEN" \
                      -H "Accept: application/vnd.github+json" \
                      "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
  | "$PY" -c "
import json, sys
data = json.load(sys.stdin)
for a in data['assets']:
    if a['name'] == '$WHEEL':
        print(a['id']); sys.exit(0)
sys.exit('no asset named $WHEEL in release $TAG')
")
ok "Asset ID: $ASSET_ID"

# ---------- 7. Download wheel ----------
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"
info "Downloading wheel..."
curl -fsSL -H "Authorization: token $SMF_TOKEN" \
           -H "Accept: application/octet-stream" \
           -o "$WHEEL" \
           "https://api.github.com/repos/$REPO/releases/assets/$ASSET_ID"
WHEEL_SIZE=$(wc -c < "$WHEEL" | tr -d ' ')
ok "Downloaded $WHEEL ($WHEEL_SIZE bytes)"

# ---------- 8. pip install ----------
info "Installing into $PY ..."
"$PY" -m pip install --upgrade pip >/dev/null
"$PY" -m pip install --force-reinstall "$WHEEL"

# ---------- 9. Smoke verify ----------
info "Verifying import..."
"$PY" - <<'PY_EOF'
import Modeling_Tool
from Modeling_Tool import WOE_Master, LRMaster, PSICalculator
print("SMF version :", getattr(Modeling_Tool, "__version__", "n/a"))
print("Install path:", Modeling_Tool.__file__)
PY_EOF

ok "SMF installed successfully."
echo
echo "Next steps:"
echo "  $PY -c 'import Modeling_Tool; print(dir(Modeling_Tool))'"
echo "  # or open a notebook with this Python kernel and 'from Modeling_Tool import ...'"
