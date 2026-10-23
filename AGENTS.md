# AGENTS.md

Rules for automated contributors working in this repository. The project is a single-shot
backup container: one POSIX `sh` script, one `Dockerfile`, one workflow, two mirrored docs.

## Ground rules

- **Never push to `main`.** Branch, commit, open a PR, and let the maintainer review and merge.
- One topic per PR, small diffs. A fix that needs a second unrelated change is two PRs.
- Commits, PR bodies, code comments and repository documentation are **English**. Only the
  conversation with the maintainer is German.
- PR body structure: *Why* → *What changed* → *Verification* → *Out of scope*. In *Verification*
  state what was actually executed, and say plainly what could not be executed here.

## Layout

| Path | Purpose |
|------|---------|
| `export-and-upload.sh` | The entire job: validate config, `bw` login/unlock/export, optional `.7z`, `rclone` upload, retention. |
| `Dockerfile` | Pinned base images, non-root user `app` (uid/gid `10001`, `HOME=/home/app`). |
| `tests/harness.sh`, `tests/shims/` | The smoke-test suite and its `bw`/`7z`/`rclone` stand-ins. |
| `.github/workflows/build.yml` | PR build + smoke test + harness; publish on `main` (`:dev`) and `v*` (`vX.Y.Z`, `vX.Y`, `latest`). |
| `README.md`, `DOCKERHUB.md` | Mirrored documentation — see *Documentation* below. |

## Behaviour contract

These properties are what the tests encode. Do not weaken them to make something pass:

- **Exit `0`** means the backup is in the destination. A failing retention/cleanup step prints a
  warning and still exits `0` — it must not turn a good backup into a failed run.
- **Exit `1`** means no backup was uploaded (config validation, login, unlock, export, validation
  or upload failed).
- **Retention must never delete the file written by the current run**, regardless of what
  modification time the remote reports. Both `.json` and `.7z` backups are rotated in one pass.
- The exported JSON is **parsed** (`node`) before upload and must contain an `items` array; an
  empty vault is a warning, not an error. In archive mode the `.7z` is verified with `7z t`.
- `CLEANUP_MIN_AGE` must match `<number><unit>` (`30d`, `12h`, `1w`) and is validated **before**
  any network call.
- The plaintext export goes to `/tmp` with `umask 077` and is removed after archiving — that is a
  normal `rm`, never describe it as a secure erase.

## Portability

- The script runs under BusyBox `ash` in the image: **POSIX `sh` only**. No `[[ ]]`, no arrays, no
  `pipefail`, no `set -o`.
- `shellcheck -S style export-and-upload.sh tests/harness.sh tests/shims/*` must stay clean apart
  from the two known SC2155/SC2046 notes on the `bw unlock` line. That `export VAR=$(…)` masking is
  deliberate: it lets the script print its own "Unlock failed" message.
- `actionlint` on `.github/workflows/build.yml` must stay clean.

## Before opening a PR

```bash
sh tests/harness.sh          # 43 assertions, needs node; retention cases skip without rclone
sh -n export-and-upload.sh
shellcheck -S style export-and-upload.sh
```

- If the harness itself changed, check that it still **fails** on a deliberately broken script.
- If `Dockerfile` or the workflow changed, read the PR's CI run to completion: it builds the image
  and runs the harness *inside* it, which is the only real proof that the image still works.

## Dependencies

- Pins live in `Dockerfile`: `node:26.12-alpine`, `rclone/rclone:1.75.2` and
  `@bitwarden/cli@2026.10.0`.
- rclone is consumed through a **`FROM … AS rclone` stage**, not `COPY --from=rclone/rclone:tag`:
  Dependabot only tracks `FROM` lines. Do not "simplify" it back.
- Dependabot (`.github/dependabot.yml`) covers the `docker` ecosystem weekly, grouped. The CLI pin
  sits inside a `npm install -g` line and is invisible to it — bump it by hand, and verify the
  flags the script uses against the new binary (`config server`, `login --apikey`,
  `unlock --passwordenv … --raw`, `export --output … --format json --session …`, `logout`).

## Documentation

- `README.md` and `DOCKERHUB.md` mirror these sections: intro, *Features*, *Requirements*,
  *Image tags*, *Environment Variables*, *What a run does*, *Security Considerations*,
  *AI Disclosure*. Patch **both**, and prove the shared sections identical:
  `diff <(sed -n '/^## Features/,/^## /p' README.md) <(sed -n '/^## Features/,/^## /p' DOCKERHUB.md)`
- Every documented command must actually run: extract the ```bash blocks, `sh -n` them, and execute
  the `docker run` blocks against a stub `docker` that prints its argv. A `#` comment inside a
  backslash continuation silently truncates the command.
- The *AI Disclosure* must stay true: name the assistant you actually use, and update the section in the same PR if the wording stops matching reality.
- Copying `DOCKERHUB.md` into the Docker Hub description is a manual step for the maintainer.
- `.dockerignore` is not `.gitignore`: it only keeps files out of the build context.

## Security

- Never commit secrets, tokens, vault exports, real hostnames or `.env` files.
- Keep `USER app` and `HOME=/home/app`: the Bitwarden CLI writes its session/config there.
- Docker Hub publishing uses the repository secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`;
  GHCR uses the built-in `GITHUB_TOKEN`. Never echo them, never ask for them in chat.
