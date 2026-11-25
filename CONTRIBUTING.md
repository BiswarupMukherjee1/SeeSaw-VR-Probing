# Contributing

## Branches

| Branch | Purpose |
| --- | --- |
| `main` | Current state of the project: the modular Quest 3 (OpenXR) version plus the desktop prototype |
| `desktop-demo` | Snapshot of the first working desktop prototype (Godot + DINOv2 sidecar) |
| `openxr-quest` | Snapshot of the modular Quest 3 / OpenXR version with desktop fallback |
| `<topic>` | Short-lived branches for a single change, merged into `main` by pull request |

## Pull requests

Keep them small. In the description, link the issue (`Closes #12`) and say how you tested the change
(desktop mode, RGB backend, DINOv2 on CPU or GPU, Quest 3). The template asks for this. CI must be green:
the `CI passed` check summarizes every job.

## CI

CI runs on every pull request and on every push to `main`. It checks:

- no merge conflict markers
- no files larger than 50 MB
- no committed `.godot/` cache, `.env` files or private keys
- both Python sidecars byte-compile (and run `pytest` once a `tests/` folder exists)
- Godot 4.7.2-stable imports both Godot projects (`godot/` and `seesaw_xr/godot/`) headless and parses every `.gd` file without errors

When you add a CI job, add it to the `needs` list of the `CI passed` job.

## Versions

The project uses **Godot 4.7.2-stable** (standard build, not .NET). Opening it in another version rewrites project
and scene files. To change the version, update `GODOT_VERSION` in [.github/workflows/ci.yml](.github/workflows/ci.yml)
and this section in the same pull request.

## Releases

Pushing a tag such as `v0.1.0` on `main` creates a GitHub release with generated notes.
