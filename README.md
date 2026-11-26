# tmux-agents

A tmux plugin that tracks Claude Code, Codex and OpenCode in your panes, on this machine and on servers you reach over ssh. Nothing is installed on the servers and the agents need no hooks.

- A watcher marks each agent `working`, `blocked` on a permission prompt, `asking` when its turn ends on a question, `waiting` when a turn finished and it is your move, or `idle` once it sits untouched for `@agents-idle-after` seconds. It sends a desktop notification when an agent out of view finishes or waits on you.
- `prefix + Space` opens go to anywhere, a fuzzy list of agents, sessions, windows and the hosts in `~/.ssh/config`.
- `prefix + a` opens a sidebar with your machines, the spaces on each, and the agents by state.

## Install

With [TPM](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'gabrielkoerich/tmux-agents'
```

Then press `prefix + I`. It needs tmux 3.3 or later for the popup, [fzf](https://github.com/junegunn/fzf) for the picker, and [jq](https://jqlang.org) to read services. With [terminal-notifier](https://github.com/julienXX/terminal-notifier) installed, clicking a notification brings your terminal forward on the agent's pane; without it, macOS notifications only show. The scripts run on the bash 3.2 that macOS ships.

## How it reads agents

An ssh pane only shows tmux the `ssh` process, so the agent's state has to come from what reaches the terminal.

1. If tmux keeps [OSC 7501](https://www.superlogical.com/rex/docs/build/program-status) program status, as `#{pane_program_status_states}`, the watcher uses it. Claude Code, Codex and OpenCode 2 send it. Stock tmux does not keep it yet ([tmux#5713](https://github.com/tmux/tmux/issues/5713)).
2. Otherwise it reads the bottom of the pane: a spinner line with elapsed time means working, a permission menu means blocked, and a finished turn whose last paragraph asks a question, the one above a marker like `✻ Cooked for 1m 37s`, means asking.

Screen reading breaks when an agent changes its UI text. The tests in `tests/fixtures` hold the screens it matches.

The host of an ssh pane comes from the arguments of the local `ssh` process. The watcher stores it in the pane option `@ssh_host`.

## Remote agents

An agent on a server should outlive your connection. `+ new` under a machine in the sidebar, or Enter on a server in the picker, opens `scripts/connect <host>` in a new window, which runs:

```sh
ssh -t <host> "tmux new -A -s <name>"
```

The agent lives in that tmux session on the server. When the link drops, `connect` says so and reconnects to the same session, waiting 2 seconds and doubling up to 30. A detach or the session ending stops it. `ServerAliveInterval=15` notices a dead link in about 45 seconds. It names the session after the date, time and pane, like `1119-021530-42`, unless you pass a name as `connect <host> <name>`.

`scripts/split h|v <pane>` splits a pane, and in a pane on a server the new pane connects to that server too, in a new session that starts in the folder the title shows. `scripts/tree <pane>` docks a tree of that folder on the left, run on the server, and the same key closes it. Bind it for panes on a server, and leave the rest to tmux-sidebar. Bind `split` in place of `split-window`:

```tmux
bind | run-shell "~/.tmux/plugins/tmux-agents/scripts/split h '#{pane_id}'"
bind _ run-shell "~/.tmux/plugins/tmux-agents/scripts/split v '#{pane_id}'"
``` The sidebar names the space after the remote folder or the agent's task, and after the session when the title has neither.

A session outlives its window too. Close the window, or restart the Mac, and the agent keeps running on the server. The watcher lists the tmux sessions on every machine in `@agents-hosts` each time it polls, and the sidebar shows the ones this Mac has no window on under their machine, as `↺ <folder> detached`, or `elsewhere` when another terminal has it. A click reattaches it in a new window with `connect <host> <session>`. Closing a window never ends its session, so an agent keeps running; to end one, select its `↺` row and press `x`, which asks first and then runs `tmux kill-session` on the server.

The same poll reads each machine's cpu and memory in use, both as a share of the machine, and its one minute load average, and the sidebar shows them on its row, `vps-us   3% 41% 0.10 ●`, so a server's tmux needs no status bar of its own in every pane. `scripts/host-probe.sh` goes to the server's `sh` on stdin, sessions and stats in one round trip, and reads `/proc` on Linux and `top`, `vm_stat` and `sysctl` on macOS. Only three numbers are kept, and a machine that stops answering shows none. Session names keep only `A-Za-z0-9_.-`, and folders and titles reach the screen as plain text.

The server needs tmux. Without it `connect` falls back to a plain shell, which a drop ends. For the agent's title to reach your tmux, set this in the server's tmux config:

```tmux
set -g set-titles on
set -g set-titles-string '#{pane_title}'
```

### SSH settings

Two settings in `~/.ssh/config` make remote spaces work well. Put them in a `Host *` block:

```
Host *
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/cm/%C
  ControlPersist 10m
```

Then create the socket folder once with `mkdir -p ~/.ssh/cm && chmod 700 ~/.ssh/cm`.

| Setting | Effect |
|---|---|
| `ServerAliveInterval 15`, `ServerAliveCountMax 3` | ssh sends a keepalive every 15 seconds and gives up after 3 missed ones, so a dead link ends in about 45 seconds and `connect` reconnects instead of the pane hanging |
| `ControlMaster auto`, `ControlPath` | The first connection to a server opens a socket in `~/.ssh/cm`, and later ones run over it without a new login. A new space or split on that server opens in a fraction of a second, and an agent that asks for a key, like 1Password, asks once |
| `ControlPersist 10m` | The shared connection stays open 10 minutes after its last window closes |

ssh takes the first value it finds for each option, so a `Host *` block above your host blocks would win over a value one of them sets. None of these options is usually set per host, so any `Host *` block works. The cost of sharing: when the shared connection dies, every window on that server drops at once, and each one reconnects through `connect`.

## Agents come back after a restart

With [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect), the plugin notes on every save which session each agent pane had, and after a restore it starts each agent again in its pane. It uses only what the agents already write, with no wrapper and no hook in the agent:

| Agent | How it finds the session | Exact | Not sure |
|---|---|---|---|
| Claude Code | The pane's title, which Claude sets to the conversation title, matches the latest `ai-title` or `custom-title` of one transcript in `~/.claude/projects/<folder>/` | `claude --resume <id>` | `claude --resume`, the picker |
| Codex | The folder had one Codex session in the last 14 days, from the `cwd` in `~/.codex/sessions` | `codex resume <id>` | `codex resume`, the picker |
| OpenCode | The pane's title, or one session for the folder, in `opencode.db` | `opencode --session <id>` | `opencode` |
| A space on a server | The pane `connect` opened | `connect <host> <session>` | |

When two panes would get the same session, both get the picker, so a conversation never opens twice. The saved file holds pane, agent and id only. The command is built at restore time, and an id that does not look like one gives the picker, so nothing read from a transcript reaches a shell as typed.

The plugin sets `@resurrect-hook-post-save-all` and `@resurrect-hook-post-restore-all` when they are empty, and leaves hooks you set yourself. Programs like nvim or lazygit are resurrect's own job, through `@resurrect-processes`. Set `@agents-resume off` to leave resurrect alone.

## Subagents

A local Claude that runs subagents shows how many on its row, `⠿ suq · fix login  ⑂3  4m`. Claude keeps each subagent's transcript in `~/.claude/projects/<folder>/<session>/subagents/agent-*.jsonl`, and the watcher counts the ones written in the last 2 minutes, every 10 seconds. It reads names and times, never what the files hold. Two Claude sessions in one folder share the count, and a subagent quiet for over 2 minutes in one long tool call drops out until it writes again.

## Services on a server

An agent that runs as a service, not in a pane, has no screen to read. The watcher polls such services over ssh, every 30 seconds by default, and lists each one with the agents in the sidebar and the picker. Clicking it opens a window on its host. Name them as `host:service`:

```tmux
set -g @agents-services 'vps-us:hermes'
```

`hermes` is the one service it knows: the [Hermes agent](https://github.com/NousResearch/hermes-agent) gateway. The watcher runs `cat ~/.hermes/gateway_state.json` on the host and takes four fields from it with `jq`:

| The state file says | State |
|---|---|
| `gateway_state` is not `running` | blocked, "gateway stopped" |
| a platform has `needs_attention` | blocked, "telegram needs attention" |
| `active_agents` is above 0 | working, with `active_work` |
| none of those | idle |
| the host does not answer | idle, "unreachable", without a notification |

The fields only ever reach the screen as plain text. With the ssh settings above, each poll reuses the open connection.

A headless agent, such as `claude -p` run by an orchestrator, draws no screen and sets no title. If it runs in its own tmux session, list those sessions in `@agents-headless-sessions` and the watcher marks them working while the session exists. They leave the spaces of this computer, and the sidebar names each after its worktree folder, so `~/.orch/worktrees/orch/internal-42-fix-login` shows as `orch · fix-login`:

```tmux
set -g @agents-headless-sessions 'orch-*'
```

## Go to anywhere

`prefix + Space` opens a popup with one list you search by typing:

```
  ! agent    claude › approve git push      orch · main:2
  ○ agent    claude › Home Security         homelab · main:1
    session  work 3 windows
    window   main:1 claude › Home Security  ~/Projects/homelab
    server   legion
```

Agents come first, the blocked ones at the top, each with its task, project and window. Then come sessions, windows, and every `Host` in `~/.ssh/config` and the files it includes.

| Key | Action |
|---|---|
| Enter | Go to the agent, session or window, or open `ssh <host>` in a new window |
| Ctrl-S | Open a server in a new session |
| Esc | Close |

## Sidebar

```
 Spaces

 ▭ This computer          ●
   M  main             main
   W  work

 ▭ legion                 ●
   O  orch             main
   +  new

 Agents

 Blocked  1
  ! legion · approve git…  2m
 Idle  1
  ○ dotfiles · tmux ssh…   1h
```

Local sessions are the spaces of this computer. An ssh window is a space of the host it points at, with the local session that holds it on the right.

Machines listed in `@agents-hosts` always show, with a grey ring until you connect to one. Other hosts show while a connection to them is open. `+ new` under a machine opens `ssh <host>` in a new window:

```tmux
set -g @agents-hosts 'legion m1-max'
``` The grey row is where you are, until you focus the sidebar and it becomes the cursor.

With `@agents-sidebar-panes on`, this computer lists each session, its windows under it, and the panes of a split window under those, each pane with its agent's state and task or its command and folder. A window with one pane is a single row that goes to that pane. Sessions, windows and panes come in index order, the same order as the tabs and the number keys:

```
 ▭ This computer          ●
   W  work
      0 zsh          Projects
   M  main             main
      0 editor
        ├ zsh            orch
        └ ⠿ Fix login    bean
```

The sidebar opens without taking focus. Click a row to go there, or scroll with the wheel. With the sidebar focused:

| Key | Action |
|---|---|
| `j` `k` or arrows | Move |
| Enter | Go to the session or pane |
| `n` | New window on that machine |
| `x` | On a detached session, end it on the server, after a confirm |
| Tab or Esc | Back to the previous pane |
| `q` | Close |

## Window names

The watcher sets `@ssh_host`, so a window name can say where its active pane runs. This format names a window after its agent and task, `claude › fix login` or `legion › fix login` over ssh, then the host of an ssh pane, the folder of a shell, or the command and folder:

```tmux
set -g automatic-rename on
set -g automatic-rename-format '#{?#{&&:#{m/r:^[^a-zA-Z0-9 ]+ ,#{pane_title}},#{!:#{m/r:^(zsh|bash|fish|sh)$,#{pane_current_command}}}},#{?#{@ssh_host},#{@ssh_host},#{pane_current_command}} › #{s|^[^a-zA-Z0-9 ]+ ||:pane_title},#{?#{m/r:^(ssh|mosh-client)$,#{pane_current_command}},#{?#{@ssh_host},#{@ssh_host},ssh},#{?#{m/r:^(zsh|bash|fish|sh)$,#{pane_current_command}},#{b:pane_current_path},#{pane_current_command} #{b:pane_current_path}}}}'
```

## Sessions as tabs

`@agents-tabs` picks what the top of the screen shows. `windows`, the default, keeps tmux's window tabs and lists your sessions under this computer in the sidebar. `sessions` turns that around: the sidebar lists the windows of the session you are in, and your status bar can loop over sessions. The watcher keeps `@agent_session_alert` on each session, the most urgent alert among its windows, for a mark on a session tab:

```tmux
set -g @agents-tabs sessions
# in status-format, in place of the #{W:…} window loop:
#{S:#[range=session|#{session_id}]#{?@agent_session_alert, !,} #{session_name} #[norange default],#[range=session|#{session_id}]#[underscore]#{session_name}#[nounderscore] #[norange default]}
```

## Status bar

The watcher sets the window option `@agent_alert` to `blocked`, `asking` or `done` while an agent out of view needs you, and clears it when you open the window. Show it in your window format:

```tmux
#{?#{==:#{@agent_alert},blocked},#[fg=colour196] !,}#{?#{==:#{@agent_alert},asking},#[fg=colour75] ?,}#{?#{==:#{@agent_alert},done},#[fg=colour46] ●,}
```

## Colours

The sidebar and the picker read a palette from tmux options, the same names the catppuccin tmux theme uses. Set them as `#rrggbb` and the plugin follows any theme you switch to. Unset, it keeps its own colours.

| Option | Used for |
|---|---|
| `@thm_fg` | Names |
| `@thm_muted` | Headings, meta and idle agents |
| `@thm_surface` | The selected row |
| `@thm_green` | Connected machines and waiting agents |
| `@thm_yellow` | Working agents |
| `@thm_alert` | Blocked agents |
| `@thm_blue` | Agents asking a question |
| `@thm_bg_dim` | Letters on badges |
| `@thm_badges` | Space separated badge colours |

The picker takes its fzf colours from `@agents-fzf-colors`, so a theme can set those too.

## Options

| Option | Default | |
|---|---|---|
| `@agents-pick-key` | `Space` | Picker key, after prefix |
| `@agents-sidebar-key` | `a` | Sidebar key, after prefix |
| `@agents-sidebar-width` | `32` | Sidebar width in cells |
| `@agents-sidebar-panes` | `off` | `on` lists each window and pane under this computer, in index order |
| `@agents-tree-width` | `40` | Width of the tree `scripts/tree` docks |
| `@agents-hosts` | | Machines the sidebar always shows, in order |
| `@agents-headless-sessions` | | Session globs that run a headless agent |
| `@agents-notify` | `on` | Desktop notifications |
| `@agents-notify-app` | `com.mitchellh.ghostty` | Bundle id of the terminal a notification click brings forward |
| `@agents-interval` | `2` | Seconds between scans |
| `@agents-resume` | `on` | Start agents again after a tmux-resurrect restore |
| `@agents-idle-after` | `600` | Seconds a finished turn waits before it counts as idle |
| `@agents-services` | | `host:service` entries the watcher polls over ssh, `hermes` for now |
| `@agents-services-interval` | `30` | Seconds between polls of services and of the sessions on pinned machines |
| `@agents-popup-style` | `bg=#101010` | Picker background |
| `@agents-popup-border-style` | `fg=colour238,bg=#101010` | Picker border |
| `@agents-fzf-colors` | dark, orange accent | fzf `--color` value for the picker |

## Tests

```sh
bats tests
```
