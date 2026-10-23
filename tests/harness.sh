#!/bin/sh
# Smoke tests for export-and-upload.sh.
#
# No Vaultwarden instance and no cloud storage are involved: `bw` and `7z` are
# replaced by tests/shims, rclone runs for real when it is installed (so the
# retention assertions use rclone's own --min-age/--filter behaviour).
#
# Usage: sh tests/harness.sh      (from anywhere; exits non-zero on failure)
set -u

TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(dirname -- "$TESTS_DIR")
SCRIPT="$REPO_DIR/export-and-upload.sh"
SHIMS="$TESTS_DIR/shims"

WORK="${TMPDIR:-/tmp}/vaultwarden-export-rclone-tests.$$"
mkdir -p "$WORK/home" "$WORK/tmp" "$WORK/cwd" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

PATH="$SHIMS:$PATH"
export PATH

if ! command -v node >/dev/null 2>&1; then
    echo "FATAL: node is required (the script validates the export with it)" >&2
    exit 1
fi

# A real rclone binary (not another script) is needed for the retention cases,
# because they rely on rclone's own --min-age/--filter behaviour.
have_real_rclone=0
old_ifs=$IFS; IFS=:
for dir in $PATH; do
    case "$dir" in ""|"$SHIMS") continue ;; esac
    bin="$dir/rclone"
    [ -f "$bin" ] && [ -x "$bin" ] || continue
    [ "$(head -c 2 "$bin" 2>/dev/null)" = "#!" ] && continue
    have_real_rclone=1; break
done
IFS=$old_ifs

pass=0; fail=0; skipped=0
rc=0; out=""

ok()    { pass=$((pass + 1)); printf 'ok    %s\n' "$1"; }
bad()   { fail=$((fail + 1)); printf 'FAIL  %s: %s\n' "$1" "$2"; }
skip()  { skipped=$((skipped + 1)); printf 'skip  %s (%s)\n' "$1" "$2"; }

# names of the export files the script writes to /tmp and must clean up again
leftover_exports() {
    for f in /tmp/vault-export-*; do
        [ -e "$f" ] || continue
        basename "$f"
    done
}

# run <name> <dest> [VAR=VALUE ...] -- runs the script, sets $rc and $out
run() {
    name=$1; dest=$2; shift 2
    logfile="$WORK/log-$(printf '%s' "$name" | tr ' /' '__')"
    : > "$logfile"
    before=$(leftover_exports)
    # run from a throwaway directory: rclone creates relative destinations there
    (
      cd "$WORK/cwd" || exit 1
      env -i PATH="$PATH" HOME="$WORK/home" LOG="$logfile" \
          BW_HOST=https://vault.example.com \
          BW_CLIENTID=user.test \
          BW_CLIENTSECRET=secret \
          BW_PASSWORD=master \
          RCLONE_DEST="$dest" \
          "$@" sh "$SCRIPT" > "$WORK/out.log" 2>&1
    )
    rc=$?
    out=$(cat "$WORK/out.log")
    after=$(leftover_exports)
    if [ "$before" != "$after" ]; then
        bad "$name" "left plaintext export files in /tmp: $(printf '%s' "$after" | tr '\n' ' ')"
    fi
}

expect_rc() { # <name> <expected>
    if [ "$rc" -eq "$2" ]; then ok "$1: exit $rc"; else bad "$1" "exit $rc, expected $2"; fi
}
expect_files() { # <name> <dest> <expected count>
    n=0
    for f in "$2"/*; do [ -e "$f" ] && n=$((n + 1)); done
    if [ "$n" -eq "$3" ]; then ok "$1: $n file(s) in destination"; else bad "$1" "expected $3 file(s) in destination, found $n"; fi
}
expect_present() { # <name> <path>
    if [ -e "$2" ]; then ok "$1: $(basename "$2") present"; else bad "$1" "missing $(basename "$2")"; fi
}
expect_absent() { # <name> <path>
    if [ -e "$2" ]; then bad "$1" "$(basename "$2") should be gone"; else ok "$1: $(basename "$2") gone"; fi
}
expect_in_output() { # <name> <needle>
    case "$out" in
      *"$2"*) ok "$1: log contains \"$2\"" ;;
      *) bad "$1" "log does not contain \"$2\"" ;;
    esac
}

seed_old_backups() { # <dir> -- two 60-day-old backups plus a file we must not touch
    mkdir -p "$1"
    printf '{"items":[]}' > "$1/vault-export-2026-08-01_030000.json"
    printf 'old-archive' > "$1/vault-export-2026-08-01_030000.7z"
    printf 'keep me' > "$1/unrelated.txt"
    touch -t 202608010300 "$1/vault-export-2026-08-01_030000.json" 2>/dev/null
    touch -t 202608010300 "$1/vault-export-2026-08-01_030000.7z" 2>/dev/null
    touch -t 202608010300 "$1/unrelated.txt" 2>/dev/null
}

echo "harness: $SCRIPT"
if [ "$have_real_rclone" -eq 1 ]; then
    echo "rclone:  real binary found (retention cases run)"
else
    echo "rclone:  none on PATH (retention cases skipped)"
fi
echo

# 1 — plaintext happy path
d="$WORK/dest-01"; rm -rf "$d"
run "plaintext happy path" "$d"
expect_rc "plaintext happy path" 0
expect_files "plaintext happy path" "$d" 1

# 2 — archive happy path
d="$WORK/dest-02"; rm -rf "$d"
run "archive happy path" "$d" ARCHIVE_PASSWORD=archivepw
expect_rc "archive happy path" 0
expect_files "archive happy path" "$d" 1
for f in "$d"/*.7z; do
    expect_present "archive happy path" "$f"
done

# 3 — unlock fails
d="$WORK/dest-03"; rm -rf "$d"
run "unlock failure" "$d" FAIL_UNLOCK=1
expect_rc "unlock failure" 1
expect_in_output "unlock failure" "Unlock failed"
expect_files "unlock failure" "$d" 0

# 4 — export fails
d="$WORK/dest-04"; rm -rf "$d"
run "export failure" "$d" FAIL_EXPORT=1
expect_rc "export failure" 1
expect_files "export failure" "$d" 0

# 5 — login fails
d="$WORK/dest-05"; rm -rf "$d"
run "login failure" "$d" FAIL_LOGIN=1
expect_rc "login failure" 1
expect_files "login failure" "$d" 0

# 6 — export exits 0 but writes nothing
d="$WORK/dest-06"; rm -rf "$d"
run "missing export file" "$d" NO_EXPORT_FILE=1
expect_rc "missing export file" 1
expect_in_output "missing export file" "JSON file not created"
expect_files "missing export file" "$d" 0

# 7 — invalid CLEANUP_MIN_AGE aborts before any API call
d="$WORK/dest-07"; rm -rf "$d"
run "invalid CLEANUP_MIN_AGE" "$d" CLEANUP_MIN_AGE=30days
expect_rc "invalid CLEANUP_MIN_AGE" 1
expect_in_output "invalid CLEANUP_MIN_AGE" "must be a number followed by one unit"
bw_calls=$(grep -c '^bw ' "$WORK/log-invalid_CLEANUP_MIN_AGE" 2>/dev/null || true)
bw_calls=${bw_calls:-0}
if [ "$bw_calls" -eq 0 ]; then ok "invalid CLEANUP_MIN_AGE: no bw calls"; else bad "invalid CLEANUP_MIN_AGE" "$bw_calls bw calls before aborting"; fi

# 8 — truncated export is rejected
d="$WORK/dest-08"; rm -rf "$d"
run "truncated export" "$d" EXPORT_MODE=truncated
expect_rc "truncated export" 1
expect_in_output "truncated export" "not valid JSON"
expect_files "truncated export" "$d" 0

# 9 — export in an unexpected shape is rejected
d="$WORK/dest-09"; rm -rf "$d"
run "export without items" "$d" EXPORT_MODE=noitems
expect_rc "export without items" 1
expect_in_output "export without items" "no items array"
expect_files "export without items" "$d" 0

# 10 — empty vault only warns
d="$WORK/dest-10"; rm -rf "$d"
run "empty vault" "$d" EXPORT_MODE=empty
expect_rc "empty vault" 0
expect_in_output "empty vault" "0 items"
expect_files "empty vault" "$d" 1

# 11 — archive verification fails
d="$WORK/dest-11"; rm -rf "$d"
run "archive verification failure" "$d" ARCHIVE_PASSWORD=archivepw FAIL_7Z_TEST=1
expect_rc "archive verification failure" 1
expect_in_output "archive verification failure" "Archive verification failed"
expect_files "archive verification failure" "$d" 0

# 12 — failed cleanup does not fail a good backup
d="$WORK/dest-12"; rm -rf "$d"
run "failed cleanup" "$d" FAIL_DELETE=1
expect_rc "failed cleanup" 0
expect_in_output "failed cleanup" "retention cleanup failed"
expect_files "failed cleanup" "$d" 1

# 13 — retention removes both formats, keeps the fresh backup and unrelated files
if [ "$have_real_rclone" -eq 1 ]; then
    d="$WORK/dest-13"; rm -rf "$d"; seed_old_backups "$d"
    run "retention rotates both formats" "$d" ARCHIVE_PASSWORD=archivepw CLEANUP_MIN_AGE=30d
    expect_rc "retention rotates both formats" 0
    expect_absent "retention rotates both formats" "$d/vault-export-2026-08-01_030000.json"
    expect_absent "retention rotates both formats" "$d/vault-export-2026-08-01_030000.7z"
    expect_present "retention rotates both formats" "$d/unrelated.txt"
    expect_files "retention rotates both formats" "$d" 2

    # 14 — the backup written in this run survives even a nonsensical retention window
    d="$WORK/dest-14"; rm -rf "$d"; seed_old_backups "$d"
    run "fresh backup survives" "$d" ARCHIVE_PASSWORD=archivepw CLEANUP_MIN_AGE=0s
    expect_rc "fresh backup survives" 0
    expect_present "fresh backup survives" "$d/unrelated.txt"
    expect_files "fresh backup survives" "$d" 2
else
    skip "retention rotates both formats" "no real rclone"
    skip "fresh backup survives" "no real rclone"
fi

# 15 — deprecated SMB_PATH is turned into an :smb: destination. There is no SMB
# server here, so the upload itself fails; asserted are the warning and the
# destination the script builds.
d="$WORK/dest-15"; rm -rf "$d"
run "deprecated SMB_PATH" "$d" SMB_PATH="$d/share" RCLONE_DEST=
expect_in_output "deprecated SMB_PATH" "SMB_PATH is deprecated"
expect_in_output "deprecated SMB_PATH" "Uploading to :smb:"

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
