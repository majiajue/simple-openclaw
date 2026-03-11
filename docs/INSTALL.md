# Install

Bootstrap the runtime scaffold:

```bash
./bin/simple-openclaw install --channel stable
./bin/simple-openclaw init
```

Then configure the gateway command and secrets:

```bash
./bin/simple-openclaw secret set model.api_key sk-xxxx
./bin/simple-openclaw model set --base-url https://api.openai.com/v1 --model gpt-4.1
```

If OpenClaw is not on `PATH`, set one of these in `~/.simple-openclaw/config/env`:

```bash
OPENCLAW_BIN=/absolute/path/to/openclaw
OPENCLAW_GATEWAY_CMD=/absolute/path/to/openclaw gateway
```

`install` requires Node.js 22+ and npm. `doctor --fix` will harden file permissions and clear stale tracked PID state.

The wrapper installs OpenClaw through the official npm/pnpm global flow:

```bash
npm install -g openclaw@latest
# or
pnpm add -g openclaw@latest
```

You can override the package manager or npm package in `~/.simple-openclaw/config/env`:

```bash
OPENCLAW_PACKAGE_MANAGER=npm
OPENCLAW_NPM_PACKAGE=openclaw
OPENCLAW_UPDATE_CHANNEL=stable
```
