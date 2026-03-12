# simple-openclaw

`simple-openclaw` is an operations wrapper for [OpenClaw](https://docs.openclaw.ai/).

It does not replace OpenClaw. It makes OpenClaw easier to install, safer to operate, and less fragile for normal users.

## Why This Exists

OpenClaw is powerful, but the real-world setup flow still has a few rough edges:

- Node.js version requirements can block first-time installs
- service status and real gateway reachability can drift apart
- stale processes can keep the port busy after a failed restart
- plugin allowlists can silently block channels
- plugin state can become confusing after upgrades or repeated installs
- channel setup is still too manual for non-operators

`simple-openclaw` adds a control layer on top of OpenClaw so users get one place for install, config, health checks, backups, updates, and recovery.

## What It Focuses On

The project is built around five operational priorities:

- Install
- Doctor
- Probe
- Rollback
- Plugin Governance

Those are the places where OpenClaw users most often need a safer, clearer workflow.

## What You Get

- One CLI entrypoint: `simple-openclaw`
- Interactive TUI menu and guided setup wizard (dialog/whiptail)
- Guided bootstrap for Node.js/OpenClaw prerequisites
- runtime config under `~/.simple-openclaw`
- model, channel, plugin, backup, update, and security management
- service status separated from real probe results
- plugin allowlist, pinned-version checks, and plugin security scanning
- comprehensive security audit and auto-hardening
- full uninstall with optional data purge
- support bundle generation for faster debugging

## Current Status

This repository already includes a working shell-based CLI scaffold with real command wiring for:

- OpenClaw install through npm or pnpm global packages
- OpenClaw update through `openclaw update` or package-manager fallback
- plugin install through `openclaw plugins install`
- plugin security scanning (source code analysis, install hook audit, binary detection)
- JSON-backed config validation with `jq`
- channel template seeding and required-field checks
- doctor and security reports
- interactive TUI menu and setup wizard

## Quick Start

### Option A: Interactive Setup Wizard (Recommended)

The fastest way to get started. Run without arguments or use `setup` to launch the guided wizard:

```bash
git clone https://github.com/majiajue/simple-openclaw.git
cd simple-openclaw
./bin/simple-openclaw setup
```

The wizard walks you through: Install -> Init -> Model Config -> API Key -> Start.

> Requires `dialog` or `whiptail`. The wizard will attempt to install `dialog` automatically if neither is found.

### Option B: Step-by-Step CLI

#### Step 1: Install OpenClaw

Clone the repository and run the install command. This will automatically:
- Detect your OS and architecture
- Install Node.js 22+ if missing or broken (supports old GLIBC systems)
- Install build tools (cmake, g++, make) if missing
- Install OpenClaw via npm

```bash
git clone https://github.com/majiajue/simple-openclaw.git
cd simple-openclaw
./bin/simple-openclaw install --channel stable
```

#### Step 2: Initialize Configuration

Generate the base configuration files under `~/.simple-openclaw/config/`.

```bash
./bin/simple-openclaw init
```

#### Step 3: Configure Your Model

Set up the LLM provider. Supports Anthropic, OpenAI, and any third-party proxy/relay API.

**Third-party proxy / relay API (recommended for China users):**

If you use a third-party API relay service (e.g. pikachu.claudecode.love), configure it as follows:

```bash
./bin/simple-openclaw model set \
  --base-url https://your-relay-host.com \
  --model claude-opus-4-6 \
  --provider anthropic \
  --api-key your-relay-api-key
```

This generates the complete OpenClaw provider config including `apiKey`, `auth`, `models` array, and `auth.profiles`. The provider ID is auto-generated from the base URL (e.g. `custom-your-relay-host-com`).

If you already configured OpenClaw via `openclaw onboard`, `model set` will detect and update the existing provider instead of creating a new one.

**Claude (direct Anthropic API):**

```bash
./bin/simple-openclaw model set \
  --base-url https://api.anthropic.com/v1 \
  --model claude-sonnet-4-20250514 \
  --provider anthropic \
  --api-key your-api-key
```

**OpenAI (direct):**

```bash
./bin/simple-openclaw model set \
  --base-url https://api.openai.com/v1 \
  --model gpt-4.1 \
  --api-key your-api-key
```

**Other OpenAI-compatible providers:**

```bash
./bin/simple-openclaw model set \
  --base-url https://your-api-provider.com/v1 \
  --model your-model-name \
  --api-key your-api-key
```

> **Note:** `--api-key` can also be set separately via `./bin/simple-openclaw secret set model.api_key your-key`

#### Step 4 (Optional): Add a Channel

Skip this step if you don't need to connect to a messaging platform. Channels are only needed for integrations like Feishu or QQ.

```bash
./bin/simple-openclaw channel add feishu
./bin/simple-openclaw channel edit feishu --set app_id=your-app-id
./bin/simple-openclaw channel edit feishu --set app_secret=your-app-secret
./bin/simple-openclaw channel edit feishu --set verification_token=your-token
```

#### Step 5 (Optional): Install the Channel Plugin

```bash
./bin/simple-openclaw plugin install @openclaw/feishu --pin
```

#### Step 6: Run Health Check

Verify everything is configured correctly.

```bash
./bin/simple-openclaw doctor
```

#### Step 7: Start the Service

```bash
./bin/simple-openclaw start
./bin/simple-openclaw probe
```

#### Step 8: Start Chatting

```bash
# Open the terminal chat UI
./bin/simple-openclaw chat

# Or send a single message
./bin/simple-openclaw agent --message "hello"
```

## Interactive Menu

Run `simple-openclaw` without arguments to open the interactive management menu:

```bash
./bin/simple-openclaw
```

The menu provides access to all operations:

- Setup wizard (guided first-time configuration)
- Service management (start / stop / restart / status)
- Chat (open terminal chat UI)
- Model configuration
- Secret management
- Channel management
- Plugin management (install, audit, security scan)
- Health check (doctor)
- Backup and restore
- Update
- Security audit and hardening
- Log viewer
- Uninstall

You can also launch the wizard directly:

```bash
./bin/simple-openclaw setup
```

## Security

### Security Audit

Run a comprehensive security audit covering 8 categories:

```bash
./bin/simple-openclaw security audit
```

The audit checks:

| Category | What It Checks |
|---|---|
| File Permissions | Config/state/backup dirs are 700; secrets/env/policy files are 600; `~/.openclaw/.env` and `openclaw.json` permissions |
| Secret Leak Scan | Scans log files and config files for plain-text API keys |
| API Key Validation | Checks key length, detects placeholder values (test-key, your-xxx, etc.) |
| Network Binding | Detects if gateway listens on 0.0.0.0 (all interfaces) instead of 127.0.0.1 |
| Plugin Policy | Checks allowlist for wildcards, version pinning policy, unpinned plugins, unapproved plugins |
| Plugin Security Scan | Static analysis of installed plugin source code (see below) |
| Config Integrity | Validates JSON format of secrets.json, policy.json, openclaw.json; checks env file for embedded secrets |
| Process Security | Warns if gateway is running as root |

### Auto-Hardening

Automatically fix detected security issues:

```bash
./bin/simple-openclaw security harden
```

This will:
- Fix file and directory permissions (700/600)
- Redact leaked secrets found in log files
- Tighten config file access

### Plugin Security Scanning

Scan installed plugins for dangerous code patterns:

```bash
# Scan all installed plugins
./bin/simple-openclaw plugin scan

# Scan a specific plugin
./bin/simple-openclaw plugin scan @openclaw/feishu
```

The scanner performs three layers of analysis:

**Package Metadata** -- Checks `package.json` for:
- Dangerous install hooks (preinstall/postinstall that download or execute code)
- Package name mismatches (identity spoofing)
- Typosquatting dependency names
- Excessive dependency count

**Source Code Analysis** -- Scans JS files for:
- `eval()` / `new Function()` usage
- `child_process` / `exec` / `spawn` calls
- Hardcoded IP network requests
- System path writes (`/etc`, `/usr`, `/bin`)
- Crypto mining indicators (stratum, coinhive, xmrig, etc.)
- Environment variable exfiltration (`JSON.stringify(process.env)` + send)
- Code obfuscation (hex/unicode escape sequences, base64 decoding)

**Permissions & Binaries** -- Detects:
- Native binary modules (`.node`, `.so`, `.dylib`)
- Unexpected executable files
- setuid/setgid files

Each plugin receives a verdict: **CLEAN**, **REVIEW_RECOMMENDED**, or **DANGEROUS**.

## Uninstall

Remove OpenClaw completely:

```bash
# Basic uninstall: stop gateway + remove npm package
./bin/simple-openclaw uninstall

# Also remove runtime data (~/.simple-openclaw)
./bin/simple-openclaw uninstall --purge

# Also remove OpenClaw config (~/.openclaw)
./bin/simple-openclaw uninstall --remove-config

# Full cleanup
./bin/simple-openclaw uninstall --purge --remove-config

# Preview what would be removed without executing
./bin/simple-openclaw uninstall --purge --dry-run
```

## Command Reference

```text
# Interactive
simple-openclaw                         open management menu (default)
simple-openclaw setup                   run guided setup wizard
simple-openclaw menu                    open management menu (explicit)

# Install & Init
simple-openclaw install --channel stable
simple-openclaw init
simple-openclaw uninstall [--purge] [--remove-config] [--dry-run]

# Service
simple-openclaw start
simple-openclaw stop
simple-openclaw restart
simple-openclaw status
simple-openclaw probe

# Chat
simple-openclaw chat
simple-openclaw tui
simple-openclaw agent --message <text>

# Health
simple-openclaw doctor
simple-openclaw doctor --fix

# Model
simple-openclaw model set --base-url <url> --model <name> --provider <type> --api-key <key>
simple-openclaw model list
simple-openclaw model test

# Secrets
simple-openclaw secret set <key> <value>
simple-openclaw secret list
simple-openclaw secret audit

# Channels
simple-openclaw channel add <name>
simple-openclaw channel edit <name> --set <key=value>
simple-openclaw channel list
simple-openclaw channel test <name>
simple-openclaw channel remove <name>

# Plugins
simple-openclaw plugin install <pkg> [--pin]
simple-openclaw plugin enable <pkg>
simple-openclaw plugin disable <pkg>
simple-openclaw plugin pin <pkg>@<version>
simple-openclaw plugin list
simple-openclaw plugin audit
simple-openclaw plugin doctor
simple-openclaw plugin scan [<pkg>]

# Security
simple-openclaw security audit
simple-openclaw security harden

# Backup & Recovery
simple-openclaw backup create
simple-openclaw backup list
simple-openclaw backup verify
simple-openclaw restore <file>
simple-openclaw rollback <snapshot-id>

# Update
simple-openclaw update
simple-openclaw update --target <ver>

# Other
simple-openclaw repair <stale-process|port|service>
simple-openclaw watchdog <enable|disable|status>
simple-openclaw logs [--follow|--since <window>]
simple-openclaw support-bundle
```

## Design Principles

- Keep the official OpenClaw runtime underneath
- reduce onboarding questions to the minimum
- separate desired service state from actual probe state
- prefer explicit safety checks over silent magic
- make rollback and diagnostics first-class features
- scan plugins for dangerous code before trusting them
- keep user data outside the code directory

## Repository Layout

```text
bin/         CLI entrypoint
lib/         command modules
templates/   config and service templates
hooks/       lifecycle hooks
docs/        user-facing docs
tests/       smoke and future regression tests
packaging/   install and release helpers
```

## Runtime Layout

```text
~/.simple-openclaw/
  config/          env, secrets.json, policy.json, channels/
  backups/
  logs/
  cache/
  snapshots/
  reports/         doctor/, security/
  state/           service_state.json, installed_plugins.db
```

## Who This Is For

- users who want OpenClaw without a complex manual setup
- operators who need a predictable wrapper for health checks and recovery
- teams who want safer plugin and channel management

## Roadmap

### v2.0 (current)

- install / init / uninstall
- model / channel / plugin flows
- start / stop / status / probe
- doctor / doctor --fix
- backup / restore / rollback
- update / release
- security audit / harden
- plugin security scanning
- interactive TUI menu and setup wizard
- logs / support-bundle

### v2.1

- watchdog
- secret rotation
- multi-profile environments

### v2.2

- web admin UI
- remote machine health checks
- centralized alerting

## Notes

- `install` auto-installs Node.js 22+ if missing (supports GLIBC 2.17+ via unofficial-builds)
- `install` auto-installs build tools (cmake, g++, make) based on your OS
- `model set` supports `--api-key` inline or separate `secret set model.api_key`
- `model set` with `--provider anthropic` and a third-party base URL auto-generates the full provider config (apiKey, auth, models array, auth.profiles)
- `model set` detects existing providers from `openclaw onboard` and updates them instead of creating duplicates
- `chat`/`tui`/`agent` commands bypass `#!/usr/bin/env node` shebang issues on old GLIBC systems
- native modules like `node-llama-cpp` may fail to compile on older systems; this is non-blocking -- OpenClaw works fine with remote API providers
- the wrapper currently uses shell scripts for speed and portability
- if `openclaw` is not on `PATH`, you can still set `OPENCLAW_BIN` manually
- configuration lives in `~/.simple-openclaw`, not in the repository
- the interactive menu requires `dialog` or `whiptail` (auto-installed if missing)
- `uninstall --purge` removes all runtime data; `--remove-config` also removes `~/.openclaw`
- `plugin scan` performs static analysis only; it does not execute plugin code

## Related Docs

- [Installation](./docs/INSTALL.md)
- [Channels](./docs/CHANNELS.md)
- [Security](./docs/SECURITY.md)
- [Backup](./docs/BACKUP.md)
- [Troubleshooting](./docs/TROUBLESHOOTING.md)

## Contributing

The fastest contributions right now are:

- more real-world doctor checks
- channel-specific validation
- service manager integration for `launchd` and `systemd`
- plugin compatibility rules
- better backup metadata and rollback verification
- additional plugin scan heuristics

If you want OpenClaw to feel more like a product than a raw toolkit, this project is pointed in that direction.
