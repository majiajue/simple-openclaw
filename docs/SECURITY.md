# Security

The default policy keeps a plugin allowlist and encourages pinned versions. Run:

```bash
./bin/simple-openclaw security audit
./bin/simple-openclaw security harden
```

The audit currently checks:

- `plugins.allow` exists and is not wildcarded
- `pinVersions` remains enabled
- config and secret file modes are visible
