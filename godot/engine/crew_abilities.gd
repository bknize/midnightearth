class_name CrewAbilities
extends RefCounted
## The Crew's triggered abilities (cycle 9 plan P13), called by the trigger queue for each
## queued Crew entry with the TriggerQueue/TriggerContext protocol (VerbHandler): prepare()
## when the trigger comes up, resolve() when it acts. A Crew prompt is optional and opens
## even for one target (TriggerContext.choose does both for a Crew).
##
## DC-13 T05 stub: every Crew trigger fizzles `no_target`; DC-13 T07 fills the six A Crew
## (Navigator and Captain on On score, Void and Dredger on On empty draw) and the Ongoing
## reads (Tallyman, Engineer).


## The Crew trigger of `ctx` came up: the T05 stub fizzles it `no_target`.
static func prepare(ctx: TriggerContext) -> void:
	ctx.fizzle(Abilities.REASON_NO_TARGET)


## The Crew trigger of `ctx` resolves: nothing before DC-13 T07.
static func resolve(_ctx: TriggerContext) -> void:
	pass
