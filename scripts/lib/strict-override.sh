#!/usr/bin/env bash
# strict-override.sh - sourced by scripts/check.sh and scripts/hooks/gd-edit-gate.sh so the
# gate and the edit hook promote the same typed-GDScript warnings to errors (B-04).
#
#   write_override <file> <strict|tests>
#
# strict adds return_value_discarded; tests skips it, because gdUnit4 fluent assertions
# discard return values by design. The caller owns the file and must remove it.

write_override() {
  cat >"$1" <<'CFG'
[debug]
gdscript/warnings/untyped_declaration=2
gdscript/warnings/inferred_declaration=2
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_cast=2
gdscript/warnings/unsafe_call_argument=2
CFG
  if [ "$2" = strict ]; then echo 'gdscript/warnings/return_value_discarded=2' >>"$1"; fi
  return 0
}
