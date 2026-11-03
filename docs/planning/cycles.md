---
type: planning
tags: [planning, cycles]
status: growing
related: ["[[planning/planning-moc]]", "[[specs/cycle-0-scaffolding/tasks]]", "[[specs/cycle-1-match-engine/tasks]]", "[[specs/cycle-1-match-engine/spec]]", "[[specs/cycle-2-board/tasks]]"]
created: 2026-11-02
updated: 2026-11-03
uid: 9628b800-b6d2-4dc1-9e13-0d7d7932fe0b
linear: https://linear.app/night-science-llc/project/cycle-0-scaffolding-6db3f9c856a0
supersedes:
---

# Dev cycles

One row per cycle. The acceptance criterion is always "buildable and testable".

| Cycle | Theme | Branch | Issues | Started | Done | Outcome |
|---|---|---|---|---|---|---|
| DC-00 | scaffolding | `cycle-0-scaffolding` | NSC-5 … NSC-20 | 2026-11-02 | 2026-11-02 | done: 16 tasks, gate green in 7 s on a fresh clone, screenshot via Godot MCP; see [[specs/cycle-0-scaffolding/tasks]] |
| DC-01 | match-engine | `dc-01-match-engine` | NSC-22 … NSC-33 (T01–T12, all of [[specs/cycle-1-match-engine/tasks]]); milestone [DC-01 match-engine](https://linear.app/night-science-llc/project/cycle-1-match-engine-19d44055ce13) | 2026-11-02 | 2026-11-02 | done: 12 tasks, merged as 6467a08; gate green in 16 s, 166 cases (first recorded as 178, a miscount; corrected 2026-11-03); smoke `seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56` pinned as golden; 50-seed sweep longest 126 actions (seed 24); no screenshot (C12); follow-ups NSC-34, NSC-35, NSC-36 |
| DC-02 | hardening | `dc-02-hardening` | NSC-36, NSC-34, NSC-35 (DC-01 follow-ups: edit hook typed-strict and worktree-aware; keep the final table after MATCH_ENDED, [[specs/cycle-1-match-engine/spec]] C15/C14; engine hardening); milestone [DC-02 hardening](https://linear.app/night-science-llc/project/cycle-1-match-engine-19d44055ce13) | 2026-11-03 | 2026-11-03 | done: 3 issues, merged as 47f0974; NSC-36 landed on master early as 1a5e391 (Ben: 2a) because Claude Code runs the edit hook from the main checkout, so agent worktrees only get the new hook once it is on master; a live agent probe then got the strict error for `var x := 1`; gate green in 15 s, 175 cases (166 + 4 round_match_end + 5 from NSC-35); smoke `seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56` unchanged; planted `printraw(` under engine/bot/ fails the source scan; reviewer on both engine diffs, nothing blocking; no screenshot (C12) |
| DC-03 | board | `dc-03-board` | NSC-37 … NSC-47 (T01–T11, all of [[specs/cycle-2-board/tasks]]); milestone [DC-03 board](https://linear.app/night-science-llc/project/cycle-2-board-b50bca125334) | 2026-11-03 | | planned: Ben chose all 11 (1a), accepting two L tasks (T07, T08) so the spec finishes in one cycle; waves T01/T03/T04/T05/T06 → T02 → T07 → T08 → T09 → T10; acceptance gate green, golden `Board: match ended seed=1 winner=0 wins=4-0 rounds=4 end=wins actions=56`, MCP drag run, two screenshots (C11); NSC-38 is the only issue allowed to edit `addons/` |
