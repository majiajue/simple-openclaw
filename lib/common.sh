#!/usr/bin/env bash

set -euo pipefail

case ":$PATH:" in
  *:/usr/local/bin:*) ;;
  *) export PATH="/usr/local/bin:$PATH" ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMPLE_OPENCLAW_HOME="${SIMPLE_OPENCLAW_HOME:-$HOME/.simple-openclaw}"
CONFIG_DIR="$SIMPLE_OPENCLAW_HOME/config"
CHANNEL_DIR="$CONFIG_DIR/channels"
BACKUP_DIR="$SIMPLE_OPENCLAW_HOME/backups"
LOG_DIR="$SIMPLE_OPENCLAW_HOME/logs"
CACHE_DIR="$SIMPLE_OPENCLAW_HOME/cache"
SNAPSHOT_DIR="$SIMPLE_OPENCLAW_HOME/snapshots"
REPORT_DIR="$SIMPLE_OPENCLAW_HOME/reports"
STATE_DIR="$SIMPLE_OPENCLAW_HOME/state"
DOCTOR_REPORT_DIR="$REPORT_DIR/doctor"
SECURITY_REPORT_DIR="$REPORT_DIR/security"
BUNDLE_REPORT_DIR="$REPORT_DIR/support-bundle"
ENV_FILE="$CONFIG_DIR/env"
SECRETS_FILE="$CONFIG_DIR/secrets.json"
POLICY_FILE="$CONFIG_DIR/policy.json"
PLUGIN_DB_FILE="$STATE_DIR/installed_plugins.db"
PLUGIN_STATE_FILE="$STATE_DIR/installed_plugins.json"
SERVICE_STATE_FILE="$STATE_DIR/service_state.json"
LAST_PROBE_FILE="$STATE_DIR/last_probe.json"
RELEASE_LOCK_FILE="$STATE_DIR/release_lock.json"
GATEWAY_PID_FILE="$STATE_DIR/gateway.pid"
VERSION_FILE="$ROOT_DIR/version"
DEFAULT_GATEWAY_PORT="18789"
DEFAULT_OPENCLAW_NPM_PACKAGE="openclaw"

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

timestamp() {
  date '+%Y%m%d-%H%M%S'
}

iso_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_jq() {
  command_exists jq || die "jq is required for this command"
}

detect_os() {
  uname -s
}

detect_service_manager() {
  if command_exists systemctl; then
    printf 'systemd-user'
  elif command_exists launchctl; then
    printf 'launchd'
  else
    printf 'none'
  fi
}

auto_install_node() {
  local target_major="${1:-22}"
  local os arch node_ver tarball url tmp_dir

  os="$(uname -s)"
  arch="$(uname -m)"

  case "$arch" in
    x86_64)  arch="x64"   ;;
    aarch64|arm64) arch="arm64" ;;
    armv7l)  arch="armv7l" ;;
    *)       die "unsupported architecture for auto-install: $arch" ;;
  esac

  case "$os" in
    Linux)  os="linux"  ;;
    Darwin) os="darwin" ;;
    *)      die "unsupported OS for auto-install: $os" ;;
  esac

  info "resolving latest Node.js ${target_major}.x version..."
  if command_exists curl; then
    node_ver="$(curl -fsSL "https://resolve-node.now.sh/${target_major}" 2>/dev/null || true)"
  elif command_exists wget; then
    node_ver="$(wget -qO- "https://resolve-node.now.sh/${target_major}" 2>/dev/null || true)"
  fi

  if [[ -z "$node_ver" ]]; then
    node_ver="v${target_major}.0.0"
    warn "could not resolve latest version, falling back to $node_ver"
  fi

  local use_unofficial=0
  if [[ "$os" == "linux" ]]; then
    local glibc_ver
    glibc_ver="$(ldd --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
    if [[ -n "$glibc_ver" ]]; then
      local glibc_major glibc_minor
      glibc_major="${glibc_ver%%.*}"
      glibc_minor="${glibc_ver##*.}"
      if [[ "$glibc_major" -lt 2 ]] || { [[ "$glibc_major" -eq 2 ]] && [[ "$glibc_minor" -lt 28 ]]; }; then
        info "detected GLIBC ${glibc_ver} (< 2.28); using unofficial-builds for compatibility"
        use_unofficial=1
      fi
    fi
  fi

  if [[ "$use_unofficial" -eq 1 ]]; then
    tarball="node-${node_ver}-${os}-${arch}-glibc-217.tar.xz"
    url="https://unofficial-builds.nodejs.org/download/release/${node_ver}/${tarball}"
  else
    tarball="node-${node_ver}-${os}-${arch}.tar.xz"
    url="https://nodejs.org/dist/${node_ver}/${tarball}"
  fi

  local extracted_name="node-${node_ver}-${os}-${arch}"
  tmp_dir="$(mktemp -d)"

  info "downloading Node.js ${node_ver} for ${os}-${arch}..."
  if command_exists curl; then
    curl -fsSL "$url" -o "${tmp_dir}/${tarball}" || {
      if [[ "$use_unofficial" -eq 0 ]]; then
        die "failed to download Node.js from $url"
      fi
      warn "unofficial-builds download failed; trying official build as fallback"
      tarball="node-${node_ver}-${os}-${arch}.tar.xz"
      url="https://nodejs.org/dist/${node_ver}/${tarball}"
      curl -fsSL "$url" -o "${tmp_dir}/${tarball}" || die "failed to download Node.js from $url"
      use_unofficial=0
    }
  elif command_exists wget; then
    wget -q "$url" -O "${tmp_dir}/${tarball}" || {
      if [[ "$use_unofficial" -eq 0 ]]; then
        die "failed to download Node.js from $url"
      fi
      warn "unofficial-builds download failed; trying official build as fallback"
      tarball="node-${node_ver}-${os}-${arch}.tar.xz"
      url="https://nodejs.org/dist/${node_ver}/${tarball}"
      wget -q "$url" -O "${tmp_dir}/${tarball}" || die "failed to download Node.js from $url"
      use_unofficial=0
    }
  else
    die "curl or wget is required to auto-install Node.js"
  fi

  local install_prefix="/usr/local"
  info "extracting Node.js to ${install_prefix}..."
  tar -xJf "${tmp_dir}/${tarball}" -C "$tmp_dir"
  local extracted_dir="${tmp_dir}/${extracted_name}"
  if [[ ! -d "$extracted_dir" ]]; then
    extracted_dir="${tmp_dir}/${tarball%.tar.xz}"
  fi

  cp -f "${extracted_dir}/bin/node" "${install_prefix}/bin/node"
  cp -rf "${extracted_dir}/lib/node_modules" "${install_prefix}/lib/node_modules"
  ln -sf "${install_prefix}/lib/node_modules/npm/bin/npm-cli.js" "${install_prefix}/bin/npm"
  ln -sf "${install_prefix}/lib/node_modules/npm/bin/npx-cli.js" "${install_prefix}/bin/npx"
  if [[ -d "${extracted_dir}/lib/node_modules/corepack" ]]; then
    ln -sf "${install_prefix}/lib/node_modules/corepack/dist/corepack.js" "${install_prefix}/bin/corepack" 2>/dev/null || true
  fi
  chmod +x "${install_prefix}/bin/node"
  rm -rf "$tmp_dir"

  export PATH="${install_prefix}/bin:$PATH"
  hash -r 2>/dev/null || true

  local installed
  installed="$("${install_prefix}/bin/node" -v 2>/dev/null || true)"
  if [[ -z "$installed" ]]; then
    local diag
    diag="$("${install_prefix}/bin/node" -v 2>&1 || true)"
    die "Node.js auto-install failed; binary is not functional after extraction: $diag"
  fi

  if [[ -e "/usr/bin/node" ]] && ! /usr/bin/node -v >/dev/null 2>&1; then
    ln -sf "${install_prefix}/bin/node" /usr/bin/node
    info "replaced broken /usr/bin/node with symlink to ${install_prefix}/bin/node"
  fi

  info "Node.js ${installed} installed successfully"
}

find_working_node() {
  local candidate
  for candidate in /usr/local/bin/node /usr/bin/node; do
    if [[ -x "$candidate" ]] && "$candidate" -v >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  candidate="$(command -v node 2>/dev/null || true)"
  if [[ -n "$candidate" ]] && "$candidate" -v >/dev/null 2>&1; then
    printf '%s' "$candidate"
    return 0
  fi
  printf ''
}

detect_system_package_manager() {
  if command_exists apt-get; then
    printf 'apt'
  elif command_exists dnf; then
    printf 'dnf'
  elif command_exists yum; then
    printf 'yum'
  elif command_exists apk; then
    printf 'apk'
  elif command_exists pacman; then
    printf 'pacman'
  elif command_exists zypper; then
    printf 'zypper'
  elif command_exists brew; then
    printf 'brew'
  else
    printf ''
  fi
}

detect_distro() {
  local os
  os="$(uname -s)"
  if [[ "$os" == "Darwin" ]]; then
    printf 'macos'
    return
  fi
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian|linuxmint|pop|elementary|kali|raspbian)
        printf 'debian'
        ;;
      centos|rhel|rocky|almalinux|ol|amzn|fedora)
        printf 'rhel'
        ;;
      alpine)
        printf 'alpine'
        ;;
      arch|manjaro|endeavouros)
        printf 'arch'
        ;;
      opensuse*|sles)
        printf 'suse'
        ;;
      *)
        printf 'unknown'
        ;;
    esac
  elif [[ -f /etc/redhat-release ]]; then
    printf 'rhel'
  elif [[ -f /etc/debian_version ]]; then
    printf 'debian'
  elif [[ -f /etc/alpine-release ]]; then
    printf 'alpine'
  else
    printf 'unknown'
  fi
}

cmake_version() {
  if command_exists cmake; then
    cmake --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1
  else
    printf ''
  fi
}

cmake_needs_upgrade() {
  local ver major minor
  ver="$(cmake_version)"
  if [[ -z "$ver" ]]; then
    return 0
  fi
  major="${ver%%.*}"
  minor="${ver##*.}"
  if [[ "$major" -lt 3 ]] || { [[ "$major" -eq 3 ]] && [[ "$minor" -lt 19 ]]; }; then
    return 0
  fi
  return 1
}

install_cmake_binary() {
  local cmake_ver="3.28.6"
  local os arch platform tmp_dir url
  os="$(uname -s)"
  arch="$(uname -m)"
  tmp_dir="$(mktemp -d)"

  case "$os" in
    Linux)
      case "$arch" in
        x86_64)  platform="linux-x86_64" ;;
        aarch64) platform="linux-aarch64" ;;
        *)
          rm -rf "$tmp_dir"
          return 1
          ;;
      esac
      url="https://github.com/Kitware/CMake/releases/download/v${cmake_ver}/cmake-${cmake_ver}-${platform}.tar.gz"
      ;;
    Darwin)
      platform="macos-universal"
      url="https://github.com/Kitware/CMake/releases/download/v${cmake_ver}/cmake-${cmake_ver}-${platform}.tar.gz"
      ;;
    *)
      rm -rf "$tmp_dir"
      return 1
      ;;
  esac

  info "downloading CMake ${cmake_ver} for ${platform}..."
  if command_exists curl; then
    curl -fsSL "$url" -o "${tmp_dir}/cmake.tar.gz" || { rm -rf "$tmp_dir"; return 1; }
  elif command_exists wget; then
    wget -q "$url" -O "${tmp_dir}/cmake.tar.gz" || { rm -rf "$tmp_dir"; return 1; }
  else
    rm -rf "$tmp_dir"
    return 1
  fi

  tar -xzf "${tmp_dir}/cmake.tar.gz" -C "$tmp_dir"
  local cmake_dir="${tmp_dir}/cmake-${cmake_ver}-${platform}"

  if [[ "$os" == "Darwin" ]]; then
    local app_dir="${cmake_dir}/CMake.app/Contents"
    if [[ -d "$app_dir" ]]; then
      cp -f "${app_dir}/bin/cmake" /usr/local/bin/cmake
      cp -f "${app_dir}/bin/ctest" /usr/local/bin/ctest
      cp -f "${app_dir}/bin/cpack" /usr/local/bin/cpack
    else
      cp -f "${cmake_dir}/bin/cmake" /usr/local/bin/cmake
      cp -f "${cmake_dir}/bin/ctest" /usr/local/bin/ctest
      cp -f "${cmake_dir}/bin/cpack" /usr/local/bin/cpack
    fi
  else
    cp -f "${cmake_dir}/bin/cmake" /usr/local/bin/cmake
    cp -f "${cmake_dir}/bin/ctest" /usr/local/bin/ctest
    cp -f "${cmake_dir}/bin/cpack" /usr/local/bin/cpack
    if ls -d "${cmake_dir}"/share/cmake-* >/dev/null 2>&1; then
      cp -rf "${cmake_dir}"/share/cmake-* /usr/local/share/ 2>/dev/null || true
    fi
  fi

  chmod +x /usr/local/bin/cmake /usr/local/bin/ctest /usr/local/bin/cpack
  rm -rf "$tmp_dir"
  hash -r 2>/dev/null || true

  info "CMake $(cmake --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+') installed"
}

ensure_build_tools_debian() {
  local sys_pm="apt"
  local missing_pkgs=""

  if ! command_exists jq; then missing_pkgs="$missing_pkgs jq"; fi
  if ! command_exists git; then missing_pkgs="$missing_pkgs git"; fi
  if ! command_exists make; then missing_pkgs="$missing_pkgs build-essential"; fi
  if ! command_exists g++ && ! command_exists c++; then missing_pkgs="$missing_pkgs build-essential"; fi
  if ! command_exists python3 && ! command_exists python; then missing_pkgs="$missing_pkgs python3"; fi

  missing_pkgs="$(printf '%s' "$missing_pkgs" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/^ *//;s/ *$//')"

  if [[ -n "$missing_pkgs" ]]; then
    info "installing build tools via apt: $missing_pkgs"
    apt-get update -qq >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    apt-get install -y -qq $missing_pkgs >/dev/null 2>&1 || die "failed to install $missing_pkgs via apt"
    info "build tools installed"
  fi
}

ensure_build_tools_rhel() {
  local sys_pm="$1"
  local missing_pkgs=""

  if ! command_exists jq; then missing_pkgs="$missing_pkgs jq"; fi
  if ! command_exists git; then missing_pkgs="$missing_pkgs git"; fi
  if ! command_exists make; then missing_pkgs="$missing_pkgs make"; fi
  if ! command_exists g++ && ! command_exists c++; then missing_pkgs="$missing_pkgs gcc-c++"; fi
  if ! command_exists python3 && ! command_exists python; then missing_pkgs="$missing_pkgs python3"; fi

  if [[ -n "$missing_pkgs" ]]; then
    info "installing build tools via $sys_pm:$missing_pkgs"
    # shellcheck disable=SC2086
    "$sys_pm" install -y -q $missing_pkgs >/dev/null 2>&1 || {
      info "trying Development Tools group..."
      "$sys_pm" groupinstall -y -q "Development Tools" >/dev/null 2>&1 || true
    }
    info "build tools installed"
  fi
}

ensure_build_tools_alpine() {
  local missing_pkgs=""

  if ! command_exists jq; then missing_pkgs="$missing_pkgs jq"; fi
  if ! command_exists git; then missing_pkgs="$missing_pkgs git"; fi
  if ! command_exists make || ! command_exists g++; then missing_pkgs="$missing_pkgs build-base"; fi
  if ! command_exists python3 && ! command_exists python; then missing_pkgs="$missing_pkgs python3"; fi
  if ! command_exists cmake; then missing_pkgs="$missing_pkgs cmake"; fi

  if [[ -n "$missing_pkgs" ]]; then
    info "installing build tools via apk:$missing_pkgs"
    # shellcheck disable=SC2086
    apk add --quiet $missing_pkgs >/dev/null 2>&1 || die "failed to install$missing_pkgs via apk"
    info "build tools installed"
  fi
}

ensure_build_tools_arch() {
  local missing_pkgs=""

  if ! command_exists jq; then missing_pkgs="$missing_pkgs jq"; fi
  if ! command_exists git; then missing_pkgs="$missing_pkgs git"; fi
  if ! command_exists make || ! command_exists g++; then missing_pkgs="$missing_pkgs base-devel"; fi
  if ! command_exists python3 && ! command_exists python; then missing_pkgs="$missing_pkgs python"; fi
  if ! command_exists cmake; then missing_pkgs="$missing_pkgs cmake"; fi

  if [[ -n "$missing_pkgs" ]]; then
    info "installing build tools via pacman:$missing_pkgs"
    # shellcheck disable=SC2086
    pacman -S --noconfirm --needed $missing_pkgs >/dev/null 2>&1 || die "failed to install$missing_pkgs via pacman"
    info "build tools installed"
  fi
}

ensure_build_tools_suse() {
  local missing_pkgs=""

  if ! command_exists jq; then missing_pkgs="$missing_pkgs jq"; fi
  if ! command_exists git; then missing_pkgs="$missing_pkgs git"; fi
  if ! command_exists make; then missing_pkgs="$missing_pkgs make"; fi
  if ! command_exists g++ && ! command_exists c++; then missing_pkgs="$missing_pkgs gcc-c++"; fi
  if ! command_exists python3 && ! command_exists python; then missing_pkgs="$missing_pkgs python3"; fi
  if ! command_exists cmake; then missing_pkgs="$missing_pkgs cmake"; fi

  if [[ -n "$missing_pkgs" ]]; then
    info "installing build tools via zypper:$missing_pkgs"
    # shellcheck disable=SC2086
    zypper install -y $missing_pkgs >/dev/null 2>&1 || die "failed to install$missing_pkgs via zypper"
    info "build tools installed"
  fi
}

ensure_build_tools_macos() {
  if ! xcode-select -p >/dev/null 2>&1; then
    info "installing Xcode Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    until xcode-select -p >/dev/null 2>&1; do
      info "waiting for Xcode Command Line Tools installation..."
      sleep 5
    done
    info "Xcode Command Line Tools installed"
  fi

  if command_exists brew; then
    if ! command_exists jq; then
      info "installing jq via Homebrew..."
      brew install jq >/dev/null 2>&1 || true
    fi
    if ! command_exists cmake; then
      info "installing cmake via Homebrew..."
      brew install cmake >/dev/null 2>&1 || true
    fi
  fi
}

ensure_build_tools() {
  local os distro
  os="$(detect_os)"
  distro="$(detect_distro)"

  info "checking build prerequisites (${distro})..."

  case "$distro" in
    macos)
      ensure_build_tools_macos
      ;;
    debian)
      ensure_build_tools_debian
      ;;
    rhel)
      local sys_pm
      if command_exists dnf; then sys_pm="dnf"; else sys_pm="yum"; fi
      ensure_build_tools_rhel "$sys_pm"
      ;;
    alpine)
      ensure_build_tools_alpine
      ;;
    arch)
      ensure_build_tools_arch
      ;;
    suse)
      ensure_build_tools_suse
      ;;
    *)
      local sys_pm
      sys_pm="$(detect_system_package_manager)"
      if [[ -z "$sys_pm" ]]; then
        warn "unknown distro and no package manager found; skipping build tool check"
        return 0
      fi
      local missing_pkgs=""
      if ! command_exists jq; then missing_pkgs="$missing_pkgs jq"; fi
      if ! command_exists git; then missing_pkgs="$missing_pkgs git"; fi
      if ! command_exists make; then missing_pkgs="$missing_pkgs make"; fi
      if ! command_exists g++ && ! command_exists c++; then missing_pkgs="$missing_pkgs g++"; fi
      if [[ -n "$missing_pkgs" ]]; then
        info "installing build tools via $sys_pm:$missing_pkgs"
        case "$sys_pm" in
          apt) apt-get update -qq >/dev/null 2>&1 || true; apt-get install -y -qq $missing_pkgs >/dev/null 2>&1 || true ;;
          dnf|yum) $sys_pm install -y -q $missing_pkgs >/dev/null 2>&1 || true ;;
          *) warn "could not install build tools automatically" ;;
        esac
      fi
      ;;
  esac

  if [[ "$distro" != "macos" ]] && cmake_needs_upgrade; then
    local current_cmake
    current_cmake="$(cmake_version)"
    if [[ -n "$current_cmake" ]]; then
      info "CMake ${current_cmake} is too old (need 3.19+); upgrading..."
    else
      info "CMake not found; installing..."
    fi
    install_cmake_binary || {
      warn "could not install CMake binary; trying system package manager..."
      local sys_pm
      sys_pm="$(detect_system_package_manager)"
      case "$sys_pm" in
        apt) apt-get install -y -qq cmake >/dev/null 2>&1 || true ;;
        dnf|yum) "$sys_pm" install -y -q cmake >/dev/null 2>&1 || true ;;
        apk) apk add --quiet cmake >/dev/null 2>&1 || true ;;
        pacman) pacman -S --noconfirm cmake >/dev/null 2>&1 || true ;;
        zypper) zypper install -y cmake >/dev/null 2>&1 || true ;;
      esac
      if cmake_needs_upgrade; then
        warn "CMake is still too old ($(cmake_version)); node-llama-cpp may fail to build"
      fi
    }
  fi

  info "build prerequisites satisfied"
}

node_version() {
  if command_exists node; then
    local raw
    raw="$(node -v 2>/dev/null)" || { printf ''; return; }
    printf '%s' "$raw" | sed 's/^v//'
  else
    printf ''
  fi
}

node_major_version() {
  local version
  version="$(node_version)"
  if [[ -z "$version" ]]; then
    printf '0'
  else
    printf '%s' "${version%%.*}"
  fi
}

openclaw_bin() {
  local configured
  configured="$(env_get OPENCLAW_BIN || true)"
  if [[ -n "$configured" && -x "$configured" ]]; then
    printf '%s' "$configured"
  elif command_exists openclaw; then
    command -v openclaw
  else
    printf ''
  fi
}

gateway_port() {
  local val
  val="$(env_get OPENCLAW_GATEWAY_PORT || true)"
  if [[ -n "$val" ]]; then
    printf '%s' "$val"
  else
    printf '%s' "$DEFAULT_GATEWAY_PORT"
  fi
}

gateway_command() {
  env_get OPENCLAW_GATEWAY_CMD || true
}

package_manager() {
  local manager
  manager="$(env_get OPENCLAW_PACKAGE_MANAGER || true)"
  if [[ -n "$manager" ]]; then
    printf '%s' "$manager"
  elif command_exists npm; then
    printf 'npm'
  elif command_exists pnpm; then
    printf 'pnpm'
  else
    printf ''
  fi
}

openclaw_npm_package() {
  local val
  val="$(env_get OPENCLAW_NPM_PACKAGE || true)"
  if [[ -n "$val" ]]; then
    printf '%s' "$val"
  else
    printf '%s' "$DEFAULT_OPENCLAW_NPM_PACKAGE"
  fi
}

update_channel() {
  local val
  val="$(env_get OPENCLAW_UPDATE_CHANNEL || true)"
  if [[ -n "$val" ]]; then
    printf '%s' "$val"
  else
    printf 'stable'
  fi
}

channel_to_dist_tag() {
  case "$1" in
    stable) printf 'latest' ;;
    beta) printf 'beta' ;;
    dev) printf 'dev' ;;
    latest|next) printf '%s' "$1" ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

run_cmd() {
  local dry_run="${SIMPLE_OPENCLAW_DRY_RUN:-0}"
  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run="1"
    shift
  fi
  if [[ "$dry_run" == "1" ]]; then
    printf '[DRY-RUN] %s\n' "$*"
    return 0
  fi
  "$@"
}

ensure_supported_package_manager() {
  local manager="$1"
  case "$manager" in
    npm|pnpm)
      command_exists "$manager" || die "package manager not found: $manager"
      ;;
    *)
      die "unsupported package manager: $manager"
      ;;
  esac
}

npm_global_install_cmd() {
  local manager="$1"
  local spec="$2"
  case "$manager" in
    npm)
      printf 'npm install -g %s' "$spec"
      ;;
    pnpm)
      printf 'pnpm add -g %s' "$spec"
      ;;
  esac
}

ensure_runtime_dirs() {
  mkdir -p \
    "$CONFIG_DIR" \
    "$CHANNEL_DIR" \
    "$BACKUP_DIR" \
    "$LOG_DIR" \
    "$CACHE_DIR" \
    "$SNAPSHOT_DIR" \
    "$DOCTOR_REPORT_DIR" \
    "$SECURITY_REPORT_DIR" \
    "$BUNDLE_REPORT_DIR" \
    "$STATE_DIR"

  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ROOT_DIR/templates/env.example" "$ENV_FILE"
  fi

  if [[ ! -f "$SECRETS_FILE" ]]; then
    cp "$ROOT_DIR/templates/secrets.example" "$SECRETS_FILE"
  fi

  if [[ ! -f "$POLICY_FILE" ]]; then
    cp "$ROOT_DIR/templates/policy.json" "$POLICY_FILE"
  fi

  touch "$PLUGIN_DB_FILE"
  refresh_plugin_json
  ensure_service_state
}

require_arg() {
  local value="${1:-}"
  local label="${2:-argument}"
  [[ -n "$value" ]] || die "missing $label"
}

env_get() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 1
  fi
  awk -F= -v target="$key" '$1 == target {sub(/^[^=]*=/, "", $0); print $0}' "$ENV_FILE" | tail -n 1
}

env_set() {
  local key="$1"
  local value="$2"
  if [[ -f "$ENV_FILE" ]] && grep -q "^${key}=" "$ENV_FILE"; then
    awk -v key="$key" -v value="$value" '
      BEGIN { updated = 0 }
      $0 ~ "^" key "=" {
        print key "=" value
        updated = 1
        next
      }
      { print }
      END {
        if (updated == 0) {
          print key "=" value
        }
      }
    ' "$ENV_FILE" >"$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
  fi
}

mask_value() {
  local value="$1"
  if [[ ${#value} -le 4 ]]; then
    printf '****'
  else
    printf '%s****%s' "${value:0:2}" "${value: -2}"
  fi
}

json_get() {
  local file="$1"
  shift
  require_jq
  jq -r "$@" "$file"
}

json_set_inplace() {
  local file="$1"
  shift
  local tmp="${file}.tmp"
  require_jq
  jq "$@" "$file" >"$tmp"
  mv "$tmp" "$file"
}

ensure_service_state() {
  if [[ ! -f "$SERVICE_STATE_FILE" ]]; then
    cat >"$SERVICE_STATE_FILE" <<EOF
{
  "desired": "stopped",
  "lastAction": "bootstrap",
  "updatedAt": "$(iso_now)"
}
EOF
  fi
}

write_service_state() {
  local desired="$1"
  local action="$2"
  local runtime="$3"
  local pid="$4"
  cat >"$SERVICE_STATE_FILE" <<EOF
{
  "desired": "$desired",
  "lastAction": "$action",
  "runtime": "$runtime",
  "pid": "$pid",
  "updatedAt": "$(iso_now)"
}
EOF
}

write_probe_state() {
  local status="$1"
  local message="$2"
  local endpoint="$3"
  cat >"$LAST_PROBE_FILE" <<EOF
{
  "status": "$status",
  "message": "$message",
  "endpoint": "$endpoint",
  "checkedAt": "$(iso_now)"
}
EOF
}

channel_file() {
  printf '%s/%s.json' "$CHANNEL_DIR" "$1"
}

refresh_plugin_json() {
  if command_exists jq; then
    jq -Rn '
      [
        inputs
        | select(length > 0)
        | split("|")
        | {
            package: .[0],
            enabled: (.[1] == "true"),
            version: .[2],
            pinned: (.[3] == "true")
          }
      ]
    ' <"$PLUGIN_DB_FILE" >"$PLUGIN_STATE_FILE"
  else
    {
      printf '[\n'
      local first=1
      while IFS='|' read -r pkg enabled version pinned; do
        [[ -n "${pkg:-}" ]] || continue
        if [[ $first -eq 0 ]]; then
          printf ',\n'
        fi
        first=0
        printf '  {"package":"%s","enabled":"%s","version":"%s","pinned":"%s"}' \
          "$pkg" "$enabled" "$version" "$pinned"
      done <"$PLUGIN_DB_FILE"
      printf '\n]\n'
    } >"$PLUGIN_STATE_FILE"
  fi
}

plugin_upsert() {
  local pkg="$1"
  local enabled="$2"
  local version="$3"
  local pinned="$4"
  awk -F'|' -v pkg="$pkg" -v enabled="$enabled" -v version="$version" -v pinned="$pinned" '
    BEGIN { found = 0 }
    $1 == pkg {
      print pkg "|" enabled "|" version "|" pinned
      found = 1
      next
    }
    { print }
    END {
      if (found == 0) {
        print pkg "|" enabled "|" version "|" pinned
      }
    }
  ' "$PLUGIN_DB_FILE" >"$PLUGIN_DB_FILE.tmp"
  mv "$PLUGIN_DB_FILE.tmp" "$PLUGIN_DB_FILE"
  refresh_plugin_json
}

plugin_get() {
  local pkg="$1"
  awk -F'|' -v pkg="$pkg" '$1 == pkg { print $0 }' "$PLUGIN_DB_FILE" | tail -n 1
}

plugin_remove() {
  local pkg="$1"
  awk -F'|' -v pkg="$pkg" '$1 != pkg { print }' "$PLUGIN_DB_FILE" >"$PLUGIN_DB_FILE.tmp"
  mv "$PLUGIN_DB_FILE.tmp" "$PLUGIN_DB_FILE"
  refresh_plugin_json
}

current_version() {
  if [[ -f "$VERSION_FILE" ]]; then
    tr -d '[:space:]' <"$VERSION_FILE"
  else
    printf '2.0.0-dev'
  fi
}

listener_pid_on_port() {
  local port="$1"
  if command_exists lsof; then
    lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -n 1
  fi
}

pid_is_running() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

record_gateway_pid() {
  local pid="$1"
  printf '%s\n' "$pid" >"$GATEWAY_PID_FILE"
}

read_gateway_pid() {
  if [[ -f "$GATEWAY_PID_FILE" ]]; then
    tr -d '[:space:]' <"$GATEWAY_PID_FILE"
  fi
}

clear_gateway_pid() {
  rm -f "$GATEWAY_PID_FILE"
}

channel_plugin_name() {
  local file="$1"
  json_get "$file" '.plugin // empty'
}

channel_required_keys() {
  local file="$1"
  json_get "$file" '.required[]?'
}

channel_missing_keys() {
  local file="$1"
  local key
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    if [[ "$(json_get "$file" --arg key "$key" '.credentials[$key] // empty')" == "" ]]; then
      printf '%s\n' "$key"
    fi
  done < <(channel_required_keys "$file")
}

policy_allows_plugin() {
  local pkg="$1"
  require_jq
  jq -e --arg pkg "$pkg" '.plugins.allow // [] | index($pkg) != null' "$POLICY_FILE" >/dev/null
}
