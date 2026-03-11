#!/usr/bin/env bash

simple_openclaw_init() {
  ensure_runtime_dirs
  env_set "OPENCLAW_MODEL_BASE_URL" "${OPENCLAW_MODEL_BASE_URL:-https://api.openai.com/v1}"
  env_set "OPENCLAW_MODEL_NAME" "${OPENCLAW_MODEL_NAME:-gpt-4.1}"
  env_set "OPENCLAW_DEFAULT_CHANNEL" "${OPENCLAW_DEFAULT_CHANNEL:-tui}"
  env_set "OPENCLAW_GATEWAY_PORT" "${OPENCLAW_GATEWAY_PORT:-$DEFAULT_GATEWAY_PORT}"
  env_set "OPENCLAW_GATEWAY_CMD" "${OPENCLAW_GATEWAY_CMD:-openclaw gateway}"
  env_set "OPENCLAW_SERVICE_MANAGER" "${OPENCLAW_SERVICE_MANAGER:-$(detect_service_manager)}"
  info "configuration initialized at $CONFIG_DIR"
  info "edit $ENV_FILE and $SECRETS_FILE to finish onboarding"
}
