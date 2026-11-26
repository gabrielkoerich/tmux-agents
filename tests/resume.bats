#!/usr/bin/env bats

# A private tmux server, a throwaway HOME with fake transcripts, and a fake claude, so nothing real is touched
setup() {
  bin="$BATS_TEST_DIRNAME/../scripts/resume"
  export HOME="$BATS_TEST_TMPDIR/home" XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/work/app"
  printf '#!/bin/sh\nexec %s -S %s/tmux.sock -f /dev/null "$@"\n' "$(command -v tmux)" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  # tmux names a pane after its process, so a copy of bash called claude passes for Claude. macOS kills a
  # copy of its own /bin/bash, so a bash from elsewhere on PATH is copied when there is one
  src=$(type -a -p bash | grep -v '^/bin/' | head -1)
  cp "${src:-$(command -v bash)}" "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  tmux new -d -s main -x 120 -y 40 -c "$BATS_TEST_TMPDIR/work/app"
  app=$(tmux display -p -t main '#{pane_current_path}')
  proj="$HOME/.claude/projects/$(printf '%s' "$app" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$proj"
}

teardown() {
  tmux kill-server 2>/dev/null || true
}

# A transcript whose latest title is $2
transcript() {
  printf '{"type":"ai-title","aiTitle":"%s","sessionId":"%s"}\n' "$2" "$1" > "$proj/$1.jsonl"
}

# A pane running the fake claude, titled the way Claude titles its terminal
claude_pane() {
  local p
  p=$(tmux new-window -d -P -F '#{pane_id}' -t main -c "$app" "claude -c 'while :; do sleep 1; done'")
  tmux select-pane -t "$p" -T "✳ $1"
  sleep 0.3
}

@test "a pane whose title matches one transcript in its folder resumes that session" {
  transcript 11111111-2222-3333-4444-555555555555 "Fix login"
  transcript 66666666-7777-8888-9999-000000000000 "Other work"
  claude_pane "Fix login"
  "$bin" save
  grep -q "claude${sep:-}" "$XDG_STATE_HOME/tmux-agents/resume"
  grep -q '11111111-2222-3333-4444-555555555555' "$XDG_STATE_HOME/tmux-agents/resume"
}

@test "two panes that would resume the same session both get the picker" {
  transcript 11111111-2222-3333-4444-555555555555 "Fix login"
  claude_pane "Fix login"
  claude_pane "Fix login"
  "$bin" save
  [ "$(grep -c 'claude' "$XDG_STATE_HOME/tmux-agents/resume")" -eq 2 ]
  ! grep -q '11111111' "$XDG_STATE_HOME/tmux-agents/resume"
}

@test "a pane with no matching title gets the picker" {
  transcript 11111111-2222-3333-4444-555555555555 "Fix login"
  claude_pane "Something else"
  "$bin" save
  grep -q 'claude' "$XDG_STATE_HOME/tmux-agents/resume"
  ! grep -q '11111111' "$XDG_STATE_HOME/tmux-agents/resume"
}

@test "restore types the resume command into a shell pane, and never an id that is not an id" {
  sep=$'\x1f'
  shell=$(tmux new-window -d -P -F '#{window_index}' -t main "bash --norc --noprofile")
  odd=$(tmux new-window -d -P -F '#{window_index}' -t main "bash --norc --noprofile")
  sleep 0.3
  mkdir -p "$XDG_STATE_HOME/tmux-agents"
  printf 'main%s%s%s0%sclaude%s11111111-2222-3333-4444-555555555555\nmain%s%s%s0%sclaude%sx;touch %s/pwned\n' \
    "$sep" "$shell" "$sep" "$sep" "$sep" "$sep" "$odd" "$sep" "$sep" "$sep" "$BATS_TEST_TMPDIR" > "$XDG_STATE_HOME/tmux-agents/resume"
  "$bin" restore
  sleep 0.5
  tmux capture-pane -p -t "main:$shell" | grep -q 'claude --resume 11111111-2222-3333-4444-555555555555'
  tmux capture-pane -p -t "main:$odd" | grep -q 'claude --resume$'
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}
