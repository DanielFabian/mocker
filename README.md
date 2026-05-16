# Mocker

Mocker is a tiny Mac-hosted execution primitive: run a Docker-shaped argv
inside a one-shot Linux ARM VM, then power the VM off.

The Mac remains the scheduler-visible machine. Linux ARM execution is an
implementation detail inside the Mac runner, not a second independent CI
runner competing for the same hardware.

## Contract

```text
host:  mocker run -- docker run --rm hello-world
guest: mount seed ISO, read job.json, run argv, print MOCKER_RESULT, poweroff
host:  parse MOCKER_RESULT from serial log, exit with the workload exit code
```

Artifacts/results belong to the workload. A container can upload to Gitea,
object storage, or a release endpoint itself. Mocker's return channel is only a
structured protocol/logging path so the host can distinguish:

- workload failed;
- appliance/protocol failed;
- VM infrastructure failed.

## Persistence model

Persistence is Docker argv policy, not a separate Mocker DSL.

Warm/leaky run:

```sh
mocker run -- docker run --rm \
  -v /ci/cargo:/cargo \
  -v /ci/target:/target \
  -e CARGO_HOME=/cargo \
  -e CARGO_TARGET_DIR=/target \
  example-builder:latest build
```

Hermetic relative to `/ci`:

```sh
mocker run -- docker run --rm hello-world
```

## Build the appliance ISO

Build this on an `aarch64-linux` builder, such as a Mac-local NixOS devhost VM
or GitHub's `ubuntu-24.04-arm` runner:

```sh
nix build .#mocker-mac-iso
```

Copy the resulting ISO to the Mac at:

```text
~/.local/share/mocker/iso/mocker-mac.iso
```

The ISO is closure-baked: it contains both the installer environment and the
installed appliance system closure. The VM does not need GitHub or flake eval
during install.

GitHub Actions also builds the ISO via `.github/workflows/build-iso.yml`.
Workflow artifacts contain `mocker-mac.iso` and `mocker-mac.iso.sha256`; pushing
a `v*` tag attaches both files to a GitHub Release.

## Run on Apple Silicon

```sh
nix run .#mocker -- create
nix run .#mocker -- run -- docker run --rm hello-world
```

Useful subcommands:

```sh
mocker status
mocker ssh
mocker wipe-os     # host-side wipe of os.img; preserves /ci
mocker wipe-data   # host-side wipe of ci.img; drops Docker/cache state
mocker destroy
```

By default the debug SSH port is localhost-only through gvproxy:

```text
127.0.0.1:2223 -> guest :22
```

## State layout

Host state defaults to:

```text
~/.local/share/mocker/
  os.img
  ci.img
  iso/mocker-mac.iso
  jobs/<job-id>/
    seed/job.json
    job-seed.iso
    serial.log
```

Guest persistent state lives on the data disk mounted at `/ci`:

```text
/ci/docker   # Docker data-root
/ci/cargo
/ci/rustup
/ci/target
/ci/sccache
/ci/logs
/ci/tmp
```
