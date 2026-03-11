#!/usr/bin/env bash

simple_openclaw_install() {
  local action="${1:-install}"
  shift || true

  case "$action" in
    install)
      local os node_major manager openclaw_path pm pkg target version_or_tag dry_run=0 install_cmd
      version_or_tag="latest"
      os="$(detect_os)"
      node_major="$(node_major_version)"
      manager="$(detect_service_manager)"
      openclaw_path="$(openclaw_bin)"
      pm="$(package_manager)"
      pkg="$(openclaw_npm_package)"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --version|--tag)
            version_or_tag="${2:-}"
            require_arg "$version_or_tag" "version or tag"
            shift 2
            ;;
          --channel)
            target="${2:-}"
            require_arg "$target" "channel"
            version_or_tag="$(channel_to_dist_tag "$target")"
            shift 2
            ;;
          --dry-run)
            dry_run=1
            shift
            ;;
          *)
            die "unknown install option: $1"
            ;;
        esac
      done

      info "initializing runtime directories under $SIMPLE_OPENCLAW_HOME"
      ensure_runtime_dirs
      info "detected operating system: $os"
      local need_node=0
      if command_exists node; then
        local node_ver
        node_ver="$(node_version)"
        if [[ -z "$node_ver" ]]; then
          warn "Node.js binary found but is not functional; will auto-install"
          need_node=1
        elif [[ "$node_major" -lt 22 ]]; then
          warn "Node.js 22+ is required, found v${node_ver}; will auto-install"
          need_node=1
        else
          info "detected Node.js v${node_ver}"
        fi
      else
        warn "Node.js is not installed; will auto-install"
        need_node=1
      fi

      if [[ "$need_node" -eq 1 ]]; then
        info "auto-installing Node.js 22..."
        auto_install_node 22
        node_major="$(node_major_version)"
        pm="$(package_manager)"
      fi
      ensure_supported_package_manager "$pm"
      info "detected package manager: $pm"
      info "detected ${pm} $($pm -v)"
      install_cmd="$(npm_global_install_cmd "$pm" "${pkg}@${version_or_tag}")"
      info "installing ${pkg}@${version_or_tag} via ${pm}"
      if [[ "$dry_run" == "1" ]]; then
        run_cmd --dry-run bash -lc "$install_cmd"
      else
        run_cmd bash -lc "$install_cmd"
      fi
      openclaw_path="$(openclaw_bin)"
      if [[ -n "$openclaw_path" ]]; then
        env_set "OPENCLAW_BIN" "$openclaw_path"
        info "detected OpenClaw binary at $openclaw_path"
      else
        warn "OpenClaw install finished but binary was not found on PATH; set OPENCLAW_BIN manually"
      fi
      env_set "OPENCLAW_GATEWAY_CMD" "$(gateway_command || printf 'openclaw gateway')"
      env_set "OPENCLAW_GATEWAY_PORT" "$(env_get OPENCLAW_GATEWAY_PORT || printf '%s' "$DEFAULT_GATEWAY_PORT")"
      env_set "OPENCLAW_SERVICE_MANAGER" "$manager"
      env_set "OPENCLAW_PACKAGE_MANAGER" "$pm"
      env_set "OPENCLAW_NPM_PACKAGE" "$pkg"
      env_set "OPENCLAW_UPDATE_CHANNEL" "$(update_channel)"
      write_service_state "stopped" "install" "stopped" ""
      "$ROOT_DIR/bin/simple-openclaw" backup create >/dev/null
      info "install scaffold complete"
      info "service manager: $manager"
      info "next steps: simple-openclaw init && simple-openclaw doctor"
      ;;
    uninstall)
      info "simple-openclaw code can be removed from $ROOT_DIR"
      info "runtime data remains in $SIMPLE_OPENCLAW_HOME"
      info "remove it manually if you want a full uninstall"
      ;;
    *)
      die "unknown install action: $action"
      ;;
  esac
}
