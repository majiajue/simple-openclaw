#!/usr/bin/env bash

simple_openclaw_model() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    set)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --base-url)
            env_set "OPENCLAW_MODEL_BASE_URL" "$2"
            shift 2
            ;;
          --api-key)
            "$ROOT_DIR/bin/simple-openclaw" secret set model.api_key "$2" >/dev/null
            shift 2
            ;;
          --model)
            env_set "OPENCLAW_MODEL_NAME" "$2"
            shift 2
            ;;
          --provider)
            env_set "OPENCLAW_MODEL_PROVIDER" "$2"
            shift 2
            ;;
          *)
            die "unknown model option: $1"
            ;;
        esac
      done
      info "model configuration updated"
      ;;
    list)
      printf 'provider=%s\n' "$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')"
      printf 'base_url=%s\n' "$(env_get OPENCLAW_MODEL_BASE_URL || true)"
      printf 'model=%s\n' "$(env_get OPENCLAW_MODEL_NAME || true)"
      ;;
    test)
      local base_url model_name
      base_url="$(env_get OPENCLAW_MODEL_BASE_URL || true)"
      model_name="$(env_get OPENCLAW_MODEL_NAME || true)"
      [[ -n "$base_url" ]] || die "OPENCLAW_MODEL_BASE_URL is not configured"
      [[ -n "$model_name" ]] || die "OPENCLAW_MODEL_NAME is not configured"
      printf 'model_test=ok provider=%s url=%s model=%s\n' \
        "$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')" "$base_url" "$model_name"
      ;;
    *)
      die "unknown model action: $action"
      ;;
  esac
}
