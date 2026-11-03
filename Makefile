# Midnight Earth build gate. Every target dispatches to scripts/check.sh (see cycle-0 R12-R19).
# Exit 0 = buildable and testable. GODOT_BIN overrides the Godot 4.6 binary.
.PHONY: check import lint parse boot test bootstrap

check:      ; @scripts/check.sh
import:     ; @scripts/check.sh import
lint:       ; @scripts/check.sh lint
parse:      ; @scripts/check.sh parse
boot:       ; @scripts/check.sh boot
test:       ; @scripts/check.sh test
bootstrap:  ; @scripts/bootstrap.sh
