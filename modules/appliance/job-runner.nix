{ pkgs, lib, ... }:

let
  runner = pkgs.writeShellApplication {
    name = "mocker-run-job";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
      jq
      docker-client
      util-linux
      systemd
    ];
    text = ''
      set -euo pipefail

      seed_label="MOCKER_JOB"
      seed_dev="/dev/disk/by-label/$seed_label"
      seed_mount="/run/mocker-job"
      result_prefix="MOCKER_RESULT "

      log() { echo "mocker-job: $*" >&2; }

      emit_result() {
        local status="$1"
        local exit_code="$2"
        local message="''${3:-}"
        local duration_ms
        duration_ms=$(( $(date +%s%3N) - start_ms ))
        jq -nc \
          --arg job_id "''${job_id:-unknown}" \
          --arg status "$status" \
          --arg message "$message" \
          --argjson exit_code "$exit_code" \
          --argjson duration_ms "$duration_ms" \
          '{version: 1, kind: "result", job_id: $job_id, status: $status, exit_code: $exit_code, duration_ms: $duration_ms} + (if $message == "" then {} else {message: $message} end)' \
          | sed "s/^/$result_prefix/"
      }

      start_ms=$(date +%s%3N)
      job_id="unknown"

      udevadm settle --timeout=30 || true
      for _ in $(seq 1 50); do
        [[ -e "$seed_dev" ]] && break
        sleep 0.1
      done

      if [[ ! -e "$seed_dev" ]]; then
        log "no job seed device at $seed_dev"
        emit_result "missing_seed" 125 "job seed ISO with label $seed_label was not found"
        systemctl poweroff
        exit 0
      fi

      mkdir -p "$seed_mount"
      mount -o ro "$seed_dev" "$seed_mount"

      job_json="$seed_mount/job.json"
      if [[ ! -r "$job_json" ]]; then
        emit_result "invalid_job" 64 "job.json missing from seed ISO"
        systemctl poweroff
        exit 0
      fi

      job_id=$(jq -r '.job_id // "unknown"' "$job_json")
      if ! jq -e '.version == 1 and (.argv | type == "array") and (.argv | length > 0) and all(.argv[]; type == "string")' "$job_json" >/dev/null; then
        emit_result "invalid_job" 64 "job.json must contain {version:1, argv:[strings...]}"
        systemctl poweroff
        exit 0
      fi

      mapfile -t argv < <(jq -r '.argv[]' "$job_json")
      log "job_id=$job_id"
      printf 'mocker-job: argv:' >&2
      printf ' %q' "''${argv[@]}" >&2
      printf '\n' >&2

      set +e
      "''${argv[@]}"
      rc=$?
      set -e

      emit_result "exited" "$rc"
      sync
      systemctl poweroff
      exit 0
    '';
  };
in
{
  environment.systemPackages = [ runner ];

  systemd.services.mocker-job = {
    description = "Run one Mocker job from the attached seed ISO, then power off";
    wantedBy = [ "multi-user.target" ];
    after = [
      "local-fs.target"
      "network-online.target"
      "docker.service"
    ];
    wants = [
      "network-online.target"
      "docker.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${runner}/bin/mocker-run-job";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
      TimeoutStartSec = "0";
    };
  };
}
