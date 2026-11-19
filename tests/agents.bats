#!/usr/bin/env bats

setup() {
  bin="$BATS_TEST_DIRNAME/../scripts/agents"
  fx="$BATS_TEST_DIRNAME/fixtures"
}

@test "a Claude spinner line reads as working" {
  run "$bin" classify < "$fx/working.txt"
  [ "$output" = working ]
}

@test "a Codex spinner line reads as working" {
  run "$bin" classify < "$fx/codex-working.txt"
  [ "$output" = working ]
}

@test "a permission menu reads as blocked" {
  run "$bin" classify < "$fx/blocked.txt"
  [ "$output" = blocked ]
}

@test "a finished turn that ends on a question reads as asking" {
  run "$bin" classify < "$fx/asking.txt"
  [ "$output" = asking ]
}

@test "a finished turn reads as nothing, so the caller decides idle" {
  run "$bin" classify < "$fx/idle.txt"
  [ -z "$output" ]
}

@test "ssh hosts follow Include and skip patterns" {
  # Include paths resolve from ~/.ssh, so point HOME at the fixtures
  mkdir -p "$BATS_TEST_TMPDIR/.ssh"
  cp -R "$fx/ssh.d" "$BATS_TEST_TMPDIR/.ssh/"
  HOME="$BATS_TEST_TMPDIR" TMUX_AGENTS_SSH_CONFIG="$fx/ssh_config" run "$bin" hosts
  [ "$output" = "$(printf '192.0.2.7\nm1-max\nm1\nlegion')" ]
}

@test "plain keeps only the text of a title, no escape sequences" {
  source "$BATS_TEST_DIRNAME/../scripts/lib.sh"
  [ "$(plain "$(printf 'fix\033]52;c;ZXZpbA==\007 login\033[2J')")" = "fix]52;c;ZXZpbA== login[2J" ]
  [ "$(clean_title "$(printf '\033[31m✳ task\a')")" = "[31m✳ task" ]
}

# A fake ssh that answers with the hermes state file in $HERMES_JSON, or fails when it is unset
hermes() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n[ -n "$HERMES_JSON" ] || exit 255\nprintf "%%s" "$HERMES_JSON"\n' > "$BATS_TEST_TMPDIR/bin/ssh"
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  HERMES_JSON=$1 PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$bin" hermes-state box
}

@test "hermes with nothing to do is idle" {
  hermes '{"gateway_state":"running","active_agents":0,"active_work":null,"platforms":{"telegram":{"needs_attention":false}}}'
  [ "$output" = idle ]
}

@test "hermes running agents is working, with what it works on" {
  hermes '{"gateway_state":"running","active_agents":2,"active_work":"reply to a message","platforms":{}}'
  [ "$output" = "$(printf 'working\nreply to a message')" ]
}

@test "a hermes platform that needs attention, or a stopped gateway, blocks" {
  hermes '{"gateway_state":"running","active_agents":0,"platforms":{"telegram":{"needs_attention":true}}}'
  [ "$output" = "$(printf 'blocked\ntelegram needs attention')" ]
  hermes '{"gateway_state":"stopped","active_agents":0,"platforms":{}}'
  [ "$output" = "$(printf 'blocked\ngateway stopped')" ]
}

@test "an unreachable hermes is idle and says so" {
  hermes ''
  [ "$output" = "$(printf 'idle\nunreachable')" ]
}

@test "hermes state from the server reaches the screen as plain text" {
  hermes "{\"gateway_state\":\"running\",\"active_agents\":1,\"active_work\":\"job\\u001b]52;c;ZXZpbA==\\u0007 done\",\"platforms\":{}}"
  [ "$output" = "$(printf 'working\njob]52;c;ZXZpbA== done')" ]
}
