# Security

## Overview

`simple-openclaw` provides a multi-layered security system to protect your deployment:

- File permission enforcement
- Secret leak detection and redaction
- API key validation
- Network binding audit
- Plugin policy governance
- Plugin source code scanning
- Config integrity verification
- Process security checks

## Security Audit

Run a full security audit:

```bash
./bin/simple-openclaw security audit
```

This checks 8 categories and produces a report saved to `~/.simple-openclaw/reports/security/`.

### What Gets Checked

| Category | Details |
|---|---|
| File Permissions | Config/state/backup dirs should be 700; secrets/env/policy files should be 600; also checks `~/.openclaw/.env` and `openclaw.json` |
| Secret Leak Scan | Scans all log files and config files for plain-text API keys from `secrets.json` |
| API Key Validation | Checks key length (min 10 chars), detects placeholder values like `test-key`, `your-xxx`, `changeme` |
| Network Binding | Detects if the gateway is listening on 0.0.0.0 (all interfaces) instead of 127.0.0.1 |
| Plugin Policy | Checks allowlist for wildcards, version pinning policy, unpinned plugins, unapproved plugins |
| Plugin Security Scan | Static analysis of installed plugin code (see below) |
| Config Integrity | Validates JSON format of secrets.json, policy.json, openclaw.json; scans env file for embedded secrets |
| Process Security | Warns if the gateway process is running as root |

### Verdict

Each audit run produces a summary:

- `status=PASS` -- no issues found
- `status=WARN` -- warnings found (non-critical)
- `status=FAIL` -- critical issues found, action required

## Auto-Hardening

Fix detected security issues automatically:

```bash
./bin/simple-openclaw security harden
```

What it fixes:

- Sets directory permissions to 700 (config, state, backups, snapshots)
- Sets file permissions to 600 (env, secrets.json, policy.json, `~/.openclaw/.env`)
- Redacts leaked API keys found in log files
- Tightens world-readable config files containing API keys

## Plugin Security Scanning

Scan installed plugins for dangerous code patterns before trusting them:

```bash
# Scan all installed plugins
./bin/simple-openclaw plugin scan

# Scan a specific plugin
./bin/simple-openclaw plugin scan @openclaw/feishu
```

### Three-Layer Analysis

**1. Package Metadata**

Checks `package.json` for:

- `preinstall` / `postinstall` hooks that download from the network (`curl`, `wget`, `http`)
- `preinstall` / `postinstall` hooks with suspicious commands (`eval`, `rm -rf`, `chmod 777`)
- Inline code execution in hooks (`node -e`, `python -c`, `bash -c`)
- Package name mismatches (declared name differs from expected -- identity spoofing)
- Typosquatting dependency names (e.g. `crossenv` instead of `cross-env`)
- Excessive dependency count (> 50)

**2. Source Code Analysis**

Scans all `.js` files (up to 200 files, depth 4) for:

| Pattern | Risk Level | Description |
|---|---|---|
| `eval()` / `new Function()` | RISK | Dynamic code execution |
| `child_process` / `exec` / `spawn` | WARN | System command execution |
| Hardcoded IP network requests | WARN | Requests to IP addresses instead of domains |
| System path writes | RISK | `writeFileSync` to `/etc`, `/usr`, `/bin` |
| Crypto mining indicators | RISK | `stratum+tcp`, `coinhive`, `xmrig`, `mining pool` |
| Environment exfiltration | RISK | `JSON.stringify(process.env)` combined with send/post |
| Code obfuscation | WARN | Hex/unicode escape sequences, base64 decoding |

**3. Permissions & Binaries**

- Native binary modules (`.node`, `.so`, `.dylib`, `.dll`)
- Unexpected executable files outside `bin/`
- setuid/setgid files (critical security risk)

### Verdicts

Each plugin receives one of three verdicts:

- **CLEAN** -- no risks or warnings found
- **REVIEW_RECOMMENDED** -- warnings found, manual review advised
- **DANGEROUS** -- critical risks found, do not enable without investigation

## Plugin Policy

The policy file at `~/.simple-openclaw/config/policy.json` controls:

```json
{
  "plugins": {
    "allow": ["@openclaw/feishu", "qqbot"],
    "pinVersions": true
  }
}
```

- `allow` -- whitelist of permitted plugin packages (no wildcards)
- `pinVersions` -- require all plugins to be pinned to specific versions

Check compliance with:

```bash
./bin/simple-openclaw plugin audit
```

## Best Practices

1. Always run `security audit` after initial setup
2. Run `security harden` to auto-fix permission issues
3. Run `plugin scan` before enabling any new plugin
4. Keep `pinVersions: true` in your policy
5. Never add `"*"` to the plugin allowlist
6. Review `plugin scan` output for any RISK findings before enabling a plugin
7. Avoid running the gateway as root
8. Bind the gateway to `127.0.0.1` instead of `0.0.0.0` unless external access is required
