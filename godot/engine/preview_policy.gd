class_name PreviewPolicy
extends RefCounted
## How a previewed walk decides what a live walk would ask for (plan P12). ScoreWalk.step
## takes one: null means a live walk, which emits events and draws from the engine stream;
## a policy means a preview, which emits nothing and never touches the stream.
##
## Empty until DC-05 T06, which adds the decisions: a prompt takes its first option and a
## random destroy hits the opponent's lowest-flat card. The destroy rule already runs in
## EffectResolver whenever a policy is passed (DC-05 T04), so T06 only fills in the policy.
