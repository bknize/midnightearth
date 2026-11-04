class_name PromptTap
extends RefCounted
## What a tap does while a prompt is open (R56, C16): the kind, and for CHOOSE the option
## position to submit. Pure data; PromptRules builds it.

var kind: int = PromptRules.Tap.NOTHING
## The position in the prompt's zone to submit; -1 unless `kind` is CHOOSE.
var index: int = -1


func _init(new_kind: int = PromptRules.Tap.NOTHING, new_index: int = -1) -> void:
	kind = new_kind
	index = new_index
