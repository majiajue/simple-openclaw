#!/usr/bin/env bash

simple_openclaw_init() {
  ensure_runtime_dirs
  env_set "OPENCLAW_MODEL_BASE_URL" "${OPENCLAW_MODEL_BASE_URL:-https://api.openai.com/v1}"
  env_set "OPENCLAW_MODEL_NAME" "${OPENCLAW_MODEL_NAME:-gpt-4.1}"
  env_set "OPENCLAW_DEFAULT_CHANNEL" "${OPENCLAW_DEFAULT_CHANNEL:-tui}"
  env_set "OPENCLAW_GATEWAY_PORT" "${OPENCLAW_GATEWAY_PORT:-$DEFAULT_GATEWAY_PORT}"
  env_set "OPENCLAW_GATEWAY_CMD" "${OPENCLAW_GATEWAY_CMD:-openclaw gateway}"
  env_set "OPENCLAW_SERVICE_MANAGER" "${OPENCLAW_SERVICE_MANAGER:-$(detect_service_manager)}"

  local openclaw_home="${HOME}/.openclaw"
  local openclaw_config="${openclaw_home}/openclaw.json"
  local openclaw_workspace="${openclaw_home}/workspace"

  mkdir -p "$openclaw_home" "$openclaw_workspace"

  if [[ ! -f "$openclaw_config" ]]; then
    local base_url model_name port
    base_url="$(env_get OPENCLAW_MODEL_BASE_URL || printf 'https://api.openai.com/v1')"
    model_name="$(env_get OPENCLAW_MODEL_NAME || printf 'gpt-4.1')"
    port="$(gateway_port)"

    cat >"$openclaw_config" <<EOCFG
{
  "gateway": {
    "port": ${port},
    "mode": "local"
  },
  "agents": {
    "defaults": {
      "workspace": "${openclaw_workspace}"
    }
  }
}
EOCFG
    info "OpenClaw config created at $openclaw_config"
  else
    info "OpenClaw config already exists at $openclaw_config"
  fi

  info "configuration initialized at $CONFIG_DIR"
  info "next: configure your model with 'simple-openclaw model set' and 'simple-openclaw secret set'"
}
