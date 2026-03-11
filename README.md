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
- Guided bootstrap for Node.js/OpenClaw prerequisites
- runtime config under `~/.simple-openclaw`
- model, channel, plugin, backup, update, and security management
- service status separated from real probe results
- plugin allowlist and pinned-version checks
- support bundle generation for faster debugging

## Current Status

This repository already includes a working shell-based CLI scaffold with real command wiring for:

- OpenClaw install through npm or pnpm global packages
- OpenClaw update through `openclaw update` or package-manager fallback
- plugin install through `openclaw plugins install`
- JSON-backed config validation with `jq`
- channel template seeding and required-field checks
- doctor and security reports

## Quick Start

### Step 1: Install OpenClaw

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

### Step 2: Initialize Configuration

Generate the base configuration files under `~/.simple-openclaw/config/`.

```bash
./bin/simple-openclaw init
```

### Step 3: Configure Your Model

Set up the LLM provider. Replace the URL and model name with your own.

```bash
./bin/simple-openclaw model set \
  --base-url https://api.openai.com/v1 \
  --model gpt-4.1

./bin/simple-openclaw secret set model.api_key sk-xxxx
```

### Step 4: Add a Channel

Add a messaging channel (e.g. feishu, qq) and fill in the credentials.

```bash
./bin/simple-openclaw channel add feishu
./bin/simple-openclaw channel edit feishu --set app_id=your-app-id
./bin/simple-openclaw channel edit feishu --set app_secret=your-app-secret
./bin/simple-openclaw channel edit feishu --set verification_token=your-token
```

### Step 5: Install the Channel Plugin

```bash
./bin/simple-openclaw plugin install @openclaw/feishu --pin
```

### Step 6: Run Health Check

Verify everything is configured correctly.

```bash
./bin/simple-openclaw doctor
```

### Step 7: Start the Service

```bash
./bin/simple-openclaw start
./bin/simple-openclaw probe
```

## Command Highlights

```text
simple-openclaw install
simple-openclaw init

simple-openclaw start
simple-openclaw stop
simple-openclaw restart
simple-openclaw status
simple-openclaw probe

simple-openclaw doctor
simple-openclaw doctor --fix

simple-openclaw model set
simple-openclaw model test

simple-openclaw channel add <name>
simple-openclaw channel edit <name> --set <key=value>
simple-openclaw channel test <name>

simple-openclaw plugin install <pkg> [--pin]
simple-openclaw plugin audit
simple-openclaw plugin doctor

simple-openclaw backup create
simple-openclaw restore <file>
simple-openclaw rollback <snapshot-id>

simple-openclaw update
simple-openclaw update --target <ver>

simple-openclaw security audit
simple-openclaw security harden

simple-openclaw support-bundle
```

## Design Principles

- Keep the official OpenClaw runtime underneath
- reduce onboarding questions to the minimum
- separate desired service state from actual probe state
- prefer explicit safety checks over silent magic
- make rollback and diagnostics first-class features
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
  config/
  backups/
  logs/
  cache/
  snapshots/
  reports/
  state/
```

## Who This Is For

- users who want OpenClaw without a complex manual setup
- operators who need a predictable wrapper for health checks and recovery
- teams who want safer plugin and channel management

## Roadmap

### v2.0

- install / init
- model / channel / plugin flows
- start / stop / status / probe
- doctor / doctor --fix
- backup / restore / rollback
- update / release
- security / repair
- logs / support-bundle

### v2.1

- watchdog
- secret rotation
- multi-profile environments
- TUI management menu

### v2.2

- web admin UI
- remote machine health checks
- centralized alerting

## Notes

- `install` auto-installs Node.js 22+ if missing (supports GLIBC 2.17+ via unofficial-builds)
- `install` auto-installs build tools (cmake, g++, make) based on your OS
- native modules like `node-llama-cpp` may fail to compile on older systems; this is non-blocking — OpenClaw works fine with remote API providers
- the wrapper currently uses shell scripts for speed and portability
- if `openclaw` is not on `PATH`, you can still set `OPENCLAW_BIN` manually
- configuration lives in `~/.simple-openclaw`, not in the repository

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

If you want OpenClaw to feel more like a product than a raw toolkit, this project is pointed in that direction.
