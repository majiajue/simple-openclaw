#!/usr/bin/env bash

simple_openclaw_bundle() {
  local output="$BUNDLE_REPORT_DIR/support-bundle-$(timestamp).tar.gz"
  tar -czf "$output" -C "$SIMPLE_OPENCLAW_HOME" config state logs reports >/dev/null 2>&1 || \
    tar -czf "$output" -C "$SIMPLE_OPENCLAW_HOME" config state logs >/dev/null 2>&1
  printf '%s\n' "$output"
}
