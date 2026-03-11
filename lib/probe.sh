#!/usr/bin/env bash

simple_openclaw_probe() {
  local port endpoints endpoint http_code
  port="$(gateway_port)"
  endpoints=("/health" "/api/health" "/")

  if command_exists curl; then
    for endpoint in "${endpoints[@]}"; do
      http_code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 "http://127.0.0.1:${port}${endpoint}" || true)"
      if [[ "$http_code" =~ ^[234][0-9][0-9]$ ]] && [[ "$http_code" != "000" ]]; then
        write_probe_state "ok" "HTTP probe returned ${http_code} on ${endpoint}" "$endpoint"
        printf 'probe=ok port=%s endpoint=%s http_code=%s\n' "$port" "$endpoint" "$http_code"
        return 0
      fi
    done
  fi

  if command_exists nc && nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
    write_probe_state "degraded" "TCP port ${port} is listening but HTTP probe failed" ""
    printf 'probe=degraded port=%s\n' "$port"
    return 0
  fi

  write_probe_state "failed" "no listener detected on port ${port}" ""
  printf 'probe=failed port=%s\n' "$port"
  return 1
}
