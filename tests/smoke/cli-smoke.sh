#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOME_DIR="$(mktemp -d)"
FAKE_BIN_DIR="$(mktemp -d)"
FAKE_LOG="$HOME_DIR/fake-exec.log"
export HOME="$HOME_DIR"
export SIMPLE_OPENCLAW_HOME="$HOME_DIR/.simple-openclaw"
export PATH="$FAKE_BIN_DIR:$PATH"

cat >"$FAKE_BIN_DIR/npm" <<EOF
#!/usr/bin/env bash
echo "npm \$*" >>"$FAKE_LOG"
exit 0
EOF

cat >"$FAKE_BIN_DIR/openclaw" <<EOF
#!/usr/bin/env bash
echo "openclaw \$*" >>"$FAKE_LOG"
if [[ "\$1" == "update" ]]; then
  exit 0
fi
if [[ "\$1" == "plugins" && "\$2" == "install" ]]; then
  exit 0
fi
if [[ "\$1" == "gateway" ]]; then
  exit 0
fi
exit 0
EOF

chmod +x "$FAKE_BIN_DIR/npm" "$FAKE_BIN_DIR/openclaw"

"$ROOT_DIR/bin/simple-openclaw" install --channel stable >/dev/null
"$ROOT_DIR/bin/simple-openclaw" init >/dev/null
"$ROOT_DIR/bin/simple-openclaw" model set --base-url https://example.com/v1 --model test-model >/dev/null
"$ROOT_DIR/bin/simple-openclaw" channel add feishu >/dev/null
"$ROOT_DIR/bin/simple-openclaw" channel edit feishu --set app_id=test-app >/dev/null
"$ROOT_DIR/bin/simple-openclaw" channel edit feishu --set app_secret=test-secret >/dev/null
"$ROOT_DIR/bin/simple-openclaw" channel edit feishu --set verification_token=test-token >/dev/null
"$ROOT_DIR/bin/simple-openclaw" plugin install @openclaw/feishu --pin >/dev/null
"$ROOT_DIR/bin/simple-openclaw" plugin enable @openclaw/feishu >/dev/null
"$ROOT_DIR/bin/simple-openclaw" plugin pin @openclaw/feishu@1.2.3 >/dev/null
"$ROOT_DIR/bin/simple-openclaw" secret set model.api_key test-key >/dev/null
"$ROOT_DIR/bin/simple-openclaw" channel test feishu >/dev/null
"$ROOT_DIR/bin/simple-openclaw" security audit >/dev/null
"$ROOT_DIR/bin/simple-openclaw" update >/dev/null
"$ROOT_DIR/bin/simple-openclaw" backup create >/dev/null
"$ROOT_DIR/bin/simple-openclaw" doctor >/dev/null

grep -q "npm install -g openclaw@latest" "$FAKE_LOG"
grep -q "openclaw plugins install @openclaw/feishu --pin" "$FAKE_LOG"
grep -q "openclaw update --channel stable" "$FAKE_LOG"

echo "smoke=ok"
