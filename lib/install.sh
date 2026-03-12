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
        pkg="$(openclaw_npm_package)"
      fi
      ensure_supported_package_manager "$pm"
      info "detected package manager: $pm"
      info "detected ${pm} $($pm -v)"
      ensure_build_tools
      install_cmd="$(npm_global_install_cmd "$pm" "${pkg}@${version_or_tag}")"
      info "installing ${pkg}@${version_or_tag} via ${pm} (skipping postinstall scripts)..."
      if [[ "$dry_run" == "1" ]]; then
        run_cmd --dry-run bash -lc "$install_cmd --ignore-scripts"
      else
        run_cmd bash -lc "$install_cmd --ignore-scripts"
      fi

      local pkg_dir=""
      if [[ "$pm" == "npm" ]]; then
        pkg_dir="$(npm root -g 2>/dev/null)/${pkg}" || true
      elif [[ "$pm" == "pnpm" ]]; then
        pkg_dir="$(pnpm root -g 2>/dev/null)/${pkg}" || true
      fi

      if [[ -n "$pkg_dir" ]] && [[ -d "$pkg_dir" ]] && [[ "$dry_run" != "1" ]]; then
        info "running postinstall scripts (native modules may take a while)..."
        if ! (cd "$pkg_dir" && npm rebuild 2>&1 | tail -n 5); then
          warn "some native modules failed to build; OpenClaw will still work with remote API providers"
          warn "to retry later: cd $pkg_dir && npm rebuild"
        fi
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
      local purge=0 dry_run=0 keep_config=1
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --purge)
            purge=1
            shift
            ;;
          --dry-run)
            dry_run=1
            shift
            ;;
          --remove-config)
            keep_config=0
            shift
            ;;
          *)
            die "unknown uninstall option: $1"
            ;;
        esac
      done

      # Stop the gateway if running
      local tracked_pid
      tracked_pid="$(read_gateway_pid || true)"
      if pid_is_running "$tracked_pid" 2>/dev/null; then
        info "stopping gateway (pid $tracked_pid)..."
        if [[ "$dry_run" == "1" ]]; then
          run_cmd --dry-run kill "$tracked_pid"
        else
          kill "$tracked_pid" >/dev/null 2>&1 || true
          clear_gateway_pid
        fi
      fi

      local port
      port="$(gateway_port)"
      local port_pid
      port_pid="$(listener_pid_on_port "$port" 2>/dev/null || true)"
      if [[ -n "$port_pid" ]]; then
        info "stopping process on port $port (pid $port_pid)..."
        if [[ "$dry_run" == "1" ]]; then
          run_cmd --dry-run kill "$port_pid"
        else
          kill "$port_pid" >/dev/null 2>&1 || true
        fi
      fi

      # Uninstall the npm global package
      local pm pkg
      pm="$(package_manager)"
      pkg="$(openclaw_npm_package)"
      if [[ -n "$pm" ]] && command_exists "$pm"; then
        info "uninstalling $pkg via $pm..."
        local uninstall_cmd
        case "$pm" in
          npm)  uninstall_cmd="npm uninstall -g $pkg" ;;
          pnpm) uninstall_cmd="pnpm remove -g $pkg" ;;
        esac
        if [[ "$dry_run" == "1" ]]; then
          run_cmd --dry-run bash -lc "$uninstall_cmd"
        else
          bash -lc "$uninstall_cmd" 2>&1 || warn "npm uninstall returned an error; package may already be removed"
        fi
      else
        warn "package manager not found; skipping npm package removal"
      fi

      # Remove runtime data
      if [[ "$purge" == "1" ]]; then
        info "removing runtime data at $SIMPLE_OPENCLAW_HOME..."
        if [[ "$dry_run" == "1" ]]; then
          run_cmd --dry-run rm -rf "$SIMPLE_OPENCLAW_HOME"
        else
          rm -rf "$SIMPLE_OPENCLAW_HOME"
        fi
        info "runtime data removed"
      else
        info "runtime data preserved at $SIMPLE_OPENCLAW_HOME"
        info "use --purge to remove it"
      fi

      # Remove OpenClaw config (~/.openclaw)
      local openclaw_home="${HOME}/.openclaw"
      if [[ "$keep_config" == "0" ]]; then
        if [[ -d "$openclaw_home" ]]; then
          info "removing OpenClaw config at $openclaw_home..."
          if [[ "$dry_run" == "1" ]]; then
            run_cmd --dry-run rm -rf "$openclaw_home"
          else
            rm -rf "$openclaw_home"
          fi
          info "OpenClaw config removed"
        fi
      else
        if [[ -d "$openclaw_home" ]]; then
          info "OpenClaw config preserved at $openclaw_home"
          info "use --remove-config to remove it"
        fi
      fi

      info "uninstall complete"
      info "simple-openclaw source code remains at $ROOT_DIR"
      ;;
    *)
      die "unknown install action: $action"
      ;;
  esac
}
