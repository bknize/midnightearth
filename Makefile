# Midnight Earth build gate. Every target dispatches to scripts/check.sh (see cycle-0 R12-R19).
# Exit 0 = buildable and testable. GODOT_BIN overrides the Godot 4.6 binary.
# bot-eval and bot-selftest (cycle 7) are never part of `check`.
.PHONY: check import lint parse boot test bootstrap bot-eval bot-selftest

BOT   ?= random
REF   ?= random
SEEDS ?= 1-5000

check:      ; @scripts/check.sh
import:     ; @scripts/check.sh import
lint:       ; @scripts/check.sh lint
parse:      ; @scripts/check.sh parse
boot:       ; @scripts/check.sh boot
test:       ; @scripts/check.sh test
bootstrap:  ; @scripts/bootstrap.sh
# The 50-seed sweep (B-14), outside `check`. `make sweep BOT=matrix` sweeps that bot;
# `WEIGHTS=<abs path>` builds it on that weights file.
.PHONY: sweep
sweep:      ; @$(if $(filter command line,$(origin BOT)),SWEEP_BOT=$(BOT) )$(if $(filter command line,$(origin WEIGHTS)),SWEEP_WEIGHTS=$(WEIGHTS) )scripts/check.sh sweep
# `WEIGHTS=<path>` builds side a (BOT) on that weights file (bot-eval.sh --weights).
bot-eval:   ; @scripts/bot-eval.sh --a $(BOT) --b $(REF) --seeds $(SEEDS)$(if $(filter command line,$(origin WEIGHTS)), --weights $(WEIGHTS))
bot-selftest: ; @python3 -I scripts/bot/driver.py selftest
# The bot trainer's unit tests (cycle 11 P19), outside `check`. No Godot.
.PHONY: trainer-test training-digest
# The training digest (cycle 16 P17): outside `check`, contacts the PC once (one scp).
training-digest: ; @scripts/training-pull.sh
trainer-test: ; @python3 -I -m unittest discover -s trainer/tests -t .
# The progress dashboard (ADR 0007): docs/dashboard.md from every tasks.md, cycles.md and
# the backlog note. Run at the end of a cycle (`/cycle test`). No Godot.
.PHONY: dashboard
dashboard:  ; @python3 -I scripts/dashboard.py
# The playtest release (docs/decisions/0008-playtest-releases.md), outside `check`: gate, export
# macOS + Windows, publish a GitHub Release from the pushed tip of master.
# `make release DRY_RUN=1` builds into build/out and uploads nothing.
.PHONY: release
release:    ; @scripts/release.sh$(if $(DRY_RUN), --dry-run)
