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

## Open questions after first Mac boot

- Confirm vfkit keeps running across the installer-triggered guest reboot. This
  is expected from the devhost experience but needs first Mocker verification.
- Confirm the fourth virtio-blk device (job ISO) does not perturb the empirical
  OS/data by-path assignments from the devhost launcher.
- Confirm `hdiutil makehybrid -default-volume-name MOCKER_JOB` produces the
  Linux by-label path `/dev/disk/by-label/MOCKER_JOB` under NixOS.
- Decide whether to add a debug `mocker up` mode or keep debugging via long-lived
  jobs such as `mocker run -- sleep infinity`.
