#!/usr/bin/env bash
set -euo pipefail

# Mocker host-side launcher for Apple Silicon.
#
# The host creates a small per-run seed ISO containing /job.json, boots a
# NixOS appliance VM with vfkit, streams the guest serial log, waits for the
# guest to power off, and maps the structured MOCKER_RESULT sentinel to this
# process' exit code.

STATE_DIR="${MOCKER_STATE:-$HOME/.local/share/mocker}"
OS_DISK="$STATE_DIR/os.img"
CI_DISK="$STATE_DIR/ci.img"
ISO_DIR="$STATE_DIR/iso"
ISO_PATH="$ISO_DIR/mocker-mac.iso"
EFI_STORE="$STATE_DIR/efi-vars"
GVPROXY_SOCK="$STATE_DIR/gvproxy.sock"
GVPROXY_LOG="$STATE_DIR/gvproxy.log"
GVPROXY_PID="$STATE_DIR/gvproxy.pid"
JOBS_DIR="$STATE_DIR/jobs"

OS_DISK_SIZE="${MOCKER_OS_SIZE:-24G}"
CI_DISK_SIZE="${MOCKER_CI_SIZE:-200G}"
VCPUS="${MOCKER_VCPUS:-8}"
MEMORY_MIB="${MOCKER_MEMORY:-16384}"
SSH_USER="${MOCKER_SSH_USER:-dany}"
SSH_PORT="${MOCKER_SSH_PORT:-2223}"

die() { echo "mocker: $*" >&2; exit 1; }
log() { echo "mocker: $*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

make_sparse_file() {
  local size="$1"
  local path="$2"
  if command -v mkfile >/dev/null 2>&1; then
    mkfile -n "$size" "$path"
  else
    truncate -s "$size" "$path"
  fi
}

cmd_create() {
  mkdir -p "$STATE_DIR" "$ISO_DIR" "$JOBS_DIR"
  if [[ -e "$OS_DISK" || -e "$CI_DISK" ]]; then
    die "disks already exist at $STATE_DIR; run 'destroy' first if intentional"
  fi
  make_sparse_file "$OS_DISK_SIZE" "$OS_DISK"
  make_sparse_file "$CI_DISK_SIZE" "$CI_DISK"
  log "created $OS_DISK ($OS_DISK_SIZE) and $CI_DISK ($CI_DISK_SIZE)"
  log "place the appliance ISO at: $ISO_PATH"
}

cmd_status() {
  if [[ ! -d "$STATE_DIR" ]]; then
    echo "no state at $STATE_DIR"
    return
  fi
  echo "state dir: $STATE_DIR"
  find "$STATE_DIR" -maxdepth 2 -mindepth 1 -print | sort | sed 's/^/  /'
}

cmd_destroy() {
  [[ -d "$STATE_DIR" ]] || die "no state dir at $STATE_DIR"
  read -r -p "Destroy $STATE_DIR (disks + EFI vars + ISOs + jobs)? type 'destroy': " confirm
  [[ "$confirm" == "destroy" ]] || die "aborted"
  rm -rf "$STATE_DIR"
  log "destroyed $STATE_DIR"
}

write_job_json() {
  local job_id="$1"
  shift
  local seed_dir="$1"
  shift
  jq -n \
    --arg job_id "$job_id" \
    '{version: 1, job_id: $job_id, argv: $ARGS.positional}' \
    --args -- "$@" > "$seed_dir/job.json"
}

make_seed_iso() {
  local seed_dir="$1"
  local out_iso="$2"
  rm -f "$out_iso"
  if command -v hdiutil >/dev/null 2>&1; then
    hdiutil makehybrid -iso -joliet -default-volume-name MOCKER_JOB -o "$out_iso" "$seed_dir" >/dev/null
  else
    die "hdiutil not found; seed ISO creation currently expects macOS"
  fi
}

start_gvproxy() {
  if [[ -f "$GVPROXY_PID" ]] && kill -0 "$(cat "$GVPROXY_PID")" 2>/dev/null; then
    die "gvproxy already running with pid $(cat "$GVPROXY_PID"); stop the old VM first"
  fi
  rm -f "$GVPROXY_SOCK" "$GVPROXY_PID"

  log "starting gvproxy (host 127.0.0.1:$SSH_PORT -> guest :22)"
  gvproxy \
    --mtu 1500 \
    --ssh-port "$SSH_PORT" \
    --listen-vfkit "unixgram://$GVPROXY_SOCK" \
    --log-file "$GVPROXY_LOG" \
    --pid-file "$GVPROXY_PID" &
  GVPROXY_CHILD=$!

  for _ in $(seq 1 50); do
    if [[ -e "$GVPROXY_SOCK" ]]; then
      return 0
    fi
    if ! kill -0 "$GVPROXY_CHILD" 2>/dev/null; then
      [[ -f "$GVPROXY_LOG" ]] && tail -50 "$GVPROXY_LOG" >&2 || true
      die "gvproxy exited before creating $GVPROXY_SOCK"
    fi
    sleep 0.1
  done
  [[ -f "$GVPROXY_LOG" ]] && tail -50 "$GVPROXY_LOG" >&2 || true
  die "timed out waiting for gvproxy socket $GVPROXY_SOCK"
}

stop_gvproxy() {
  if [[ -n "${GVPROXY_CHILD:-}" ]]; then
    kill "$GVPROXY_CHILD" 2>/dev/null || true
  elif [[ -f "$GVPROXY_PID" ]]; then
    kill "$(cat "$GVPROXY_PID")" 2>/dev/null || true
  fi
  rm -f "$GVPROXY_SOCK" "$GVPROXY_PID"
}

boot_vm() {
  local job_iso="$1"
  local serial_log="$2"
  local gui=0
  if [[ "${MOCKER_GUI:-0}" == "1" ]]; then
    gui=1
  fi

  [[ -e "$OS_DISK" ]] || die "no OS disk; run 'mocker create' first"
  [[ -e "$CI_DISK" ]] || die "no CI disk; run 'mocker create' first"
  [[ -e "$ISO_PATH" ]] || die "no appliance ISO at $ISO_PATH"
  [[ -e "$job_iso" ]] || die "no job seed ISO at $job_iso"

  if [[ ! -e "$EFI_STORE" ]]; then
    log "initializing EFI variable store"
    : > "$EFI_STORE"
  fi

  start_gvproxy
  trap stop_gvproxy EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  : > "$serial_log"
  tail -n 0 -F "$serial_log" &
  local tail_pid=$!

  local gui_args=()
  if (( gui )); then
    gui_args=(--gui)
  fi

  set +e
  vfkit \
    "${gui_args[@]}" \
    --cpus "$VCPUS" \
    --memory "$MEMORY_MIB" \
    --bootloader "efi,variable-store=$EFI_STORE,create" \
    --device "virtio-blk,path=$OS_DISK" \
    --device "virtio-blk,path=$CI_DISK" \
    --device "virtio-blk,path=$ISO_PATH,readonly" \
    --device "virtio-blk,path=$job_iso,readonly" \
    --device "virtio-net,unixSocketPath=$GVPROXY_SOCK,mac=5a:94:ef:e4:0c:ef" \
    --device "virtio-rng" \
    --device "virtio-serial,logFilePath=$serial_log"
  local vfkit_rc=$?
  set -e

  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true
  stop_gvproxy
  trap - EXIT INT TERM

  return "$vfkit_rc"
}

parse_result() {
  local serial_log="$1"
  local result_json
  result_json=$({ grep -a '^MOCKER_RESULT ' "$serial_log" || true; } | tail -1 | sed 's/^MOCKER_RESULT //')
  if [[ -z "$result_json" ]]; then
    log "no MOCKER_RESULT sentinel found in $serial_log"
    return 125
  fi

  if ! jq -e '.version == 1 and .kind == "result" and (.exit_code | type == "number")' >/dev/null <<<"$result_json"; then
    log "invalid MOCKER_RESULT sentinel: $result_json"
    return 125
  fi

  jq . <<<"$result_json" >&2
  local exit_code
  exit_code=$(jq -r '.exit_code' <<<"$result_json")
  return "$exit_code"
}

cmd_run() {
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  [[ $# -gt 0 ]] || die "usage: mocker run -- docker run ..."
  require jq
  require vfkit
  require gvproxy

  local job_id
  job_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  local job_dir="$JOBS_DIR/$job_id"
  local seed_dir="$job_dir/seed"
  local job_iso="$job_dir/job-seed.iso"
  local serial_log="$job_dir/serial.log"
  mkdir -p "$seed_dir"

  write_job_json "$job_id" "$seed_dir" "$@"
  make_seed_iso "$seed_dir" "$job_iso"

  log "job $job_id"
  log "argv: $*"
  log "serial: $serial_log"

  set +e
  boot_vm "$job_iso" "$serial_log"
  local vfkit_rc=$?
  set -e
  if [[ "$vfkit_rc" -ne 0 ]]; then
    log "vfkit exited with $vfkit_rc before/while guest ran"
    return "$vfkit_rc"
  fi

  parse_result "$serial_log"
}

cmd_ssh() {
  exec ssh -p "$SSH_PORT" "$SSH_USER@127.0.0.1" "$@"
}

cmd_wipe_os() {
  log "wiping OS disk signature only; /ci data disk is preserved"
  "$0" ssh sudo mocker-wipe --no-reboot
  log "reboot or run the next job to reinstall from ISO"
}

cmd_wipe_data() {
  log "wiping OS and /ci data disk signatures"
  "$0" ssh sudo mocker-wipe --data --no-reboot
  log "reboot or run the next job to reinstall/reinitialize from ISO"
}

usage() {
  cat <<EOF
Mocker — run Docker argv inside a one-shot Linux ARM VM.

Usage:
  mocker create                 allocate OS + /ci disk images
  mocker run -- docker run ...  run a Docker-shaped argv in the VM
  mocker ssh [args...]          SSH to the guest through localhost gvproxy
  mocker status                 show host-side state
  mocker wipe-os                wipe guest OS disk via SSH; preserve /ci
  mocker wipe-data              wipe guest OS and /ci disks via SSH
  mocker destroy                delete all host-side state

State dir: $STATE_DIR
ISO path : $ISO_PATH

Environment overrides:
  MOCKER_STATE, MOCKER_OS_SIZE, MOCKER_CI_SIZE, MOCKER_VCPUS,
  MOCKER_MEMORY, MOCKER_SSH_PORT, MOCKER_GUI=1
EOF
}

case "${1:-}" in
  create) shift; cmd_create "$@" ;;
  run) shift; cmd_run "$@" ;;
  ssh) shift; cmd_ssh "$@" ;;
  status) shift; cmd_status "$@" ;;
  wipe-os) shift; cmd_wipe_os "$@" ;;
  wipe-data) shift; cmd_wipe_data "$@" ;;
  destroy) shift; cmd_destroy "$@" ;;
  ""|-h|--help|help) usage ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
