# Mocker journal

Mocker is a Mac-hosted, Docker-run-shaped execution primitive: the Mac runner
launches a one-shot Linux ARM VM, the guest executes an argv array, emits a
structured serial result, and powers off.

## Decisions

- The Mac is the only scheduler-visible runner. Linux ARM execution inside a
  VM is an implementation detail of a Mac runner task, not a second independent
  Gitea runner.
- The host/guest input boundary is a read-only seed ISO containing `job.json`.
- `job.json` carries Docker-style argv, not a CI DSL. Persistence/hermeticity is
  expressed by Docker args such as `-v /ci/cargo:/cargo`; Mocker does not invent
  separate cache policy syntax.
- Workload artifacts/results are workload-owned. The container should upload its
  own outputs. Mocker's return channel is only the serial `MOCKER_RESULT` line,
  used to map guest workload exit status back to the host process.
- The appliance ISO is closure-baked. The installed NixOS system closure is
  included in `isoImage.storeContents`, and the installer uses
  `nixos-install --system`, so first install does not depend on GitHub, network,
  or guest-side flake evaluation.
- Persistent VM state lives on a separate `/ci` disk. Docker's `data-root` is
  `/ci/docker`; OS disk state is disposable.
- Debug SSH is localhost-only through gvproxy. It is a debugging affordance, not
  part of the job protocol.

## Current v0 falsifier

```sh
mocker run -- docker run --rm hello-world
```

Expected behavior:

1. host writes `job.json` to a seed ISO labelled `MOCKER_JOB`;
2. vfkit boots the VM with OS disk, `/ci` disk, appliance ISO, and job ISO;
3. installer converges the OS disk from the closure-baked ISO if needed;
4. installed guest initializes/mounts `/ci`, starts Docker, runs argv;
5. guest prints `MOCKER_RESULT { ... "exit_code": N ... }` to serial;
6. guest powers off;
7. host parses the sentinel and exits with `N`.

Observed result, 2026-05-16: `hello-world` works. This proves the closure-baked
ISO, installer path, vfkit boot, job seed ISO, Docker daemon/client path, and
guest poweroff loop are all fundamentally alive.

Two follow-up fixes came from the first real run:

- Serial output is journal/kernel prefixed, e.g.
  `[   17.055058] mocker-run-job[1328]: MOCKER_RESULT ...`, so host parsing must
  search for `MOCKER_RESULT ` anywhere in a line rather than anchoring at column
  zero.
- Wipe cannot depend on SSH. One-shot jobs usually power off quickly, and debug
  SSH is not part of the job protocol. Host wipe now zeros signatures in the raw
  host disk images directly: `wipe-os` wipes only `os.img`; `wipe-data` wipes
  only `ci.img`.

Release note: `v0.1.0` was pushed to GitHub to trigger the release workflow,
which should build `mocker-mac.iso` on `ubuntu-24.04-arm` and attach the ISO plus
SHA256 to a GitHub Release.

## Open questions after first Mac boot

- Watch the `v0.1.0` GitHub Release build and confirm the release artifact is
  attached, not merely uploaded as a workflow artifact.
- Decide whether to add a debug `mocker up` mode or keep debugging via long-lived
  jobs such as `mocker run -- sleep infinity`.
