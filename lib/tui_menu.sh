#!/usr/bin/env bash

TUI_TOOL=""

detect_tui_tool() {
  if command_exists dialog; then
    TUI_TOOL="dialog"
  elif command_exists whiptail; then
    TUI_TOOL="whiptail"
  else
    TUI_TOOL=""
  fi
}

ensure_tui_tool() {
  detect_tui_tool
  if [[ -z "$TUI_TOOL" ]]; then
    info "dialog/whiptail not found, attempting to install..."
    local distro
    distro="$(detect_distro)"
    case "$distro" in
      macos)
        if command_exists brew; then
          brew install dialog >/dev/null 2>&1 || true
        fi
        ;;
      debian)
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq dialog >/dev/null 2>&1 || true
        ;;
      rhel)
        local sys_pm
        if command_exists dnf; then sys_pm="dnf"; else sys_pm="yum"; fi
        "$sys_pm" install -y -q dialog >/dev/null 2>&1 || true
        ;;
      alpine)
        apk add --quiet dialog >/dev/null 2>&1 || true
        ;;
      arch)
        pacman -S --noconfirm dialog >/dev/null 2>&1 || true
        ;;
      suse)
        zypper install -y dialog >/dev/null 2>&1 || true
        ;;
    esac
    detect_tui_tool
    [[ -n "$TUI_TOOL" ]] || die "could not install dialog or whiptail; please install one manually"
  fi
}

tui_msgbox() {
  local title="$1" text="$2"
  $TUI_TOOL --title "$title" --msgbox "$text" 12 60
}

tui_yesno() {
  local title="$1" text="$2"
  if $TUI_TOOL --title "$title" --yesno "$text" 10 60; then
    return 0
  else
    return 1
  fi
}

tui_inputbox() {
  local title="$1" text="$2" default="${3:-}"
  local result
  if [[ "$TUI_TOOL" == "dialog" ]]; then
    result="$($TUI_TOOL --title "$title" --inputbox "$text" 10 70 "$default" 3>&1 1>&2 2>&3)" || return 1
  else
    result="$($TUI_TOOL --title "$title" --inputbox "$text" 10 70 "$default" 3>&1 1>&2 2>&3)" || return 1
  fi
  printf '%s' "$result"
}

tui_passwordbox() {
  local title="$1" text="$2"
  local result
  if [[ "$TUI_TOOL" == "dialog" ]]; then
    result="$($TUI_TOOL --title "$title" --insecure --passwordbox "$text" 10 70 3>&1 1>&2 2>&3)" || return 1
  else
    result="$($TUI_TOOL --title "$title" --passwordbox "$text" 10 70 3>&1 1>&2 2>&3)" || return 1
  fi
  printf '%s' "$result"
}

tui_menu() {
  local title="$1" text="$2"
  shift 2
  local result
  if [[ "$TUI_TOOL" == "dialog" ]]; then
    result="$($TUI_TOOL --title "$title" --menu "$text" 20 70 12 "$@" 3>&1 1>&2 2>&3)" || return 1
  else
    result="$($TUI_TOOL --title "$title" --menu "$text" 20 70 12 "$@" 3>&1 1>&2 2>&3)" || return 1
  fi
  printf '%s' "$result"
}

tui_radiolist() {
  local title="$1" text="$2"
  shift 2
  local result
  if [[ "$TUI_TOOL" == "dialog" ]]; then
    result="$($TUI_TOOL --title "$title" --radiolist "$text" 18 70 10 "$@" 3>&1 1>&2 2>&3)" || return 1
  else
    result="$($TUI_TOOL --title "$title" --radiolist "$text" 18 70 10 "$@" 3>&1 1>&2 2>&3)" || return 1
  fi
  printf '%s' "$result"
}

tui_gauge() {
  local title="$1" text="$2" percent="$3"
  printf '%s' "$percent" | $TUI_TOOL --title "$title" --gauge "$text" 8 60 0
}

# ── Setup Wizard ──

tui_wizard() {
  local step=1 total=5

  # Step 1: Welcome
  tui_msgbox "simple-openclaw Setup Wizard" \
    "Welcome to simple-openclaw setup wizard!\n\nThis wizard will guide you through:\n  1. Install OpenClaw\n  2. Initialize configuration\n  3. Configure model provider\n  4. Set API key\n  5. Start the service\n\nPress OK to begin."

  # Step 2: Install
  if tui_yesno "Step $step/$total: Install" \
    "Install OpenClaw via npm?\n\nThis will:\n- Auto-install Node.js 22+ if needed\n- Install build tools if missing\n- Install OpenClaw globally\n\nSkip if already installed."; then
    local channel
    channel="$(tui_radiolist "Install Channel" "Select install channel:" \
      "stable" "Stable release (recommended)" "ON" \
      "beta"   "Beta release" "OFF" \
      "dev"    "Development release" "OFF")" || channel="stable"
    clear
    info "Running: simple-openclaw install --channel $channel"
    "$ROOT_DIR/bin/simple-openclaw" install --channel "$channel" || {
      tui_msgbox "Install Error" "Installation failed. Check the logs for details.\nYou can retry later with:\n  simple-openclaw install --channel $channel"
    }
  fi
  step=$((step + 1))

  # Step 3: Init
  if tui_yesno "Step $step/$total: Initialize" \
    "Initialize configuration?\n\nThis generates base config files under\n~/.simple-openclaw/config/\n\nSkip if already initialized."; then
    clear
    info "Running: simple-openclaw init"
    "$ROOT_DIR/bin/simple-openclaw" init || {
      tui_msgbox "Init Error" "Initialization failed."
    }
  fi
  step=$((step + 1))

  # Step 4: Model Configuration
  if tui_yesno "Step $step/$total: Model Configuration" \
    "Configure the LLM model provider?\n\nYou will set:\n- Provider type\n- Base URL\n- Model name"; then
    tui_wizard_model
  fi
  step=$((step + 1))

  # Step 5: API Key
  if tui_yesno "Step $step/$total: API Key" \
    "Set API key for your model provider?\n\nThe key will be stored securely in\n~/.simple-openclaw/config/secrets.json"; then
    local api_key
    api_key="$(tui_passwordbox "API Key" "Enter your API key:")" || api_key=""
    if [[ -n "$api_key" ]]; then
      clear
      "$ROOT_DIR/bin/simple-openclaw" secret set model.api_key "$api_key"
    else
      tui_msgbox "Skipped" "No API key entered. Set it later with:\n  simple-openclaw secret set model.api_key YOUR_KEY"
    fi
  fi
  step=$((step + 1))

  # Step 6: Start service
  if tui_yesno "Step $step/$total: Start Service" \
    "Start the OpenClaw gateway service now?"; then
    clear
    info "Running: simple-openclaw start"
    "$ROOT_DIR/bin/simple-openclaw" start
    sleep 2
    "$ROOT_DIR/bin/simple-openclaw" probe 2>/dev/null || true
  fi

  tui_msgbox "Setup Complete" \
    "Setup wizard complete!\n\nUseful commands:\n  simple-openclaw status    - check service status\n  simple-openclaw chat      - open terminal chat\n  simple-openclaw doctor    - run health check\n  simple-openclaw           - open management menu"
}

tui_wizard_model() {
  local provider base_url model_name

  provider="$(tui_radiolist "Provider Type" "Select your model provider:" \
    "anthropic" "Anthropic (Claude)" "ON" \
    "openai"    "OpenAI (GPT)" "OFF" \
    "custom"    "Other OpenAI-compatible API" "OFF")" || provider="anthropic"

  case "$provider" in
    anthropic)
      base_url="$(tui_inputbox "Base URL" \
        "Enter the API base URL:\n(Use proxy URL for relay services)" \
        "https://api.anthropic.com/v1")" || base_url="https://api.anthropic.com/v1"
      model_name="$(tui_inputbox "Model Name" \
        "Enter the model name:" \
        "claude-sonnet-4-20250514")" || model_name="claude-sonnet-4-20250514"
      ;;
    openai)
      base_url="$(tui_inputbox "Base URL" \
        "Enter the API base URL:" \
        "https://api.openai.com/v1")" || base_url="https://api.openai.com/v1"
      model_name="$(tui_inputbox "Model Name" \
        "Enter the model name:" \
        "gpt-4.1")" || model_name="gpt-4.1"
      ;;
    custom)
      base_url="$(tui_inputbox "Base URL" \
        "Enter your API provider base URL:" \
        "")" || base_url=""
      model_name="$(tui_inputbox "Model Name" \
        "Enter the model name:" \
        "")" || model_name=""
      provider=""
      ;;
  esac

  if [[ -z "$base_url" || -z "$model_name" ]]; then
    tui_msgbox "Skipped" "Model configuration skipped (missing values)."
    return
  fi

  clear
  local cmd="$ROOT_DIR/bin/simple-openclaw model set --base-url $base_url --model $model_name"
  [[ -z "$provider" ]] || cmd="$cmd --provider $provider"
  info "Running: model set --base-url $base_url --model $model_name${provider:+ --provider $provider}"
  "$ROOT_DIR/bin/simple-openclaw" model set --base-url "$base_url" --model "$model_name" \
    ${provider:+--provider "$provider"}
}

# ── Main Menu ──

tui_main_menu() {
  while true; do
    local choice
    choice="$(tui_menu "simple-openclaw Management" \
      "Select an operation:" \
      "setup"    "Run setup wizard" \
      "status"   "Show service status" \
      "start"    "Start the gateway" \
      "stop"     "Stop the gateway" \
      "restart"  "Restart the gateway" \
      "chat"     "Open terminal chat" \
      "model"    "Configure model" \
      "secret"   "Manage secrets" \
      "channel"  "Manage channels" \
      "plugin"   "Manage plugins" \
      "doctor"   "Run health check" \
      "backup"   "Backup management" \
      "update"   "Update OpenClaw" \
      "security" "Security audit" \
      "profile"  "Manage profiles" \
      "watchdog" "Watchdog monitoring" \
      "logs"     "View logs" \
      "uninstall" "Uninstall OpenClaw" \
      "quit"     "Exit")" || break

    case "$choice" in
      setup)    tui_wizard ;;
      status)   tui_cmd_status ;;
      start)    tui_cmd_start ;;
      stop)     tui_cmd_stop ;;
      restart)  tui_cmd_restart ;;
      chat)     tui_cmd_chat ;;
      model)    tui_submenu_model ;;
      secret)   tui_submenu_secret ;;
      channel)  tui_submenu_channel ;;
      plugin)   tui_submenu_plugin ;;
      doctor)   tui_cmd_doctor ;;
      backup)   tui_submenu_backup ;;
      update)   tui_cmd_update ;;
      security) tui_submenu_security ;;
      profile)  tui_submenu_profile ;;
      watchdog) tui_submenu_watchdog ;;
      logs)     tui_cmd_logs ;;
      uninstall) tui_cmd_uninstall ;;
      quit)     break ;;
    esac
  done
}

# ── Command wrappers ──

tui_run_and_show() {
  local title="$1"
  shift
  local output
  output="$("$@" 2>&1)" || true
  tui_msgbox "$title" "$output"
}

tui_cmd_status() {
  tui_run_and_show "Service Status" "$ROOT_DIR/bin/simple-openclaw" status
}

tui_cmd_start() {
  clear
  "$ROOT_DIR/bin/simple-openclaw" start
  sleep 1
  tui_run_and_show "Start Result" "$ROOT_DIR/bin/simple-openclaw" status
}

tui_cmd_stop() {
  clear
  "$ROOT_DIR/bin/simple-openclaw" stop
  tui_run_and_show "Stop Result" "$ROOT_DIR/bin/simple-openclaw" status
}

tui_cmd_restart() {
  clear
  "$ROOT_DIR/bin/simple-openclaw" restart
  sleep 1
  tui_run_and_show "Restart Result" "$ROOT_DIR/bin/simple-openclaw" status
}

tui_cmd_chat() {
  clear
  exec "$ROOT_DIR/bin/simple-openclaw" chat
}

tui_cmd_doctor() {
  tui_run_and_show "Health Check" "$ROOT_DIR/bin/simple-openclaw" doctor
}

tui_cmd_update() {
  if tui_yesno "Update OpenClaw" "Check for and install updates?"; then
    clear
    "$ROOT_DIR/bin/simple-openclaw" update || true
    tui_msgbox "Update" "Update process complete."
  fi
}

tui_submenu_security() {
  while true; do
    local choice
    choice="$(tui_menu "Security" \
      "Select an action:" \
      "audit"   "Run full security audit" \
      "harden"  "Auto-fix security issues" \
      "back"    "Back to main menu")" || break

    case "$choice" in
      audit)
        local output
        output="$("$ROOT_DIR/bin/simple-openclaw" security audit 2>&1)" || true
        $TUI_TOOL --title "Security Audit Report" --msgbox "$output" 30 80
        ;;
      harden)
        if tui_yesno "Security Harden" \
          "Auto-fix detected security issues?\n\nThis will:\n- Fix file/directory permissions\n- Redact secrets found in logs\n- Tighten config file access"; then
          local output
          output="$("$ROOT_DIR/bin/simple-openclaw" security harden 2>&1)" || true
          $TUI_TOOL --title "Security Harden Report" --msgbox "$output" 30 80
        fi
        ;;
      back) break ;;
    esac
  done
}

tui_cmd_security() {
  tui_submenu_security
}

tui_cmd_logs() {
  clear
  "$ROOT_DIR/bin/simple-openclaw" logs --follow 2>/dev/null || {
    local log_file="$LOG_DIR/openclaw-gateway.log"
    if [[ -f "$log_file" ]]; then
      $TUI_TOOL --title "Gateway Logs" --textbox "$log_file" 24 80
    else
      tui_msgbox "Logs" "No log files found."
    fi
  }
}

tui_cmd_uninstall() {
  if ! tui_yesno "Uninstall OpenClaw" \
    "Are you sure you want to uninstall OpenClaw?\n\nThis will:\n- Stop the running gateway\n- Remove the openclaw npm package"; then
    return
  fi

  local flags=""

  if tui_yesno "Remove Runtime Data" \
    "Also remove runtime data?\n\n$SIMPLE_OPENCLAW_HOME\n\n(configs, backups, logs, state)"; then
    flags="$flags --purge"
  fi

  if tui_yesno "Remove OpenClaw Config" \
    "Also remove OpenClaw config directory?\n\n~/.openclaw\n\n(openclaw.json, .env, workspace)"; then
    flags="$flags --remove-config"
  fi

  clear
  # shellcheck disable=SC2086
  "$ROOT_DIR/bin/simple-openclaw" uninstall $flags || true
  tui_msgbox "Uninstall Complete" "OpenClaw has been uninstalled."
}

# ── Model submenu ──

tui_submenu_model() {
  while true; do
    local choice
    choice="$(tui_menu "Model Management" \
      "Select an action:" \
      "list"     "Show current model config" \
      "set"      "Configure model provider" \
      "test"     "Test model connectivity" \
      "back"     "Back to main menu")" || break

    case "$choice" in
      list) tui_run_and_show "Model Config" "$ROOT_DIR/bin/simple-openclaw" model list ;;
      set)  tui_wizard_model ;;
      test) tui_run_and_show "Model Test" "$ROOT_DIR/bin/simple-openclaw" model test ;;
      back) break ;;
    esac
  done
}

# ── Secret submenu ──

tui_submenu_secret() {
  while true; do
    local choice
    choice="$(tui_menu "Secret Management" \
      "Select an action:" \
      "list"     "List secrets (masked)" \
      "set-key"  "Set model API key" \
      "set"      "Set custom secret" \
      "rotate"   "Rotate a secret" \
      "audit"    "Audit secrets" \
      "history"  "Rotation history" \
      "rotate-expired" "Rotate all expired" \
      "back"     "Back to main menu")" || break

    case "$choice" in
      list)    tui_run_and_show "Secrets" "$ROOT_DIR/bin/simple-openclaw" secret list ;;
      set-key)
        local api_key
        api_key="$(tui_passwordbox "API Key" "Enter API key for model provider:")" || continue
        if [[ -n "$api_key" ]]; then
          "$ROOT_DIR/bin/simple-openclaw" secret set model.api_key "$api_key"
          tui_msgbox "Secret Updated" "model.api_key has been updated."
        fi
        ;;
      set)
        local skey sval
        skey="$(tui_inputbox "Secret Key" "Enter secret key name:")" || continue
        sval="$(tui_passwordbox "Secret Value" "Enter value for '$skey':")" || continue
        if [[ -n "$skey" && -n "$sval" ]]; then
          "$ROOT_DIR/bin/simple-openclaw" secret set "$skey" "$sval"
          tui_msgbox "Secret Updated" "$skey has been updated."
        fi
        ;;
      audit)   tui_run_and_show "Secret Audit" "$ROOT_DIR/bin/simple-openclaw" secret audit ;;
      rotate)
        local rkey
        rkey="$(tui_inputbox "Rotate Secret" "Enter secret key to rotate:")" || continue
        [[ -n "$rkey" ]] && {
          clear
          "$ROOT_DIR/bin/simple-openclaw" secret rotate "$rkey" || true
          tui_msgbox "Rotate" "Secret rotation complete."
        }
        ;;
      history) tui_run_and_show "Rotation History" "$ROOT_DIR/bin/simple-openclaw" secret history ;;
      rotate-expired)
        if tui_yesno "Rotate Expired" "Rotate all expired secrets?"; then
          clear
          "$ROOT_DIR/bin/simple-openclaw" secret rotate-expired || true
          tui_msgbox "Rotate" "Expired secrets rotation complete."
        fi
        ;;
      back)    break ;;
    esac
  done
}

# ── Channel submenu ──

tui_submenu_channel() {
  while true; do
    local choice
    choice="$(tui_menu "Channel Management" \
      "Select an action:" \
      "list"     "List configured channels" \
      "add"      "Add a new channel" \
      "edit"     "Edit channel credentials" \
      "remove"   "Remove a channel" \
      "test"     "Test a channel" \
      "back"     "Back to main menu")" || break

    case "$choice" in
      list) tui_run_and_show "Channels" "$ROOT_DIR/bin/simple-openclaw" channel list ;;
      add)
        local ch_name
        ch_name="$(tui_radiolist "Add Channel" "Select channel type:" \
          "feishu"   "Feishu / Lark" "ON" \
          "qq"       "QQ" "OFF" \
          "wechat"   "WeChat" "OFF" \
          "telegram" "Telegram" "OFF" \
          "slack"    "Slack" "OFF" \
          "custom"   "Custom channel name" "OFF")" || continue
        if [[ "$ch_name" == "custom" ]]; then
          ch_name="$(tui_inputbox "Channel Name" "Enter custom channel name:")" || continue
        fi
        if [[ -n "$ch_name" ]]; then
          "$ROOT_DIR/bin/simple-openclaw" channel add "$ch_name"
          tui_msgbox "Channel Added" "Channel '$ch_name' has been added.\n\nNext: configure credentials via 'Edit channel'."
        fi
        ;;
      edit)
        local ch_edit_name ch_key ch_value
        ch_edit_name="$(tui_inputbox "Edit Channel" "Enter channel name to edit:")" || continue
        ch_key="$(tui_inputbox "Credential Key" "Enter credential key (e.g. app_id):")" || continue
        ch_value="$(tui_inputbox "Credential Value" "Enter value for '$ch_key':")" || continue
        if [[ -n "$ch_edit_name" && -n "$ch_key" && -n "$ch_value" ]]; then
          "$ROOT_DIR/bin/simple-openclaw" channel edit "$ch_edit_name" --set "${ch_key}=${ch_value}"
          tui_msgbox "Channel Updated" "Credential '$ch_key' updated for channel '$ch_edit_name'."
        fi
        ;;
      remove)
        local ch_rm_name
        ch_rm_name="$(tui_inputbox "Remove Channel" "Enter channel name to remove:")" || continue
        if [[ -n "$ch_rm_name" ]]; then
          if tui_yesno "Confirm" "Remove channel '$ch_rm_name'?"; then
            "$ROOT_DIR/bin/simple-openclaw" channel remove "$ch_rm_name"
            tui_msgbox "Channel Removed" "Channel '$ch_rm_name' has been removed."
          fi
        fi
        ;;
      test)
        local ch_test_name
        ch_test_name="$(tui_inputbox "Test Channel" "Enter channel name to test:")" || continue
        if [[ -n "$ch_test_name" ]]; then
          tui_run_and_show "Channel Test" "$ROOT_DIR/bin/simple-openclaw" channel test "$ch_test_name"
        fi
        ;;
      back) break ;;
    esac
  done
}

# ── Plugin submenu ──

tui_submenu_plugin() {
  while true; do
    local choice
    choice="$(tui_menu "Plugin Management" \
      "Select an action:" \
      "list"     "List installed plugins" \
      "install"  "Install a plugin" \
      "enable"   "Enable a plugin" \
      "disable"  "Disable a plugin" \
      "scan"     "Security scan (all plugins)" \
      "scan-one" "Security scan (single plugin)" \
      "audit"    "Audit plugins against policy" \
      "doctor"   "Plugin health check" \
      "back"     "Back to main menu")" || break

    case "$choice" in
      list)   tui_run_and_show "Plugins" "$ROOT_DIR/bin/simple-openclaw" plugin list ;;
      install)
        local pl_pkg pl_pin
        pl_pkg="$(tui_inputbox "Install Plugin" "Enter plugin package name\n(e.g. @openclaw/feishu):")" || continue
        if [[ -n "$pl_pkg" ]]; then
          pl_pin=""
          if tui_yesno "Pin Version" "Pin this plugin to its current version?"; then
            pl_pin="--pin"
          fi
          clear
          "$ROOT_DIR/bin/simple-openclaw" plugin install "$pl_pkg" $pl_pin || true
          tui_msgbox "Plugin Install" "Plugin install for '$pl_pkg' complete."
        fi
        ;;
      enable)
        local pl_en
        pl_en="$(tui_inputbox "Enable Plugin" "Enter plugin package name:")" || continue
        [[ -n "$pl_en" ]] && "$ROOT_DIR/bin/simple-openclaw" plugin enable "$pl_en" && \
          tui_msgbox "Plugin Enabled" "Plugin '$pl_en' enabled."
        ;;
      disable)
        local pl_dis
        pl_dis="$(tui_inputbox "Disable Plugin" "Enter plugin package name:")" || continue
        [[ -n "$pl_dis" ]] && "$ROOT_DIR/bin/simple-openclaw" plugin disable "$pl_dis" && \
          tui_msgbox "Plugin Disabled" "Plugin '$pl_dis' disabled."
        ;;
      audit)  tui_run_and_show "Plugin Audit" "$ROOT_DIR/bin/simple-openclaw" plugin audit ;;
      scan)
        local output
        output="$("$ROOT_DIR/bin/simple-openclaw" plugin scan 2>&1)" || true
        $TUI_TOOL --title "Plugin Security Scan (All)" --msgbox "$output" 30 80
        ;;
      scan-one)
        local pl_scan
        pl_scan="$(tui_inputbox "Scan Plugin" "Enter plugin package name to scan:")" || continue
        if [[ -n "$pl_scan" ]]; then
          local output
          output="$("$ROOT_DIR/bin/simple-openclaw" plugin scan "$pl_scan" 2>&1)" || true
          $TUI_TOOL --title "Plugin Scan: $pl_scan" --msgbox "$output" 30 80
        fi
        ;;
      doctor) tui_run_and_show "Plugin Doctor" "$ROOT_DIR/bin/simple-openclaw" plugin doctor ;;
      back)   break ;;
    esac
  done
}

# ── Backup submenu ──

tui_submenu_backup() {
  while true; do
    local choice
    choice="$(tui_menu "Backup Management" \
      "Select an action:" \
      "create"   "Create a new backup" \
      "list"     "List existing backups" \
      "verify"   "Verify a backup" \
      "restore"  "Restore from backup" \
      "back"     "Back to main menu")" || break

    case "$choice" in
      create)
        clear
        "$ROOT_DIR/bin/simple-openclaw" backup create
        tui_msgbox "Backup" "Backup created successfully."
        ;;
      list)   tui_run_and_show "Backups" "$ROOT_DIR/bin/simple-openclaw" backup list ;;
      verify) tui_run_and_show "Backup Verify" "$ROOT_DIR/bin/simple-openclaw" backup verify ;;
      restore)
        local bk_file
        bk_file="$(tui_inputbox "Restore" "Enter backup file path:")" || continue
        if [[ -n "$bk_file" ]]; then
          if tui_yesno "Confirm Restore" "Restore from:\n$bk_file\n\nThis will overwrite current config."; then
            clear
            "$ROOT_DIR/bin/simple-openclaw" restore "$bk_file" || true
            tui_msgbox "Restore" "Restore process complete."
          fi
        fi
        ;;
      back) break ;;
    esac
  done
}

tui_submenu_profile() {
  while true; do
    local choice
    choice="$(tui_menu "Profile Management" \
      "Select an action:" \
      "list"    "List profiles" \
      "create"  "Create a new profile" \
      "switch"  "Switch active profile" \
      "delete"  "Delete a profile" \
      "export"  "Export a profile" \
      "import"  "Import a profile" \
      "back"    "Back to main menu")" || break

    case "$choice" in
      list)   tui_run_and_show "Profiles" "$ROOT_DIR/bin/simple-openclaw" profile list ;;
      create)
        local pname
        pname="$(tui_inputbox "Create Profile" "Enter profile name:")" || continue
        [[ -n "$pname" ]] && {
          clear
          "$ROOT_DIR/bin/simple-openclaw" profile create "$pname" || true
          tui_msgbox "Profile" "Profile '$pname' created."
        }
        ;;
      switch)
        local pname
        pname="$(tui_inputbox "Switch Profile" "Enter profile name:")" || continue
        [[ -n "$pname" ]] && {
          clear
          "$ROOT_DIR/bin/simple-openclaw" profile switch "$pname" || true
          tui_msgbox "Profile" "Switched to profile '$pname'."
        }
        ;;
      delete)
        local pname
        pname="$(tui_inputbox "Delete Profile" "Enter profile name:")" || continue
        [[ -n "$pname" ]] && {
          if tui_yesno "Confirm Delete" "Delete profile '$pname'?\nThis cannot be undone."; then
            clear
            "$ROOT_DIR/bin/simple-openclaw" profile delete "$pname" || true
          fi
        }
        ;;
      export)
        local pname
        pname="$(tui_inputbox "Export Profile" "Enter profile name:")" || continue
        [[ -n "$pname" ]] && {
          clear
          "$ROOT_DIR/bin/simple-openclaw" profile export "$pname" || true
          tui_msgbox "Export" "Profile exported."
        }
        ;;
      import)
        local pfile
        pfile="$(tui_inputbox "Import Profile" "Enter archive file path:")" || continue
        [[ -n "$pfile" ]] && {
          clear
          "$ROOT_DIR/bin/simple-openclaw" profile import "$pfile" || true
          tui_msgbox "Import" "Profile imported."
        }
        ;;
      back) break ;;
    esac
  done
}

tui_submenu_watchdog() {
  while true; do
    local choice
    choice="$(tui_menu "Watchdog Monitoring" \
      "Select an action:" \
      "status"  "Show watchdog status" \
      "start"   "Start watchdog" \
      "stop"    "Stop watchdog" \
      "log"     "View watchdog log" \
      "back"    "Back to main menu")" || break

    case "$choice" in
      status) tui_run_and_show "Watchdog Status" "$ROOT_DIR/bin/simple-openclaw" watchdog status ;;
      start)
        clear
        "$ROOT_DIR/bin/simple-openclaw" watchdog start || true
        tui_msgbox "Watchdog" "Watchdog started."
        ;;
      stop)
        clear
        "$ROOT_DIR/bin/simple-openclaw" watchdog stop || true
        tui_msgbox "Watchdog" "Watchdog stopped."
        ;;
      log) tui_run_and_show "Watchdog Log" "$ROOT_DIR/bin/simple-openclaw" watchdog log ;;
      back) break ;;
    esac
  done
}

# ── Entry point ──

simple_openclaw_tui_menu() {
  local mode="${1:-menu}"
  shift || true

  ensure_tui_tool

  case "$mode" in
    wizard|setup)
      tui_wizard
      ;;
    menu|*)
      tui_main_menu
      ;;
  esac
}
