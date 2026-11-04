#!/usr/bin/env bash
# art-fetch.sh - download a Replicate prediction's output images next to its sidecar and
# log the estimated spend (ADR 0003, /art skill).
#
#   scripts/art-fetch.sh art/candidates/<batch>/<name>.json
#
# The sidecar is written by the artist straight after the prediction succeeds. Required
# keys: prediction_id, model, input, output (a URL or a list of URLs),
# price_per_image_usd. This script:
#   - downloads each output URL to <name>-1.<ext>, <name>-2.<ext>, ... beside the sidecar
#     (plain request first; on failure retries with the Replicate token from the
#     environment, passed through a curl config on stdin so it never reaches argv);
#   - adds "files" (the local names) and "fetched" (UTC time) to the sidecar;
#   - appends one line to art/ledger.jsonl (gitignored) at the checkout root;
#   - prints this month's estimated spend against ART_MONTHLY_BUDGET_USD (default 30).
#
# Exit codes: 0 ok, 1 download or JSON failure, 2 bad usage, 3 the month budget is
# reached (the files are still downloaded and logged; stop generating).
set -uo pipefail

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: scripts/art-fetch.sh <sidecar.json>" >&2
  exit 2
fi
command -v jq >/dev/null || { echo "art-fetch: jq is required" >&2; exit 1; }

sidecar="$1"
dir="$(cd "$(dirname "$sidecar")" && pwd)"
base="$(basename "$sidecar" .json)"
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "art-fetch: $sidecar is not inside a git checkout" >&2; exit 1; }
ledger="$root/art/ledger.jsonl"
budget="${ART_MONTHLY_BUDGET_USD:-30}"

if ! jq -e '.prediction_id and .model and .input and .output
            and (.price_per_image_usd | type == "number")' "$sidecar" >/dev/null; then
  echo "art-fetch: $sidecar lacks prediction_id, model, input, output or a numeric price_per_image_usd" >&2
  exit 1
fi

fetch() {  # fetch <url> <dest>
  if curl -fsSL --retry 2 -o "$2" "$1"; then return 0; fi
  [ -n "${REPLICATE_API_TOKEN:-}" ] || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$REPLICATE_API_TOKEN" \
    | curl -fsSL --retry 2 -K - -o "$2" "$1"
}

files=()
i=0
while IFS= read -r url; do
  [ -n "$url" ] || continue
  i=$((i + 1))
  ext="${url##*.}"; ext="${ext%%\?*}"
  case "$ext" in png|webp|jpg|jpeg) ;; *) ext="png" ;; esac
  name="$base-$i.$ext"
  if ! fetch "$url" "$dir/$name"; then
    echo "art-fetch: download failed for output $i of $base (URLs expire an hour after the prediction)" >&2
    rm -f "$dir/$name"
    exit 1
  fi
  files+=("$name")
  echo "fetched $dir/$name"
done < <(jq -r 'if (.output | type) == "array" then .output[] else .output end' "$sidecar")

if [ "${#files[@]}" -eq 0 ]; then
  echo "art-fetch: no output URLs in $sidecar" >&2
  exit 1
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp="$(mktemp)"
printf '%s\n' "${files[@]}" | jq -R . | jq -s . > "$tmp.files"
jq --slurpfile f "$tmp.files" --arg now "$now" '.files = $f[0] | .fetched = $now' \
  "$sidecar" > "$tmp" && mv "$tmp" "$sidecar"
rm -f "$tmp.files"

mkdir -p "$(dirname "$ledger")"
jq -c --arg now "$now" --arg sidecar "${sidecar}" --argjson n "${#files[@]}" \
  '{date: $now, prediction_id, model, images: $n,
    usd: ($n * .price_per_image_usd), batch: (.batch // null), sidecar: $sidecar}' \
  "$sidecar" >> "$ledger"

month="${now:0:7}"
spent="$(jq -s --arg m "$month" \
  '[.[] | select(.date | startswith($m)) | .usd] | add // 0' "$ledger")"
printf 'month %s estimated spend $%.3f of $%s\n' "$month" "$spent" "$budget"

if awk -v s="$spent" -v b="$budget" 'BEGIN { exit !(s >= b) }'; then
  echo "art-fetch: month budget reached; stop generating and ask Ben" >&2
  exit 3
fi
exit 0
