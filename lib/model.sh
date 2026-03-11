#!/usr/bin/env bash

sync_openclaw_model_config() {
  local openclaw_config="${HOME}/.openclaw/openclaw.json"
  [[ -f "$openclaw_config" ]] || return 0
  require_jq

  local base_url model_name provider api_key api_compat
  base_url="$(env_get OPENCLAW_MODEL_BASE_URL || true)"
  model_name="$(env_get OPENCLAW_MODEL_NAME || true)"
  provider="$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')"
  api_key="$(json_get "$SECRETS_FILE" '.["model.api_key"] // empty' 2>/dev/null || true)"
  api_compat="$(env_get OPENCLAW_MODEL_API_COMPAT || true)"
  [[ -n "$api_compat" ]] || {
    case "$provider" in
      anthropic) api_compat="anthropic-messages" ;;
      *)         api_compat="openai-chat" ;;
    esac
  }

  [[ -n "$model_name" ]] || return 0

  local existing_provider
  existing_provider="$(jq -r '
    .models.providers // {} | to_entries[]
    | select(.value.baseUrl != null)
    | .key' "$openclaw_config" 2>/dev/null | head -1 || true)"

  local prov_id
  if [[ -n "$existing_provider" ]]; then
    prov_id="$existing_provider"
  elif [[ -n "$base_url" ]]; then
    local slug
    slug="$(printf '%s' "$base_url" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s|-\+|-|g;s|^-||;s|-$||')"
    prov_id="custom-${slug}"
  else
    case "$provider" in
      anthropic) prov_id="anthropic" ;;
      openai)    prov_id="openai" ;;
      *)         prov_id="custom" ;;
    esac
  fi

  local model_ref="${prov_id}/${model_name}"
  local tmp="${openclaw_config}.tmp"

  jq --arg model "$model_ref" --arg alias "$model_name" \
     --arg prov "$prov_id" \
     --arg baseUrl "${base_url:-}" \
     --arg apiKey "${api_key:-}" \
     --arg apiCompat "${api_compat}" \
     '
     .agents.defaults.model.primary = $model
     | .agents.defaults.models[$model] = { alias: $alias }
     | if ($baseUrl | length) > 0 then
         .models.providers[$prov].baseUrl = $baseUrl
       else . end
     | if ($apiKey | length) > 0 then
         .models.providers[$prov].apiKey = $apiKey
       else . end
     | .models.providers[$prov].api = $apiCompat
     | .models.providers[$prov].auth = "api-key"
     | .models.providers[$prov].models = [
         {
           id: $alias,
           name: $alias,
           reasoning: true,
           input: ["text", "image"],
           contextWindow: 200000,
           maxTokens: 65536
         }
       ]
     | .auth.profiles[($prov + ":default")] = {
         provider: $prov,
         mode: "api_key"
       }
     ' "$openclaw_config" >"$tmp"
  mv "$tmp" "$openclaw_config"
}

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
      sync_openclaw_model_config
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
