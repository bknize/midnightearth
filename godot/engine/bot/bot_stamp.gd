class_name BotStamp
extends RefCounted
## The stamp of the engine a record or a ladder rung belongs to (cycle 11 R1, R2, plan P1;
## first cycle 7 R33 and cycle 8 R58): `"r" + MatchRules.RULES_VERSION + "-"` and the first
## 16 hex digits of SHA-256 over the bytes of the card pool file, then the bytes of the deck
## list file, then the bytes of the Crew pool file (the files the engine loads,
## CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH and CrewPool.DEFAULT_PATH). The driver side
## (scripts/bot/records.py current_stamp) hashes godot/engine/data/cards.json, decks.json
## then crew.json the same way, so both sides give the same string for the same files. A
## change to the rules version, the pool, the deck list or the Crew pool changes the stamp:
## every record set the workers and the driver write carries it, and a ladder rung is one
## bot measured at one stamp.
##
## Static and pure: it reads the three files and prints nothing.

## How many hex digits of the digest the stamp keeps.
const HEX_DIGITS: int = 16


## The stamp of the shipped data under the current rules; "" when any file is missing.
## The paths default to the engine's data files; a suite may hash others.
static func current(
	cards_path: String = CardDb.DEFAULT_PATH,
	decks_path: String = DeckList.DEFAULT_PATH,
	crew_path: String = CrewPool.DEFAULT_PATH
) -> String:
	var paths: Array[String] = [cards_path, decks_path, crew_path]
	for path: String in paths:
		if not FileAccess.file_exists(path):
			return ""
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for path: String in paths:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty() and hashing.update(bytes) != OK:
			return ""
	var digest: String = hashing.finish().hex_encode()
	return "r%d-%s" % [MatchRules.RULES_VERSION, digest.substr(0, HEX_DIGITS)]
