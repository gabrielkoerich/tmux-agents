# Agent rules for tmux-agents

## Never touch the tmux server someone works in

The scripts drive the user's live tmux server. A test that reaches it can kill every session they have open.

- Every tmux command in a test, a bats test or a one-off check, names a private socket on its own command line: `tmux -S "$dir/tmux.sock" ...`. Do not rely on a PATH wrapper, an alias or an environment variable to redirect `tmux`, since one that is missing falls through to the live server. On 2026-11-23 a test whose wrapper folder came from an unset variable ran `tmux kill-server` against the live server.
- Keep socket paths short, like `/tmp/x.sock` or the bats test's temp folder. A Unix socket path over about 100 bytes fails.
- Read-only commands against the live server (`list-panes`, `show`, `display -p`) are fine. Anything that kills, creates or reconfigures runs on a private socket, unless the user asked for that change on their live server.
- A test that starts a server kills it and leaves no socket behind, also when it fails.
- If the live server was restarted from a non-interactive shell, `tmux source-file ~/.tmux.conf` re-runs TPM and brings back the plugin bindings and widgets without touching sessions.

## Tests

```sh
bats tests
PATH="/bin:/usr/bin:$(brew --prefix)/bin" bats tests   # macOS bash 3.2, which tmux runs the scripts with
./bin/security-audit --strict
```

CI also runs the tests on bash 3.2, 4.4 and 5.2, each built from source.
