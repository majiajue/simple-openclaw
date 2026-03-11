# Channels

Supported starter templates:

- `qq`
- `feishu`
- `custom`

Use `simple-openclaw channel add <name>` to seed a config into `~/.simple-openclaw/config/channels/`.

Populate required credentials with:

```bash
./bin/simple-openclaw channel edit feishu --set app_id=xxx
./bin/simple-openclaw channel edit feishu --set app_secret=yyy
./bin/simple-openclaw channel edit feishu --set verification_token=zzz
./bin/simple-openclaw channel test feishu
```

`channel test` validates:

- channel config file exists
- required credentials are not blank
- the bound plugin is present in `policy.json` allowlist
