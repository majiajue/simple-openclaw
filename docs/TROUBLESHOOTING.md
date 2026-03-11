# Troubleshooting

Recommended flow:

1. `simple-openclaw status`
2. `simple-openclaw probe`
3. `simple-openclaw doctor`
4. `simple-openclaw plugin audit`
5. `simple-openclaw repair port`

Useful interpretation:

- `status` is desired state plus actual listener/PID state.
- `probe` is the real reachability check and tries `/health`, `/api/health`, then `/`.
- `doctor --fix` clears stale tracked PID files when there is no live listener.
