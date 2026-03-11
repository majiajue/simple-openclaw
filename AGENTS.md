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

Direct commands `chat`, `tui`, and `agent` bypass module dispatch — they locate a working Node.js binary via `find_working_node()` and run the `openclaw` npm binary directly with `exec $node_bin $openclaw_bin <command>` to avoid shebang issues on old GLIBC systems.

### Shared library (`lib/common.sh`)

All global variables, path constants, and utility functions live here. Every module sources it transitively through the entrypoint. Key conventions:

- Logging: `info`, `warn`, `die` (the latter exits with code 1).
- JSON manipulation: `json_get` / `json_set_inplace` wrappers around `jq`.
- Environment config: `env_get` / `env_set` read/write a key=value flat file at `$CONFIG_DIR/env`.
- Plugin state: pipe-delimited flat file (`$PLUGIN_DB_FILE`) with `plugin_upsert`, `plugin_get`, `plugin_remove`, plus `refresh_plugin_json` to regenerate a JSON view.
- Service state: `write_service_state`, `write_probe_state` write structured JSON to `$STATE_DIR`.
- Dry-run support: `run_cmd` checks `SIMPLE_OPENCLAW_DRY_RUN` and prints instead of executing.
- PATH management: `/usr/local/bin` is prepended to `$PATH` at load time so auto-installed Node.js and CMake are found first.

#### Node.js auto-installation (`auto_install_node`)

Downloads official Node.js binaries to `/usr/local`. On systems with GLIBC < 2.28, it downloads from `unofficial-builds.nodejs.org` (the `glibc-217` variant). After install, broken `/usr/bin/node` binaries are replaced with a symlink to `/usr/local/bin/node`.

#### Working Node.js discovery (`find_working_node`)

Checks `/usr/local/bin/node` first, then `/usr/bin/node`, then `$PATH`. Returns the first binary that can successfully run `node -v`. Used by `chat`/`tui`/`agent` to bypass broken `#!/usr/bin/env node` shebangs.

#### OS-aware build tool installation (`ensure_build_tools`)

`detect_distro()` identifies the Linux family (debian/rhel/alpine/arch/suse) or macOS. Per-distro handlers install the correct packages:
- **Debian/Ubuntu**: `build-essential`, `python3`, `git`, `jq`
- **RHEL/CentOS/Fedora**: `gcc-c++`, `make`, `python3`, `git`, `jq`
- **Alpine**: `build-base`, `python3`, `git`, `jq`
- **Arch**: `base-devel`, `python`, `git`, `jq`
- **SUSE**: `gcc-c++`, `make`, `python3`, `git`, `jq`
- **macOS**: Xcode CLT + Homebrew packages

`install_cmake_binary()` downloads CMake 3.28.6 from GitHub when the system CMake is too old (< 3.19, required by node-llama-cpp).

### Module conventions

Each `lib/<module>.sh` file exports exactly one public function: `simple_openclaw_<module>`. That function parses its own subcommands and options. Modules should not define global variables beyond what `common.sh` provides.

### OpenClaw config generation

#### `init.sh`
Generates `~/.openclaw/openclaw.json` with `gateway.mode=local` and workspace path if it doesn't exist.

#### `model.sh` — `sync_openclaw_model_config()`
Writes the complete model/provider config into `~/.openclaw/openclaw.json`. Key behaviors:
- **Reuses existing providers**: If `openclaw.json` already has a custom provider (e.g. from `openclaw onboard`), `model set` updates that provider instead of creating a conflicting new one.
- **Generates provider slug**: For new setups, creates a provider ID like `custom-pikachu-claudecode-love` from the base URL.
- **Writes full provider structure**: `baseUrl`, `apiKey`, `api` (anthropic-messages or openai-chat), `auth: api-key`, `models` array (with `id`, `name`, `reasoning`, `input`, `contextWindow`, `maxTokens`), and `auth.profiles` entry.
- **API compatibility**: Detects `anthropic-messages` vs `openai-chat` based on `--provider` flag.

#### `secret.sh`
- Writes API key to `~/.simple-openclaw/secrets.json` and `~/.openclaw/.env`.
- After setting `model.api_key`, triggers `sync_openclaw_model_config()` to sync the key into `openclaw.json`.

### State separation

The project deliberately separates *desired* service state (what the user requested) from *runtime* state (what is actually running). `service.sh` records desired state via `write_service_state` while `service_detect_runtime` checks actual port/PID status independently. `doctor.sh` and `probe.sh` compare these two to surface drift.

### Plugin governance

Plugins are tracked in a pipe-delimited DB (`package|enabled|version|pinned`). A `policy.json` file provides an allowlist. `plugin audit` checks each installed plugin against the allowlist and pinning policy. `plugin doctor` checks for duplicate records and invalid state.

### npm install strategy

Install uses `npm install -g --ignore-scripts` followed by a separate non-blocking `npm rebuild`. This avoids hard failures from native modules (koffi, node-llama-cpp) on systems with old GLIBC or missing build tools. OpenClaw still works for remote API providers without native modules.

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
| `OPENCLAW_MODEL_BASE_URL` | Model provider base URL (stored in env file) |
| `OPENCLAW_MODEL_NAME` | Model name, e.g. `claude-opus-4-6` (stored in env file) |
| `OPENCLAW_MODEL_PROVIDER` | Provider type: `anthropic`, `openai`, or custom (stored in env file) |
| `OPENCLAW_MODEL_API_COMPAT` | API compatibility: `anthropic-messages` or `openai-chat` (stored in env file) |

## Common Issues on Old GLIBC Systems (< 2.28)

- **Node.js GLIBC errors**: `auto_install_node` downloads `unofficial-builds.nodejs.org` glibc-217 variant automatically.
- **`#!/usr/bin/env node` resolves to broken binary**: `chat`/`tui`/`agent` bypass shebang via `exec $node_bin $openclaw_bin`.
- **`/usr/bin/node` broken after install**: `auto_install_node` replaces it with symlink to `/usr/local/bin/node`.
- **CMake too old for node-llama-cpp**: `install_cmake_binary` downloads CMake 3.28.6 from GitHub.
- **npm postinstall failures**: `--ignore-scripts` + non-blocking `npm rebuild` prevents hard failures.

## Shell Conventions

- All scripts use `set -euo pipefail`.
- `jq` is required for most config and state operations; `require_jq` gates commands that need it.
- Node.js 22+ is required at install time (auto-installed if missing).
- The version is stored in the `version` file at the repo root (currently `2.0.0-dev`).
- `/usr/local/bin` is always prepended to `$PATH` in `common.sh`.
