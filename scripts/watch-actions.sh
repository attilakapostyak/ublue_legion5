#!/usr/bin/env bash
# Watch a snapshot of this repository's active runs; never start a workflow.
set -euo pipefail

interval="${1:-10}"
if [[ ! "$interval" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: just actions-watch [poll-seconds] (positive integer, default: 10)" >&2
    exit 1
fi
for tool in gh jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing $tool. Run 'just apps-install' (or 'brew install $tool')." >&2
        exit 1
    fi
done

# Capture the command separately so authentication/network errors aren't hidden
# by mapfile/process substitution. gh infers the repository from the git remote.
if ! active="$(gh run list --limit 100 --json databaseId,status \
    --jq '.[] | select(.status != "completed") | .databaseId')"; then
    echo "Could not list GitHub Actions runs. Check your connection and 'gh auth status'." >&2
    exit 1
fi
if [[ -z "$active" ]]; then
    echo "No active GitHub Actions runs found among the latest 100 runs."
    exit 0
fi
mapfile -t runs <<<"$active"
printf 'Watching %s active run(s), checking every %ss. Ctrl+C to stop.\n' "${#runs[@]}" "$interval"
printf '  Run %s\n' "${runs[@]}"

notify() {
    local title="$1" message="$2" urgency="$3"
    printf '\n%s\n%s\n\a' "$title" "$message"
    # Notification/sound support is optional (e.g. over SSH or in a box).
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name='GitHub Actions' --urgency="$urgency" \
            --hint=string:sound-name:complete -- "$title" "$message" || true
    fi
    if command -v canberra-gtk-play >/dev/null 2>&1; then
        canberra-gtk-play --id=complete >/dev/null 2>&1 || true
    fi
}

failed=0
while ((${#runs[@]})); do
    pending=()
    for run in "${runs[@]}"; do
        # Do not report a failed API request as a finished/failed workflow.
        if ! details="$(gh run view "$run" --json status,conclusion,displayTitle,url)"; then
            echo "Could not check run $run; stopping without a completion notification for it. Rerun to retry." >&2
            exit 1
        fi
        if [[ "$(jq -r '.status' <<<"$details")" != completed ]]; then
            pending+=("$run")
            continue
        fi
        conclusion="$(jq -r '.conclusion' <<<"$details")"
        message="$(jq -r '.displayTitle + "\n" + .url' <<<"$details")"
        urgency=normal
        if [[ "$conclusion" != success ]]; then
            urgency=critical
            failed=1
        fi
        notify "GitHub Actions: $conclusion (run $run)" "$message" "$urgency"
    done
    runs=("${pending[@]}")
    if ((${#runs[@]})); then
        sleep "$interval"
    fi
done
exit "$failed"
