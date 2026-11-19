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

@test "pinned machines show with no connection, each with a new row" {
  tmux set -g @agents-hosts 'legion m1-max'
  TMUX_PANE=$pane run "$bin" build
  [[ $output == *"host:legion|"*"legion"* ]]
  [[ $output == *"host:m1-max|"*"new"* ]]
  legion=$(grep -n 'host:legion|' <<<"$output" | head -1 | cut -d: -f1)
  m1=$(grep -n 'host:m1-max|' <<<"$output" | head -1 | cut -d: -f1)
  [ "$legion" -lt "$m1" ]
}

@test "headless sessions leave the spaces and show as working agents named after their worktree" {
  mkdir -p "$BATS_TEST_TMPDIR/worktrees/orch/internal-42-fix-login"
  tmux new -d -s orch-orch-internal-42 -c "$BATS_TEST_TMPDIR/worktrees/orch/internal-42-fix-login"
  tmux set -g @agents-headless-sessions 'orch-*'
  "$BATS_TEST_DIRNAME/../scripts/agents" watch &
  sleep 3
  kill $!
  TMUX_PANE=$pane run "$bin" build
  [[ $output != *"session:orch-orch-internal-42|"* ]]
  [[ $output == *"Working"* ]]
  [[ $output == *"orch"*"fix-login"* ]]
}

@test "a split of a server pane never runs what the server put in its title" {
  printf '#!/bin/sh\nsleep 30\n' > "$BATS_TEST_TMPDIR/bin/ssh"
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  marker="$BATS_TEST_TMPDIR/pwned"
  tmux set -p -t "$pane" @remote_session s1 \; set -p -t "$pane" @ssh_host box \; select-pane -t "$pane" -T "u@box: /tmp';touch $marker;'"
  run "$BATS_TEST_DIRNAME/../scripts/split" h "$pane"
  [ "$status" -eq 0 ]
  sleep 1
  [ ! -e "$marker" ]
  [[ "$(tmux list-panes -t main -F '#{pane_start_command}' | tail -1)" == *"connect box '' ''" ]]
}

@test "tree opens a server pane's tree on the left and the same key closes it" {
  printf '#!/bin/sh\nsleep 30\n' > "$BATS_TEST_TMPDIR/bin/ssh"
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  tmux set -p -t "$pane" @remote_session s1 \; set -p -t "$pane" @ssh_host box \; select-pane -t "$pane" -T "u@box: ~/code"
  "$BATS_TEST_DIRNAME/../scripts/tree" "$pane"
  [[ "$(tmux list-panes -t main -F '#{@agents_tree} #{pane_start_command}')" == *'1 ssh -t box "cd ~/code'* ]]
  "$BATS_TEST_DIRNAME/../scripts/tree" "$pane"
  [ "$(tmux list-panes -t main | wc -l | tr -d ' ')" -eq 1 ]
}

@test "a pinned machine lists its sessions this Mac has no window on, to reattach" {
  printf '#!/bin/sh\nprintf "%%s\\n" "s-open|1|/home/u|u@box: ~" "s-old|0|/home/u/code/orch|u@box: ~/code/orch" "bad;rm -rf ~|2|/tmp|x"\n' > "$BATS_TEST_TMPDIR/bin/ssh"
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  tmux set -g @agents-hosts box
  other=$(tmux new-window -d -P -F '#{pane_id}' -t main)
  tmux set -p -t "$other" @remote_session s-open \; set -p -t "$other" @ssh_host box
  "$BATS_TEST_DIRNAME/../scripts/agents" poll-sessions
  TMUX_PANE=$pane run "$bin" build
  [[ $output != *"attach:box:s-open|"* ]]
  [[ $output == *"attach:box:s-old|"*"orch"*"detached"* ]]
  [[ $output == *"attach:box:badrm-rf|"*"elsewhere"* ]]
}

@test "a session open in a split counts as open, not detached" {
  printf '#!/bin/sh\nprintf "%%s\\n" "s-one|1|/home/u|x" "s-two|1|/home/u|x"\n' > "$BATS_TEST_TMPDIR/bin/ssh"
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  tmux set -g @agents-hosts box
  a=$(tmux new-window -d -P -F '#{pane_id}' -t main)
  b=$(tmux split-window -d -P -F '#{pane_id}' -t "$a")
  tmux set -p -t "$a" @remote_session s-one \; set -p -t "$a" @ssh_host box \; set -p -t "$b" @remote_session s-two \; set -p -t "$b" @ssh_host box
  "$BATS_TEST_DIRNAME/../scripts/agents" poll-sessions
  TMUX_PANE=$pane run "$bin" build
  [[ $output != *"attach:box:"* ]]
}

@test "a pinned machine shows the cpu, memory and load it reports, and only numbers" {
  printf '#!/bin/sh\ncat >/dev/null\nprintf "%%s\\n" "--stats--" "$STATS"\n' > "$BATS_TEST_TMPDIR/bin/ssh"
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  tmux set -g @agents-hosts box
  STATS='12|1.5|0.30' "$BATS_TEST_DIRNAME/../scripts/agents" poll-sessions
  TMUX_PANE=$pane run "$bin" build
  [[ $output == *"host:box|"*"12% 1.5G 0.30"* ]]
  STATS="$(printf '9|1|1\033]52;c;eA==\007')" "$BATS_TEST_DIRNAME/../scripts/agents" poll-sessions
  [ -z "$(tmux show -gqv @agents_stats_box)" ]
}
