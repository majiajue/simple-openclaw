#!/usr/bin/env bash

split_plugin_spec() {
  local spec="$1"
  local package_name version
  if [[ "$spec" == @*/*@* ]]; then
    package_name="${spec%@*}"
    version="${spec##*@}"
  elif [[ "$spec" == *"@"* && "$spec" != @* ]]; then
    package_name="${spec%@*}"
    version="${spec##*@}"
  else
    package_name="$spec"
    version=""
  fi
  printf '%s|%s\n' "$package_name" "$version"
}

simple_openclaw_plugin() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    list)
      if [[ ! -s "$PLUGIN_DB_FILE" ]]; then
        info "no plugins recorded"
        return 0
      fi
      jq -r '.[] | "\(.package) enabled=\(.enabled) version=\(.version) pinned=\(.pinned)"' "$PLUGIN_STATE_FILE"
      ;;
    install)
      local pkg="${1:-}" pin_flag="" openclaw_path package_name version
      require_arg "$pkg" "plugin package"
      shift || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --pin)
            pin_flag="--pin"
            shift
            ;;
          --dry-run)
            SIMPLE_OPENCLAW_DRY_RUN=1
            shift
            ;;
          *)
            die "unknown plugin install option: $1"
            ;;
        esac
      done
      openclaw_path="$(openclaw_bin)"
      [[ -n "$openclaw_path" ]] || die "OpenClaw binary not found; run simple-openclaw install first or set OPENCLAW_BIN"
      if [[ -n "$pin_flag" ]]; then
        run_cmd "$openclaw_path" plugins install "$pkg" --pin
      else
        run_cmd "$openclaw_path" plugins install "$pkg"
      fi
      IFS='|' read -r package_name version <<<"$(split_plugin_spec "$pkg")"
      if [[ -n "$version" ]]; then
        plugin_upsert "$package_name" "false" "$version" "true"
      else
        plugin_upsert "$pkg" "false" "latest" "$([[ -n "$pin_flag" ]] && printf true || printf false)"
      fi
      info "plugin installed: $pkg"
      ;;
    enable)
      local pkg_enable="${1:-}"
      require_arg "$pkg_enable" "plugin package"
      local record_enable
      record_enable="$(plugin_get "$pkg_enable")"
      [[ -n "$record_enable" ]] || die "plugin not found: $pkg_enable"
      IFS='|' read -r _ _ version_enable pinned_enable <<<"$record_enable"
      plugin_upsert "$pkg_enable" "true" "$version_enable" "$pinned_enable"
      info "plugin enabled: $pkg_enable"
      ;;
    disable)
      local pkg_disable="${1:-}"
      require_arg "$pkg_disable" "plugin package"
      local record_disable
      record_disable="$(plugin_get "$pkg_disable")"
      [[ -n "$record_disable" ]] || die "plugin not found: $pkg_disable"
      IFS='|' read -r _ _ version_disable pinned_disable <<<"$record_disable"
      plugin_upsert "$pkg_disable" "false" "$version_disable" "$pinned_disable"
      info "plugin disabled: $pkg_disable"
      ;;
    pin)
      local spec="${1:-}"
      require_arg "$spec" "plugin@version"
      local pkg="${spec%@*}"
      local version="${spec##*@}"
      [[ "$pkg" != "$version" ]] || die "pin expects plugin@version"
      local current
      current="$(plugin_get "$pkg")"
      if [[ -n "$current" ]]; then
        IFS='|' read -r _ enabled_current _ _ <<<"$current"
      else
        enabled_current="false"
      fi
      plugin_upsert "$pkg" "$enabled_current" "$version" "true"
      info "plugin pinned: $pkg@$version"
      ;;
    audit)
      local package_status
      while IFS='|' read -r pkg enabled version pinned; do
        [[ -n "${pkg:-}" ]] || continue
        if ! policy_allows_plugin "$pkg"; then
          printf 'audit=warn plugin=%s reason=not_in_allowlist\n' "$pkg"
        elif [[ "$pinned" != "true" && "$(jq -r '.plugins.pinVersions // false' "$POLICY_FILE")" == "true" ]]; then
          printf 'audit=warn plugin=%s reason=not_pinned\n' "$pkg"
        else
          printf 'audit=ok plugin=%s enabled=%s version=%s pinned=%s\n' "$pkg" "$enabled" "$version" "$pinned"
        fi
      done <"$PLUGIN_DB_FILE"
      ;;
    doctor)
      local seen=" " enabled_count=0 duplicate_count=0
      while IFS='|' read -r pkg enabled version pinned; do
        [[ -n "${pkg:-}" ]] || continue
        if [[ "$seen" == *" $pkg "* ]]; then
          printf 'doctor=warn plugin=%s reason=duplicate_record\n' "$pkg"
          duplicate_count=$((duplicate_count + 1))
        fi
        seen="${seen}${pkg} "
        [[ -n "$version" ]] || printf 'doctor=warn plugin=%s reason=missing_version\n' "$pkg"
        [[ "$enabled" == "true" || "$enabled" == "false" ]] || printf 'doctor=warn plugin=%s reason=invalid_enabled_state\n' "$pkg"
        [[ "$enabled" == "true" ]] && enabled_count=$((enabled_count + 1))
      done <"$PLUGIN_DB_FILE"
      printf 'doctor=summary enabled=%s duplicates=%s\n' "$enabled_count" "$duplicate_count"
      ;;
    *)
      die "unknown plugin action: $action"
      ;;
  esac
}
