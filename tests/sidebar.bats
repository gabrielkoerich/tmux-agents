#!/usr/bin/env bats

# Each test gets its own tmux server, with no config so no watcher runs
setup() {
  bin="$BATS_TEST_DIRNAME/../scripts/sidebar"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexec %s -L bats-%s -f /dev/null "$@"\n' "$(command -v tmux)" "$$" > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  tmux new -d -s main -x 120 -y 40
  tmux new -d -s work -x 120 -y 40
  pane=$(tmux display -p -t main '#{pane_id}')
}

teardown() {
  tmux kill-server 2>/dev/null || true
}

@test "local sessions are spaces of this computer" {
  TMUX_PANE=$pane run "$bin" build
  [[ $output == *"session:main|"* ]]
  [[ $output == *"session:work|"* ]]
  [[ $output == *"This computer"* ]]
}

@test "agents are grouped by state, the most urgent first" {
  tmux set -p -t work @agent_state idle \; set -p -t work @agent_since "$(date +%s)"
  other=$(tmux split-window -d -P -F '#{pane_id}' -t work)
  tmux set -p -t "$other" @agent_state blocked
  TMUX_PANE=$pane run "$bin" build
  blocked=$(grep -n 'Blocked' <<<"$output" | cut -d: -f1)
  idle=$(grep -n 'Idle' <<<"$output" | cut -d: -f1)
  [ -n "$blocked" ] && [ "$blocked" -lt "$idle" ]
  [[ $output == *"pane:$other|"* ]]
}

@test "the sidebar leaves itself out" {
  tmux set -p -t "$pane" @agent_state idle
  TMUX_PANE=$pane run "$bin" build
  [[ $output != *"pane:$pane|"* ]]
}
