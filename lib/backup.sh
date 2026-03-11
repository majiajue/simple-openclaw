#!/usr/bin/env bash

simple_openclaw_backup() {
  local action="${1:-list}"
  shift || true

  case "$action" in
    create)
      local name="simple-openclaw-$(timestamp).tar.gz"
      tar -czf "$BACKUP_DIR/$name" -C "$SIMPLE_OPENCLAW_HOME" config state reports >/dev/null 2>&1 || \
        tar -czf "$BACKUP_DIR/$name" -C "$SIMPLE_OPENCLAW_HOME" config state >/dev/null 2>&1
      cp "$BACKUP_DIR/$name" "$SNAPSHOT_DIR/${name}"
      printf '%s\n' "$BACKUP_DIR/$name"
      ;;
    list)
      find "$BACKUP_DIR" -maxdepth 1 -name '*.tar.gz' -type f | sort
      ;;
    verify)
      local archive="${1:-}"
      require_arg "$archive" "backup file"
      tar -tzf "$archive" >/dev/null
      printf 'verify=ok file=%s\n' "$archive"
      ;;
    restore)
      local restore_file="${1:-}"
      require_arg "$restore_file" "backup file"
      tar -xzf "$restore_file" -C "$SIMPLE_OPENCLAW_HOME"
      printf 'restore=ok file=%s\n' "$restore_file"
      ;;
    rollback)
      local snapshot_id="${1:-}"
      require_arg "$snapshot_id" "snapshot id"
      local snapshot_file="$SNAPSHOT_DIR/$snapshot_id"
      [[ -f "$snapshot_file" ]] || die "snapshot not found: $snapshot_id"
      tar -xzf "$snapshot_file" -C "$SIMPLE_OPENCLAW_HOME"
      printf 'rollback=ok snapshot=%s\n' "$snapshot_id"
      ;;
    *)
      die "unknown backup action: $action"
      ;;
  esac
}
