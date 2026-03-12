#!/usr/bin/env bash

PLUGIN_SCAN_RISK_COUNT=0
PLUGIN_SCAN_WARN_COUNT=0

pscan_risk() {
  PLUGIN_SCAN_RISK_COUNT=$((PLUGIN_SCAN_RISK_COUNT + 1))
  printf 'scan=RISK plugin=%s scope=%s detail=%s\n' "$1" "$2" "$3"
}

pscan_warn() {
  PLUGIN_SCAN_WARN_COUNT=$((PLUGIN_SCAN_WARN_COUNT + 1))
  printf 'scan=warn plugin=%s scope=%s detail=%s\n' "$1" "$2" "$3"
}

pscan_ok() {
  printf 'scan=ok plugin=%s scope=%s\n' "$1" "$2"
}

resolve_plugin_dir() {
  local pkg="$1"
  local pm pkg_dir
  pm="$(package_manager)"
  if [[ "$pm" == "npm" ]]; then
    pkg_dir="$(npm root -g 2>/dev/null)/${pkg}" || true
  elif [[ "$pm" == "pnpm" ]]; then
    pkg_dir="$(pnpm root -g 2>/dev/null)/${pkg}" || true
  fi
  if [[ -n "$pkg_dir" && -d "$pkg_dir" ]]; then
    printf '%s' "$pkg_dir"
  fi
}

scan_plugin_package_json() {
  local pkg="$1" pkg_dir="$2"
  local pkg_json="${pkg_dir}/package.json"

  if [[ ! -f "$pkg_json" ]]; then
    pscan_warn "$pkg" "package_json" "not_found"
    return
  fi

  if ! jq empty "$pkg_json" >/dev/null 2>&1; then
    pscan_risk "$pkg" "package_json" "invalid_json"
    return
  fi

  # Check install scripts for dangerous commands
  local scripts_to_check=("preinstall" "postinstall" "preuninstall" "postuninstall" "prepare" "prepublish")
  for hook in "${scripts_to_check[@]}"; do
    local script_val
    script_val="$(jq -r ".scripts.${hook} // empty" "$pkg_json" 2>/dev/null || true)"
    if [[ -n "$script_val" ]]; then
      # Dangerous patterns in install hooks
      case "$script_val" in
        *curl*|*wget*|*http:*|*https:*)
          pscan_risk "$pkg" "install_hook" "${hook}_downloads_from_network"
          ;;
        *eval*|*">/dev/"*|*rm\ -rf*|*chmod\ 777*)
          pscan_risk "$pkg" "install_hook" "${hook}_suspicious_command"
          ;;
        *node\ -e*|*python\ -c*|*bash\ -c*)
          pscan_warn "$pkg" "install_hook" "${hook}_inline_code_execution"
          ;;
        *node-gyp*|*cmake*|*make*)
          pscan_ok "$pkg" "install_hook_${hook}(native_build)"
          ;;
        *)
          pscan_warn "$pkg" "install_hook" "${hook}_present=${script_val}"
          ;;
      esac
    fi
  done

  # Check for known typosquatting patterns
  local name
  name="$(jq -r '.name // empty' "$pkg_json" 2>/dev/null || true)"
  if [[ -n "$name" && "$name" != "$pkg" ]]; then
    pscan_risk "$pkg" "identity" "package_name_mismatch(json=${name},expected=${pkg})"
  fi

  # Check dependency count
  local dep_count
  dep_count="$(jq '[(.dependencies // {} | length), (.optionalDependencies // {} | length)] | add' "$pkg_json" 2>/dev/null || printf '0')"
  if [[ "$dep_count" -gt 50 ]]; then
    pscan_warn "$pkg" "dependencies" "high_count(${dep_count})"
  else
    pscan_ok "$pkg" "dependency_count(${dep_count})"
  fi

  # Check for suspicious dependency names (common typosquat targets)
  local suspicious_deps
  suspicious_deps="$(jq -r '
    [(.dependencies // {}), (.devDependencies // {})] | add // {} | keys[]
  ' "$pkg_json" 2>/dev/null || true)"
  for dep in $suspicious_deps; do
    case "$dep" in
      *-js-|*lodash[0-9]*|*requets*|*requierjs*|*crossenv*|*cross-env.js*|*babelcli*|*gruntcli*|*mongose*)
        pscan_risk "$pkg" "typosquat_dep" "$dep"
        ;;
    esac
  done

  pscan_ok "$pkg" "package_json_checked"
}

scan_plugin_source() {
  local pkg="$1" pkg_dir="$2"

  local js_files
  js_files="$(find "$pkg_dir" -maxdepth 4 -name '*.js' -not -path "${pkg_dir}/node_modules/*" -not -path '*/.git/*' 2>/dev/null | head -200)"

  if [[ -z "$js_files" ]]; then
    pscan_ok "$pkg" "source_scan(no_js_files)"
    return
  fi

  local found_eval=0 found_exec=0 found_net=0 found_fs_danger=0 found_crypto_mine=0 found_env_access=0 found_obfuscation=0

  while IFS= read -r jsfile; do
    [[ -f "$jsfile" ]] || continue
    local relpath="${jsfile#"$pkg_dir"/}"

    # eval / Function constructor
    if grep -qE '\beval\s*\(|new\s+Function\s*\(' "$jsfile" 2>/dev/null; then
      if [[ "$found_eval" -eq 0 ]]; then
        pscan_risk "$pkg" "eval_usage" "$relpath"
        found_eval=1
      fi
    fi

    # child_process / exec / spawn
    if grep -qE "require\s*\(\s*['\"]child_process['\"]|child_process|\.exec\s*\(|\.execSync\s*\(|\.spawn\s*\(" "$jsfile" 2>/dev/null; then
      if [[ "$found_exec" -eq 0 ]]; then
        pscan_warn "$pkg" "child_process" "$relpath"
        found_exec=1
      fi
    fi

    # Outbound network calls to hardcoded IPs/URLs (not standard APIs)
    if grep -qE 'https?://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|\.request\s*\(\s*["\x27]https?://(?!api\.(openai|anthropic|github))' "$jsfile" 2>/dev/null; then
      if [[ "$found_net" -eq 0 ]]; then
        pscan_warn "$pkg" "hardcoded_network" "$relpath"
        found_net=1
      fi
    fi

    # Dangerous filesystem writes to system paths
    if grep -qE "writeFileSync\s*\(\s*['\"]/(usr|etc|bin|tmp)" "$jsfile" 2>/dev/null; then
      if [[ "$found_fs_danger" -eq 0 ]]; then
        pscan_risk "$pkg" "system_path_write" "$relpath"
        found_fs_danger=1
      fi
    fi

    # Crypto mining indicators
    if grep -qiE 'stratum\+tcp|coinhive|cryptonight|monero|xmrig|hashrate|mining.?pool' "$jsfile" 2>/dev/null; then
      if [[ "$found_crypto_mine" -eq 0 ]]; then
        pscan_risk "$pkg" "crypto_mining" "$relpath"
        found_crypto_mine=1
      fi
    fi

    # Accessing environment variables for exfiltration patterns
    if grep -qE 'process\.env\b' "$jsfile" 2>/dev/null; then
      if grep -qE 'Object\.keys\s*\(\s*process\.env|JSON\.stringify\s*\(\s*process\.env|\.send\(.*process\.env|\.post\(.*process\.env' "$jsfile" 2>/dev/null; then
        if [[ "$found_env_access" -eq 0 ]]; then
          pscan_risk "$pkg" "env_exfiltration" "$relpath"
          found_env_access=1
        fi
      fi
    fi

    # Obfuscation indicators
    if grep -qE '\\x[0-9a-f]{2}\\x[0-9a-f]{2}\\x[0-9a-f]{2}|\\u[0-9a-f]{4}\\u[0-9a-f]{4}\\u[0-9a-f]{4}|atob\s*\(|Buffer\.from\s*\([^)]+,\s*["\x27]base64' "$jsfile" 2>/dev/null; then
      if [[ "$found_obfuscation" -eq 0 ]]; then
        pscan_warn "$pkg" "obfuscated_code" "$relpath"
        found_obfuscation=1
      fi
    fi

  done <<< "$js_files"

  local risk_total=$((found_eval + found_exec + found_net + found_fs_danger + found_crypto_mine + found_env_access + found_obfuscation))
  if [[ "$risk_total" -eq 0 ]]; then
    pscan_ok "$pkg" "source_scan_clean"
  fi
}

scan_plugin_permissions() {
  local pkg="$1" pkg_dir="$2"

  # Check for native binaries / .so / .dylib / .node
  local native_count
  native_count="$(find "$pkg_dir" -maxdepth 5 \( -name '*.node' -o -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) -not -path "${pkg_dir}/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$native_count" -gt 0 ]]; then
    pscan_warn "$pkg" "native_modules" "count=${native_count}"
  else
    pscan_ok "$pkg" "no_native_modules"
  fi

  # Check for executable files in unexpected places
  local exec_count
  exec_count="$(find "$pkg_dir" -maxdepth 4 -type f -perm +111 -not -name '*.js' -not -name '*.sh' -not -path "${pkg_dir}/node_modules/*" -not -path '*/.git/*' -not -path '*/bin/*' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$exec_count" -gt 5 ]]; then
    pscan_warn "$pkg" "executable_files" "count=${exec_count}"
  fi

  # Check for setuid/setgid files
  local suid_count
  suid_count="$(find "$pkg_dir" -maxdepth 5 \( -perm -4000 -o -perm -2000 \) 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$suid_count" -gt 0 ]]; then
    pscan_risk "$pkg" "setuid_files" "count=${suid_count}"
  fi
}

scan_single_plugin() {
  local pkg="$1"
  local pkg_dir

  PLUGIN_SCAN_RISK_COUNT=0
  PLUGIN_SCAN_WARN_COUNT=0

  pkg_dir="$(resolve_plugin_dir "$pkg")"
  if [[ -z "$pkg_dir" ]]; then
    printf 'scan=skip plugin=%s reason=package_directory_not_found\n' "$pkg"
    return 1
  fi

  printf '%s\n' "=== Plugin Security Scan: $pkg ==="
  printf 'directory=%s\n\n' "$pkg_dir"

  printf '%s\n' "--- Package Metadata ---"
  scan_plugin_package_json "$pkg" "$pkg_dir"
  printf '\n'

  printf '%s\n' "--- Source Code Analysis ---"
  scan_plugin_source "$pkg" "$pkg_dir"
  printf '\n'

  printf '%s\n' "--- Permissions & Binaries ---"
  scan_plugin_permissions "$pkg" "$pkg_dir"
  printf '\n'

  printf '%s\n' "=== Scan Summary ==="
  printf 'plugin=%s risks=%d warnings=%d\n' "$pkg" "$PLUGIN_SCAN_RISK_COUNT" "$PLUGIN_SCAN_WARN_COUNT"
  if [[ "$PLUGIN_SCAN_RISK_COUNT" -gt 0 ]]; then
    printf 'verdict=DANGEROUS\n'
  elif [[ "$PLUGIN_SCAN_WARN_COUNT" -gt 0 ]]; then
    printf 'verdict=REVIEW_RECOMMENDED\n'
  else
    printf 'verdict=CLEAN\n'
  fi
}

scan_all_plugins() {
  if [[ ! -s "$PLUGIN_DB_FILE" ]]; then
    info "no plugins recorded"
    return 0
  fi

  local total_risk=0 total_warn=0 scanned=0 skipped=0

  while IFS='|' read -r pkg enabled version pinned; do
    [[ -n "${pkg:-}" ]] || continue
    PLUGIN_SCAN_RISK_COUNT=0
    PLUGIN_SCAN_WARN_COUNT=0

    local pkg_dir
    pkg_dir="$(resolve_plugin_dir "$pkg")"
    if [[ -z "$pkg_dir" ]]; then
      printf 'scan=skip plugin=%s reason=not_installed_locally\n' "$pkg"
      skipped=$((skipped + 1))
      continue
    fi

    printf '\n%s\n' "=== Scanning: $pkg ==="
    scan_plugin_package_json "$pkg" "$pkg_dir"
    scan_plugin_source "$pkg" "$pkg_dir"
    scan_plugin_permissions "$pkg" "$pkg_dir"

    total_risk=$((total_risk + PLUGIN_SCAN_RISK_COUNT))
    total_warn=$((total_warn + PLUGIN_SCAN_WARN_COUNT))
    scanned=$((scanned + 1))

    if [[ "$PLUGIN_SCAN_RISK_COUNT" -gt 0 ]]; then
      printf 'plugin_verdict=%s status=DANGEROUS risks=%d warnings=%d\n' "$pkg" "$PLUGIN_SCAN_RISK_COUNT" "$PLUGIN_SCAN_WARN_COUNT"
    elif [[ "$PLUGIN_SCAN_WARN_COUNT" -gt 0 ]]; then
      printf 'plugin_verdict=%s status=REVIEW risks=%d warnings=%d\n' "$pkg" "$PLUGIN_SCAN_RISK_COUNT" "$PLUGIN_SCAN_WARN_COUNT"
    else
      printf 'plugin_verdict=%s status=CLEAN\n' "$pkg"
    fi
  done <"$PLUGIN_DB_FILE"

  printf '\n%s\n' "=== All Plugins Summary ==="
  printf 'scanned=%d skipped=%d total_risks=%d total_warnings=%d\n' "$scanned" "$skipped" "$total_risk" "$total_warn"
  if [[ "$total_risk" -gt 0 ]]; then
    printf 'overall=DANGEROUS\n'
  elif [[ "$total_warn" -gt 0 ]]; then
    printf 'overall=REVIEW_RECOMMENDED\n'
  else
    printf 'overall=CLEAN\n'
  fi
}

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
    scan)
      local scan_target="${1:-all}"
      if [[ "$scan_target" == "all" ]]; then
        scan_all_plugins
      else
        scan_single_plugin "$scan_target"
      fi
      ;;
    *)
      die "unknown plugin action: $action"
      ;;
  esac
}
