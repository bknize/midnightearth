---
type: planning
tags: [planning, cycles]
status: growing
related: ["[[planning/planning-moc]]", "[[specs/cycle-0-scaffolding/tasks]]", "[[specs/cycle-1-match-engine/tasks]]"]
created: 2026-11-02
updated: 2026-11-02
uid: 9628b800-b6d2-4dc1-9e13-0d7d7932fe0b
linear: https://linear.app/night-science-llc/project/cycle-0-scaffolding-6db3f9c856a0
supersedes:
---

# Dev cycles

One row per cycle. The acceptance criterion is always "buildable and testable".

| Cycle | Theme | Branch | Issues | Started | Done | Outcome |
|---|---|---|---|---|---|---|
| DC-00 | scaffolding | `cycle-0-scaffolding` | NSC-5 … NSC-20 | 2026-11-02 | 2026-11-02 | done: 16 tasks, gate green in 7 s on a fresh clone, screenshot via Godot MCP; see [[specs/cycle-0-scaffolding/tasks]] |
| DC-01 | match-engine | `dc-01-match-engine` | NSC-22 … NSC-33 (T01–T12, all of [[specs/cycle-1-match-engine/tasks]]); milestone [DC-01 match-engine](https://linear.app/night-science-llc/project/cycle-1-match-engine-19d44055ce13) | 2026-11-02 | 2026-11-02 | done: 12 tasks, merged as 6467a08; gate green in 16 s, 178 cases; smoke `seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56` pinned as golden; 50-seed sweep longest 126 actions (seed 24); no screenshot (C12); follow-ups NSC-34, NSC-35, NSC-36 |
