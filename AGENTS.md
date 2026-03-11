# AGENTS.md

## Project Overview

`simple-openclaw` is a shell-based (Bash) operations wrapper around [OpenClaw](https://docs.openclaw.ai/). It provides a single CLI entrypoint (`bin/simple-openclaw`) for installing, configuring, health-checking, and managing an OpenClaw deployment. All runtime state lives under `~/.simple-openclaw/` (overridable via `SIMPLE_OPENCLAW_HOME`), not in the repository.

## Running Tests

The only existing test is a smoke test:

```bash
bash tests/smoke/cli-smoke.sh
```

It creates a temporary `$HOME` with fake `npm` and `openclaw` binaries, then exercises the full CLI flow (install, init, model, channel, plugin, secret, security, update, backup, doctor). A passing run prints `smoke=ok`. The `tests/channel/`, `tests/plugin/`, and `tests/doctor/` directories are placeholders for future regression tests.

There is no lint, typecheck, or build step. The project is pure Bash.

## Architecture

### CLI dispatch

`bin/simple-openclaw` is the entrypoint. It sources `lib/common.sh`, then dispatches the first argument to a module via `dispatch_module`, which sources `lib/<module>.sh` and calls `simple_openclaw_<module>`. For example, `simple-openclaw channel add feishu` sources `lib/channel.sh` and calls `simple_openclaw_channel add feishu`.

### Shared library (`lib/common.sh`)

All global variables, path constants, and utility functions live here. Every module sources it transitively through the entrypoint. Key conventions:

- Logging: `info`, `warn`, `die` (the latter exits with code 1).
- JSON manipulation: `json_get` / `json_set_inplace` wrappers around `jq`.
- Environment config: `env_get` / `env_set` read/write a key=value flat file at `$CONFIG_DIR/env`.
- Plugin state: pipe-delimited flat file (`$PLUGIN_DB_FILE`) with `plugin_upsert`, `plugin_get`, `plugin_remove`, plus `refresh_plugin_json` to regenerate a JSON view.
- Service state: `write_service_state`, `write_probe_state` write structured JSON to `$STATE_DIR`.
- Dry-run support: `run_cmd` checks `SIMPLE_OPENCLAW_DRY_RUN` and prints instead of executing.

### Module conventions

Each `lib/<module>.sh` file exports exactly one public function: `simple_openclaw_<module>`. That function parses its own subcommands and options. Modules should not define global variables beyond what `common.sh` provides.

### State separation

The project deliberately separates *desired* service state (what the user requested) from *runtime* state (what is actually running). `service.sh` records desired state via `write_service_state` while `service_detect_runtime` checks actual port/PID status independently. `doctor.sh` and `probe.sh` compare these two to surface drift.

### Plugin governance

Plugins are tracked in a pipe-delimited DB (`package|enabled|version|pinned`). A `policy.json` file provides an allowlist. `plugin audit` checks each installed plugin against the allowlist and pinning policy. `plugin doctor` checks for duplicate records and invalid state.

### Hooks

`hooks/` contains lifecycle scripts (`pre-backup.sh`, `post-update.sh`, etc.) that are currently placeholders. They are not yet wired into the command flow.

### Templates

`templates/` holds seed files for channels (`channel.*.json`), base config (`openclaw.base.json`), policy (`policy.json`), env example, secrets example, and a systemd unit file.

## Key Environment Variables

| Variable | Purpose |
|---|---|
| `SIMPLE_OPENCLAW_HOME` | Override runtime directory (default: `~/.simple-openclaw`) |
| `OPENCLAW_BIN` | Explicit path to the `openclaw` binary |
| `OPENCLAW_GATEWAY_PORT` | Gateway port (default: `18789`) |
| `OPENCLAW_GATEWAY_CMD` | Command to start the gateway process |
| `OPENCLAW_PACKAGE_MANAGER` | Force `npm` or `pnpm` |
| `OPENCLAW_NPM_PACKAGE` | Override the npm package name (default: `openclaw`) |
| `OPENCLAW_UPDATE_CHANNEL` | Update channel: `stable`, `beta`, `dev` |
| `SIMPLE_OPENCLAW_DRY_RUN` | Set to `1` to print commands instead of executing |

## Shell Conventions

- All scripts use `set -euo pipefail`.
- `jq` is required for most config and state operations; `require_jq` gates commands that need it.
- Node.js 22+ is required at install time.
- The version is stored in the `version` file at the repo root (currently `2.0.0-dev`).
