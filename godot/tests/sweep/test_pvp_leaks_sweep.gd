class_name TestPvpLeaksSweep
extends PvpLeakHarness
## The PVP leak scan (PvpLeakHarness; spec R21, R33, R67) on SWEEP_SEEDS seeds, outside the
## gate: `make sweep` runs res://tests/sweep (R69, cycle-12 T13). The gate scans the first
## GATE_SEEDS of them (tests/test_pvp_leaks.gd).


func test_ten_pvp_matches_send_no_seed_and_no_hidden_card() -> void:
	_scan_seeds(PvpLeakHarness.SWEEP_SEEDS)
