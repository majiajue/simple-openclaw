#!/usr/bin/env bash

set -euo pipefail

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

  tarball="node-${node_ver}-${os}-${arch}.tar.xz"
  url="https://nodejs.org/dist/${node_ver}/${tarball}"
  tmp_dir="$(mktemp -d)"

  info "downloading Node.js ${node_ver} for ${os}-${arch}..."
  if command_exists curl; then
    curl -fsSL "$url" -o "${tmp_dir}/${tarball}" || die "failed to download Node.js from $url"
  elif command_exists wget; then
    wget -q "$url" -O "${tmp_dir}/${tarball}" || die "failed to download Node.js from $url"
  else
    die "curl or wget is required to auto-install Node.js"
  fi

  local install_prefix="/usr/local"
  info "extracting Node.js to ${install_prefix}..."
  tar -xJf "${tmp_dir}/${tarball}" -C "$tmp_dir"
  local extracted_dir="${tmp_dir}/node-${node_ver}-${os}-${arch}"

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
    die "Node.js auto-install failed; binary is not functional after extraction"
  fi
  info "Node.js ${installed} installed successfully"
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
  env_get OPENCLAW_GATEWAY_PORT || printf '%s' "$DEFAULT_GATEWAY_PORT"
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
  env_get OPENCLAW_NPM_PACKAGE || printf '%s' "$DEFAULT_OPENCLAW_NPM_PACKAGE"
}

update_channel() {
  env_get OPENCLAW_UPDATE_CHANNEL || printf 'stable'
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
