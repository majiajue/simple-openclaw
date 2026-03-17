#!/usr/bin/env bash

active_profile_name() {
  if [[ -f "$ACTIVE_PROFILE_FILE" ]]; then
    tr -d '[:space:]' <"$ACTIVE_PROFILE_FILE"
  else
    printf 'default'
  fi
}

profile_activate() {
  local name="$1"
  local pdir="$PROFILE_DIR/$name"
  [[ -d "$pdir" ]] || die "profile not found: $name"

  # Remove old symlinks
  for f in env secrets.json policy.json secret_metadata.json; do
    rm -f "$CONFIG_DIR/$f"
    if [[ -f "$pdir/$f" ]]; then
      ln -sf "$pdir/$f" "$CONFIG_DIR/$f"
    fi
  done
  rm -f "$CONFIG_DIR/channels"
  ln -sf "$pdir/channels" "$CONFIG_DIR/channels"

  printf '%s\n' "$name" >"$ACTIVE_PROFILE_FILE"

  # Sync model API key to openclaw env if present
  if [[ -f "$pdir/secrets.json" ]]; then
    local api_key
    api_key="$(json_get "$pdir/secrets.json" '.["model.api_key"] // empty')"
    if [[ -n "$api_key" ]]; then
      sync_openclaw_env_secret "model.api_key" "$api_key"
    fi
  fi

  info "switched to profile: $name"
}

profile_create() {
  local name="$1"
  local pdir="$PROFILE_DIR/$name"
  [[ ! -d "$pdir" ]] || die "profile already exists: $name"

  mkdir -p "$pdir/channels"
  cp "$ROOT_DIR/templates/env.example" "$pdir/env"
  cp "$ROOT_DIR/templates/secrets.example" "$pdir/secrets.json"
  cp "$ROOT_DIR/templates/policy.json" "$pdir/policy.json"
  info "created profile: $name"
}

profile_list() {
  local active
  active="$(active_profile_name)"
  for d in "$PROFILE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local pname
    pname="$(basename "$d")"
    if [[ "$pname" == "$active" ]]; then
      printf '%s *\n' "$pname"
    else
      printf '%s\n' "$pname"
    fi
  done
}

profile_switch() {
  local name="$1"
  local current
  current="$(active_profile_name)"
  if [[ "$name" == "$current" ]]; then
    info "already on profile: $name"
    return 0
  fi
  profile_activate "$name"
}

profile_delete() {
  local name="$1"
  local active
  active="$(active_profile_name)"
  [[ "$name" != "$active" ]] || die "cannot delete active profile: $name (switch first)"
  [[ "$name" != "default" ]] || die "cannot delete the default profile"
  local pdir="$PROFILE_DIR/$name"
  [[ -d "$pdir" ]] || die "profile not found: $name"
  rm -rf "$pdir"
  info "deleted profile: $name"
}

profile_export() {
  local name="$1"
  local pdir="$PROFILE_DIR/$name"
  [[ -d "$pdir" ]] || die "profile not found: $name"
  local ts
  ts="$(timestamp)"
  local outfile="$BACKUP_DIR/profile-${name}-${ts}.tar.gz"
  tar -czf "$outfile" -C "$PROFILE_DIR" "$name"
  info "exported profile to: $outfile"
}

profile_import() {
  local file="$1"
  [[ -f "$file" ]] || die "file not found: $file"
  local imported_name
  imported_name="$(tar -tzf "$file" | head -1 | cut -d/ -f1)"
  [[ -n "$imported_name" ]] || die "cannot detect profile name from archive"
  if [[ -d "$PROFILE_DIR/$imported_name" ]]; then
    die "profile already exists: $imported_name (delete it first)"
  fi
  tar -xzf "$file" -C "$PROFILE_DIR"
  info "imported profile: $imported_name"
}

simple_openclaw_profile() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    create)
      local name="${1:-}"
      require_arg "$name" "profile name"
      profile_create "$name"
      ;;
    list)
      profile_list
      ;;
    switch)
      local name="${1:-}"
      require_arg "$name" "profile name"
      profile_switch "$name"
      ;;
    delete)
      local name="${1:-}"
      require_arg "$name" "profile name"
      profile_delete "$name"
      ;;
    export)
      local name="${1:-}"
      require_arg "$name" "profile name"
      profile_export "$name"
      ;;
    import)
      local file="${1:-}"
      require_arg "$file" "archive file"
      profile_import "$file"
      ;;
    active)
      active_profile_name
      ;;
    *)
      die "unknown profile action: $action"
      ;;
  esac
}
