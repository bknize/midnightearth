class_name BotStamp
extends RefCounted
## The stamp of the engine a bot's weights belong to (cycle 7 R33, R34, plan P8):
## `"r" + MatchRules.RULES_VERSION + "-"` and the first 16 hex digits of SHA-256 over the
## bytes of the card pool file, then the bytes of the deck list file (the files the engine
## loads, CardDb.DEFAULT_PATH and DeckList.DEFAULT_PATH). The script side
## (scripts/bot/records.py current_stamp) hashes godot/engine/data/cards.json then
## godot/engine/data/decks.json the same way, so both sides give the same string for the
## same files. A change to the rules version, the pool or the deck list changes the stamp,
## which is what the rerun provision (R36) watches.
##
## Static and pure: it reads the two files and prints nothing.

## How many hex digits of the digest the stamp keeps.
const HEX_DIGITS: int = 16


## The stamp of the shipped data under the current rules; "" when either file is missing.
## `cards_path` and `decks_path` default to the engine's data files; a suite may hash others.
static func current(
	cards_path: String = CardDb.DEFAULT_PATH, decks_path: String = DeckList.DEFAULT_PATH
) -> String:
	if not FileAccess.file_exists(cards_path) or not FileAccess.file_exists(decks_path):
		return ""
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for path: String in [cards_path, decks_path]:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty() and hashing.update(bytes) != OK:
			return ""
	var digest: String = hashing.finish().hex_encode()
	return "r%d-%s" % [MatchRules.RULES_VERSION, digest.substr(0, HEX_DIGITS)]
