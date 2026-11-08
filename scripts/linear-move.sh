#!/usr/bin/env bash
# linear-move.sh - move Linear issues to a state in one call, printing one line, instead
# of one MCP save_issue per issue that echoes the whole issue back into the orchestrator's
# context (ADR 0006). Everything else in Linear still goes through the MCP.
#
#   scripts/linear-move.sh --state "<state name>" [--comment "<text>"] NSC-1 [NSC-2 ...]
#   scripts/linear-move.sh --check    read only: confirm the key works, list team NSC's states
#
# The key comes from LINEAR_API_KEY in the environment, else from the main checkout's .env
# (a worktree has no .env of its own). It goes to curl through a config on stdin, so it
# never reaches argv, and it is never printed.
#
# Exit codes:
#   0 every issue moved
#   1 at least one issue failed (each is named; the others did move)
#   2 bad usage
#   3 no API key: nothing was attempted, use the Linear MCP's save_issue instead
#
# LINEAR_API_URL overrides the endpoint, for testing this script only.
set -uo pipefail

usage() {
  echo 'usage: scripts/linear-move.sh --state "<state name>" [--comment "<text>"] NSC-1 [NSC-2 ...]' >&2
  echo '       scripts/linear-move.sh --check' >&2
  exit 2
}

state=""; comment=""; check=0
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || usage; state="$2"; shift 2 ;;
    --comment) [ $# -ge 2 ] || usage; comment="$2"; shift 2 ;;
    --check) check=1; shift ;;
    --*) usage ;;
    *) break ;;
  esac
done
[ "$check" -eq 1 ] || { [ -n "$state" ] && [ $# -ge 1 ]; } || usage
command -v jq >/dev/null || { echo "linear-move: jq is required" >&2; exit 1; }

key="${LINEAR_API_KEY:-}"
if [ -z "$key" ]; then
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  envfile="${common%/.git}/.env"
  if [ -n "$common" ] && [ -f "$envfile" ]; then
    key="$(sed -n 's/^LINEAR_API_KEY=//p' "$envfile" | tail -n 1)"
  fi
fi
if [ -z "$key" ]; then
  echo "linear-move: no LINEAR_API_KEY; use the Linear MCP's save_issue" >&2
  exit 3
fi

url="${LINEAR_API_URL:-https://api.linear.app/graphql}"
issue_arg="${1:-NSC-0}"
team="${issue_arg%%-*}"

body="$(mktemp -t linear-move.XXXXXX)"
trap 'rm -f "$body"' EXIT

gql() {  # gql <query> <variables as JSON>; prints the response
  jq -n --arg q "$1" --argjson v "$2" '{query: $q, variables: $v}' >"$body"
  printf 'header = "Authorization: %s"\n' "$key" \
    | curl -sS --retry 2 -K - -H 'Content-Type: application/json' --data-binary "@$body" "$url"
}

teams_query='query($key: String!) { teams(filter: {key: {eq: $key}}) { nodes { states { nodes { id name } } } } }'
resp="$(gql "$teams_query" "$(jq -n --arg key "$team" '{key: $key}')")"
if [ "$check" -eq 1 ]; then
  states="$(jq -r '[.data.teams.nodes[0].states.nodes[]?.name] | join(", ")' <<<"$resp" 2>/dev/null)"
  if [ -z "$states" ]; then
    echo "linear-move: check failed: $(jq -r '.errors[0].message // "no states in the response"' <<<"$resp" 2>/dev/null)" >&2
    exit 1
  fi
  echo "linear-move: key works; team $team states: $states"
  exit 0
fi
state_id="$(jq -r --arg s "$state" \
  '[.data.teams.nodes[0].states.nodes[]? | select(.name == $s) | .id][0] // empty' <<<"$resp" 2>/dev/null)"
if [ -z "$state_id" ]; then
  echo "linear-move: no state \"$state\" on team $team (or the request failed): $(jq -r '.errors[0].message // empty' <<<"$resp" 2>/dev/null)" >&2
  exit 1
fi

update_query='mutation($id: String!, $state: String!) { issueUpdate(id: $id, input: {stateId: $state}) { success issue { id } } }'
comment_query='mutation($issue: String!, $body: String!) { commentCreate(input: {issueId: $issue, body: $body}) { success } }'

moved=0; failed=0
for issue in "$@"; do
  resp="$(gql "$update_query" "$(jq -n --arg id "$issue" --arg state "$state_id" '{id: $id, state: $state}')")"
  uuid="$(jq -r 'select(.data.issueUpdate.success == true) | .data.issueUpdate.issue.id // empty' <<<"$resp" 2>/dev/null)"
  if [ -z "$uuid" ]; then
    echo "linear-move: $issue failed: $(jq -r '.errors[0].message // "no success in the response"' <<<"$resp" 2>/dev/null)" >&2
    failed=$((failed + 1))
    continue
  fi
  moved=$((moved + 1))
  if [ -n "$comment" ]; then
    resp="$(gql "$comment_query" "$(jq -n --arg issue "$uuid" --arg b "$comment" '{issue: $issue, body: $b}')")"
    if [ "$(jq -r '.data.commentCreate.success // false' <<<"$resp" 2>/dev/null)" != "true" ]; then
      echo "linear-move: $issue moved, but its comment failed" >&2
      failed=$((failed + 1))
    fi
  fi
done

echo "linear-move: $moved moved to $state${comment:+ with a comment}, $failed failed"
[ "$failed" -eq 0 ]
