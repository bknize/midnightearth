#!/usr/bin/env bash
# art-approve.sh - move one candidate Ben picked into the Godot project and record how
# to regenerate it (ADR 0003, /art approve). Run by the orchestrator, on the branch the
# commit will land on, from that checkout.
#
#   scripts/art-approve.sh <candidate-image> <asset-id> [--kind cards] [--replace]
#
#   <candidate-image>  art/candidates/<batch>/<name>-<n>.<ext>, absolute or relative;
#                      may live in another checkout (candidates are gitignored)
#   <asset-id>         kebab-case or a card id such as c01
#   --kind <kind>      subfolder under godot/art/ (default cards; ref for LoRA
#                      references, icons, ui, ...)
#   --replace          overwrite an existing asset and manifest entry
#
# Copies the image to godot/art/<kind>/<asset-id>.png (converted with sips when it is
# not PNG) and writes manifest["assets"]["<kind>/<asset-id>"] in art/manifest.json from
# the sidecar <name>.json beside the candidate. Images under godot/art/ are Git LFS
# (.gitattributes). Exit codes: 0 ok, 1 failure, 2 bad usage.
set -uo pipefail

usage() { echo "usage: scripts/art-approve.sh <candidate-image> <asset-id> [--kind <kind>] [--replace]" >&2; exit 2; }
[ $# -ge 2 ] || usage
src="$1"; id="$2"; shift 2
kind="cards"; replace=0
while [ $# -gt 0 ]; do
  case "$1" in
    --kind) shift; kind="${1:-}"; [ -n "$kind" ] || usage ;;
    --replace) replace=1 ;;
    *) usage ;;
  esac
  shift
done
[ -f "$src" ] || { echo "art-approve: no such file $src" >&2; exit 1; }
[[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "art-approve: asset id must be lowercase kebab-case" >&2; exit 2; }
[[ "$kind" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "art-approve: kind must be lowercase kebab-case" >&2; exit 2; }
command -v jq >/dev/null || { echo "art-approve: jq is required" >&2; exit 1; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "art-approve: run inside a checkout" >&2; exit 1; }
manifest="$root/art/manifest.json"
dest_rel="godot/art/$kind/$id.png"
dest="$root/$dest_rel"
key="$kind/$id"

src_dir="$(cd "$(dirname "$src")" && pwd)"
src_name="$(basename "$src")"
sidecar="$src_dir/$(printf '%s' "${src_name%.*}" | sed -E 's/-[0-9]+$//').json"
[ -f "$sidecar" ] || { echo "art-approve: no sidecar $sidecar for $src_name" >&2; exit 1; }
[ -f "$manifest" ] || { echo "art-approve: $manifest missing" >&2; exit 1; }

if [ "$replace" -eq 0 ]; then
  if [ -e "$dest" ] || jq -e --arg k "$key" '.assets[$k]' "$manifest" >/dev/null; then
    echo "art-approve: $key already exists; pass --replace to overwrite" >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$dest")"
case "${src_name##*.}" in
  png|PNG) cp "$src" "$dest" || exit 1 ;;
  *) sips -s format png "$src" --out "$dest" >/dev/null || { echo "art-approve: sips could not convert $src" >&2; exit 1; } ;;
esac

today="$(date +%Y-%m-%d)"
tmp="$(mktemp)"
if ! jq --arg k "$key" --arg path "$dest_rel" --arg src "$src_name" --arg today "$today" \
     --slurpfile s "$sidecar" '
  .assets[$k] = {
    path: $path,
    source: $src,
    batch: ($s[0].batch // null),
    subject: ($s[0].subject // null),
    model: $s[0].model,
    version: ($s[0].version // null),
    prediction_id: $s[0].prediction_id,
    seed: ($s[0].input.seed // null),
    input: $s[0].input,
    price_per_image_usd: $s[0].price_per_image_usd,
    approved: $today
  }' "$manifest" > "$tmp"; then
  rm -f "$tmp"
  echo "art-approve: could not update $manifest" >&2
  exit 1
fi
mv "$tmp" "$manifest"
echo "approved $key -> $dest_rel (manifest updated)"
