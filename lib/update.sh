#!/usr/bin/env bash

stable_version() {
  printf '2026.3.8'
}

write_release_lock() {
  local target="$1"
  cat >"$RELEASE_LOCK_FILE" <<EOF
{
  "track": "stable",
  "target": "$target",
  "updatedAt": "$(iso_now)"
}
EOF
}

simple_openclaw_update() {
  local arg="${1:-}"
  local dry_run=0 target="" channel="" pm pkg openclaw_path version_spec=""
  pm="$(package_manager)"
  pkg="$(openclaw_npm_package)"
  openclaw_path="$(openclaw_bin)"

  case "$arg" in
    --check)
      printf 'current=%s stable=%s\n' "$(current_version)" "$(stable_version)"
      ;;
    --target)
      target="${2:-}"
      require_arg "$target" "target version"
      "$ROOT_DIR/bin/simple-openclaw" backup create >/dev/null
      write_release_lock "$target"
      if [[ -n "$openclaw_path" ]]; then
        run_cmd "$openclaw_path" update --tag "$target"
      else
        ensure_supported_package_manager "$pm"
        run_cmd bash -lc "$(npm_global_install_cmd "$pm" "${pkg}@${target}")"
      fi
      "$ROOT_DIR/bin/simple-openclaw" doctor >/dev/null || true
      "$ROOT_DIR/bin/simple-openclaw" probe >/dev/null || true
      printf 'update=ok target=%s\n' "$target"
      ;;
    "" )
      "$ROOT_DIR/bin/simple-openclaw" backup create >/dev/null
      channel="$(update_channel)"
      write_release_lock "$channel"
      if [[ -n "$openclaw_path" ]]; then
        run_cmd "$openclaw_path" update --channel "$channel"
      else
        ensure_supported_package_manager "$pm"
        version_spec="$(channel_to_dist_tag "$channel")"
        run_cmd bash -lc "$(npm_global_install_cmd "$pm" "${pkg}@${version_spec}")"
      fi
      "$ROOT_DIR/bin/simple-openclaw" doctor >/dev/null || true
      "$ROOT_DIR/bin/simple-openclaw" probe >/dev/null || true
      printf 'update=ok channel=%s\n' "$channel"
      ;;
    release)
      local sub="${2:-list}"
      case "$sub" in
        list)
          printf 'stable %s\n' "$(stable_version)"
          printf 'current %s\n' "$(current_version)"
          ;;
        stable)
          printf '%s\n' "$(stable_version)"
          ;;
        *)
          die "unknown release action: $sub"
          ;;
      esac
      ;;
    --channel)
      channel="${2:-}"
      require_arg "$channel" "channel"
      channel="$(channel_to_dist_tag "$channel")"
      "$ROOT_DIR/bin/simple-openclaw" backup create >/dev/null
      write_release_lock "$channel"
      if [[ -n "$openclaw_path" ]]; then
        run_cmd "$openclaw_path" update --channel "$channel"
      else
        ensure_supported_package_manager "$pm"
        run_cmd bash -lc "$(npm_global_install_cmd "$pm" "${pkg}@${channel}")"
      fi
      env_set "OPENCLAW_UPDATE_CHANNEL" "$channel"
      "$ROOT_DIR/bin/simple-openclaw" doctor >/dev/null || true
      "$ROOT_DIR/bin/simple-openclaw" probe >/dev/null || true
      printf 'update=ok channel=%s\n' "$channel"
      ;;
    --dry-run)
      SIMPLE_OPENCLAW_DRY_RUN=1 simple_openclaw_update
      ;;
    *)
      die "unknown update option: $arg"
      ;;
  esac
}
