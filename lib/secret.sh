#!/usr/bin/env bash

set_secret_value() {
  local key="$1"
  local value="$2"
  json_set_inplace "$SECRETS_FILE" --arg key "$key" --arg value "$value" '.[$key] = $value'
}

sync_openclaw_env_secret() {
  local key="$1"
  local value="$2"
  local openclaw_env="${HOME}/.openclaw/.env"

  if [[ "$key" == "model.api_key" ]]; then
    local provider
    provider="$(env_get OPENCLAW_MODEL_PROVIDER || printf 'openai-compatible')"

    mkdir -p "${HOME}/.openclaw"

    local env_key
    case "$provider" in
      anthropic) env_key="ANTHROPIC_API_KEY" ;;
      openai)    env_key="OPENAI_API_KEY" ;;
      *)         env_key="OPENAI_API_KEY" ;;
    esac

    if [[ -f "$openclaw_env" ]] && grep -q "^${env_key}=" "$openclaw_env"; then
      sed -i.bak "s|^${env_key}=.*|${env_key}=${value}|" "$openclaw_env"
      rm -f "${openclaw_env}.bak"
    else
      printf '%s=%s\n' "$env_key" "$value" >>"$openclaw_env"
    fi
    chmod 600 "$openclaw_env"
  fi
}

# ── Secret metadata ──

ensure_secret_meta() {
  if [[ ! -f "$SECRET_META_FILE" ]]; then
    local now
    now="$(iso_now)"
    # Seed metadata from existing secrets
    if [[ -f "$SECRETS_FILE" ]]; then
      jq --arg ts "$now" '[to_entries[] | {(.key): {created_at: $ts, rotated_at: $ts}}] | add // {}' \
        "$SECRETS_FILE" >"$SECRET_META_FILE"
    else
      printf '{}\n' >"$SECRET_META_FILE"
    fi
  fi
}

update_secret_meta() {
  local key="$1"
  local field="$2"  # created_at or rotated_at
  local now
  now="$(iso_now)"
  ensure_secret_meta
  json_set_inplace "$SECRET_META_FILE" --arg key "$key" --arg field "$field" --arg ts "$now" \
    '.[$key][$field] = $ts'
}

append_rotation_history() {
  local key="$1"
  local old_hash="$2"
  local new_hash="$3"
  local now
  now="$(iso_now)"
  local actor="${USER:-unknown}"

  if [[ ! -f "$SECRET_HISTORY_FILE" ]]; then
    printf '[]\n' >"$SECRET_HISTORY_FILE"
  fi

  local tmp="${SECRET_HISTORY_FILE}.tmp"
  jq --arg k "$key" --arg ts "$now" --arg oh "$old_hash" --arg nh "$new_hash" --arg a "$actor" \
    '. + [{key: $k, timestamp: $ts, old_hash: $oh, new_hash: $nh, actor: $a}]' \
    "$SECRET_HISTORY_FILE" >"$tmp" && mv "$tmp" "$SECRET_HISTORY_FILE"
}

hash_value() {
  printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1 | head -c 12
}

# ── Secret rotation ──

secret_rotate_key() {
  local key="$1"
  ensure_secret_meta

  # Verify key exists
  local old_value
  old_value="$(json_get "$SECRETS_FILE" --arg k "$key" '.[$k] // empty')"
  [[ -n "$old_value" ]] || die "secret key not found: $key"

  local old_hash
  old_hash="$(hash_value "$old_value")"

  # Prompt for new value
  printf 'Enter new value for %s: ' "$key" >&2
  local new_value
  read -rs new_value
  printf '\n' >&2
  [[ -n "$new_value" ]] || die "empty value, rotation cancelled"

  # Confirm
  printf 'Confirm new value for %s: ' "$key" >&2
  local confirm_value
  read -rs confirm_value
  printf '\n' >&2
  [[ "$new_value" == "$confirm_value" ]] || die "values do not match, rotation cancelled"

  local new_hash
  new_hash="$(hash_value "$new_value")"

  # Update secret
  set_secret_value "$key" "$new_value"
  sync_openclaw_env_secret "$key" "$new_value"

  if [[ "$key" == "model.api_key" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/lib/model.sh"
    sync_openclaw_model_config
  fi

  # Update metadata and history
  update_secret_meta "$key" "rotated_at"
  append_rotation_history "$key" "$old_hash" "$new_hash"

  info "rotated secret: $key (hash: ${old_hash} -> ${new_hash})"
}

# ── Secret audit ──

secret_audit_enhanced() {
  ensure_secret_meta
  local max_age_days
  max_age_days="$(env_get OPENCLAW_SECRET_MAX_AGE_DAYS 2>/dev/null || printf '90')"

  local now_epoch
  now_epoch="$(date +%s)"

  printf '%-25s %-10s %-20s %s\n' "KEY" "AGE(days)" "LAST_ROTATED" "STATUS"
  printf '%-25s %-10s %-20s %s\n' "---" "---" "---" "---"

  jq -r 'to_entries[] | [.key, .value] | @tsv' "$SECRETS_FILE" | while IFS=$'\t' read -r key _value; do
    local rotated_at age_days status
    rotated_at="$(json_get "$SECRET_META_FILE" --arg k "$key" '.[$k].rotated_at // empty')"

    if [[ -z "$rotated_at" ]]; then
      age_days="?"
      status="no_metadata"
    else
      local rotated_epoch
      rotated_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$rotated_at" '+%s' 2>/dev/null || date -d "$rotated_at" '+%s' 2>/dev/null || printf '0')"
      if [[ "$rotated_epoch" -gt 0 ]]; then
        age_days="$(( (now_epoch - rotated_epoch) / 86400 ))"
        if [[ "$age_days" -ge "$max_age_days" ]]; then
          status="STALE"
        else
          status="ok"
        fi
      else
        age_days="?"
        status="parse_error"
      fi
    fi

    printf '%-25s %-10s %-20s %s\n' "$key" "$age_days" "${rotated_at:-never}" "$status"
  done
}

secret_rotate_expired() {
  ensure_secret_meta
  local max_age_days
  max_age_days="$(env_get OPENCLAW_SECRET_MAX_AGE_DAYS 2>/dev/null || printf '90')"
  local now_epoch
  now_epoch="$(date +%s)"
  local found=0

  jq -r 'to_entries[] | .key' "$SECRETS_FILE" | while read -r key; do
    local rotated_at
    rotated_at="$(json_get "$SECRET_META_FILE" --arg k "$key" '.[$k].rotated_at // empty')"
    [[ -n "$rotated_at" ]] || continue

    local rotated_epoch
    rotated_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$rotated_at" '+%s' 2>/dev/null || date -d "$rotated_at" '+%s' 2>/dev/null || printf '0')"
    [[ "$rotated_epoch" -gt 0 ]] || continue

    local age_days=$(( (now_epoch - rotated_epoch) / 86400 ))
    if [[ "$age_days" -ge "$max_age_days" ]]; then
      info "secret '$key' is ${age_days} days old (max: ${max_age_days})"
      secret_rotate_key "$key"
      found=1
    fi
  done

  [[ "$found" -eq 1 ]] || info "no expired secrets found"
}

secret_history() {
  if [[ ! -f "$SECRET_HISTORY_FILE" ]] || [[ "$(jq 'length' "$SECRET_HISTORY_FILE")" == "0" ]]; then
    info "no rotation history"
    return 0
  fi

  printf '%-20s %-25s %-14s %-14s %s\n' "TIMESTAMP" "KEY" "OLD_HASH" "NEW_HASH" "ACTOR"
  printf '%-20s %-25s %-14s %-14s %s\n' "---" "---" "---" "---" "---"

  jq -r '.[] | [.timestamp, .key, .old_hash, .new_hash, .actor] | @tsv' "$SECRET_HISTORY_FILE" | \
    while IFS=$'\t' read -r ts key oh nh actor; do
      printf '%-20s %-25s %-14s %-14s %s\n' "$ts" "$key" "$oh" "$nh" "$actor"
    done
}

# ── Dispatch ──

simple_openclaw_secret() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    set)
      local key="${1:-}"
      local value="${2:-}"
      require_arg "$key" "secret key"
      require_arg "$value" "secret value"
      set_secret_value "$key" "$value"
      sync_openclaw_env_secret "$key" "$value"
      if [[ "$key" == "model.api_key" ]]; then
        # shellcheck source=/dev/null
        source "$ROOT_DIR/lib/model.sh"
        sync_openclaw_model_config
      fi
      ensure_secret_meta
      update_secret_meta "$key" "created_at"
      update_secret_meta "$key" "rotated_at"
      info "secret updated: $key"
      ;;
    list)
      jq -r 'to_entries[] | [.key, .value] | @tsv' "$SECRETS_FILE" | while IFS=$'\t' read -r key value; do
        printf '%s=%s\n' "$key" "$(mask_value "$value")"
      done
      ;;
    rotate)
      local rotate_key="${1:-}"
      require_arg "$rotate_key" "secret key"
      secret_rotate_key "$rotate_key"
      ;;
    audit)
      secret_audit_enhanced
      ;;
    history)
      secret_history
      ;;
    rotate-expired)
      secret_rotate_expired
      ;;
    *)
      die "unknown secret action: $action"
      ;;
  esac
}
