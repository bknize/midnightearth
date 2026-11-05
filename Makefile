# Midnight Earth build gate. Every target dispatches to scripts/check.sh (see cycle-0 R12-R19).
# Exit 0 = buildable and testable. GODOT_BIN overrides the Godot 4.6 binary.
# bot-eval and bot-selftest (cycle 7) are never part of `check`.
.PHONY: check import lint parse boot test bootstrap bot-eval bot-selftest

BOT   ?= tuned
REF   ?= greedy_v1
SEEDS ?= 1-5000

check:      ; @scripts/check.sh
import:     ; @scripts/check.sh import
lint:       ; @scripts/check.sh lint
parse:      ; @scripts/check.sh parse
boot:       ; @scripts/check.sh boot
test:       ; @scripts/check.sh test
bootstrap:  ; @scripts/bootstrap.sh
# The 50-seed sweep (NSC-133), outside `check`. `make sweep BOT=matrix` sweeps that bot.
.PHONY: sweep
sweep:      ; @$(if $(filter command line,$(origin BOT)),SWEEP_BOT=$(BOT) )scripts/check.sh sweep
bot-eval:   ; @scripts/bot-eval.sh --a $(BOT) --b $(REF) --seeds $(SEEDS)
bot-selftest: ; @python3 -I scripts/bot/driver.py selftest
