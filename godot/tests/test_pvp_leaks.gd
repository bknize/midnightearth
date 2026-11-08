class_name TestPvpLeaks
extends PvpLeakHarness
## The P15 leak scan over every PVP message (cycle 12 T03; plan P15; spec R21, R33, R67) on
## GATE_SEEDS seeds, inside the gate's 30-second budget (R69). The scan itself lives in
## PvpLeakHarness; tests/sweep/test_pvp_leaks_sweep.gd runs it on SWEEP_SEEDS under
## `make sweep`.


func test_pvp_matches_send_no_seed_and_no_hidden_card() -> void:
	_scan_seeds(PvpLeakHarness.GATE_SEEDS)
