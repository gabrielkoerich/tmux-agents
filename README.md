# tmux-agents

A tmux plugin that tracks Claude Code, Codex and OpenCode in your panes, on this machine and on servers you reach over ssh. Nothing is installed on the servers and the agents need no hooks.

- A watcher marks each pane `working`, `blocked` or `idle`, and sends a desktop notification when an agent out of view finishes or waits on you.
- `prefix + Space` opens a fuzzy list of agents, sessions, windows and the hosts in `~/.ssh/config`. Enter goes there, or opens `ssh <host>` in a new window.
- `prefix + a` opens a sidebar with your machines, the spaces on each, and the agents by state.

## Install

With [TPM](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'gabrielkoerich/tmux-agents'
```

Then press `prefix + I`. It needs tmux 3.3 or later for the popup, and [fzf](https://github.com/junegunn/fzf) for the picker. The scripts run on the bash 3.2 that macOS ships.

## How it reads agents

An ssh pane only shows tmux the `ssh` process, so the agent's state has to come from what reaches the terminal.

1. If tmux keeps [OSC 7501](https://www.superlogical.com/rex/docs/build/program-status) program status, as `#{pane_program_status_states}`, the watcher uses it. Claude Code, Codex and OpenCode 2 send it. Stock tmux does not keep it yet ([tmux#5713](https://github.com/tmux/tmux/issues/5713)).
2. Otherwise it reads the bottom of the pane: a spinner line with elapsed time means working, a permission menu means blocked.

Screen reading breaks when an agent changes its UI text. The tests in `tests/fixtures` hold the screens it matches.

The host of an ssh pane comes from the arguments of the local `ssh` process. The watcher stores it in the pane option `@ssh_host`.

## Sidebar

```
 Spaces

 ▭ This computer          ●
   M  main             main
   W  work

 ▭ legion                 ●
   O  orch             main

 Agents

 Blocked  1
  ! legion · approve git…  2m
 Idle  1
  ○ dotfiles · tmux ssh…   1h
```

Local sessions are the spaces of this computer. An ssh window is a space of the host it points at, with the local session that holds it on the right. The grey row is where you are, until you focus the sidebar and it becomes the cursor.

The sidebar opens without taking focus. Click a row to go there, or scroll with the wheel. With the sidebar focused:

| Key | Action |
|---|---|
| `j` `k` or arrows | Move |
| Enter | Go to the session or pane |
| `n` | New window on that machine |
| Tab or Esc | Back to the previous pane |
| `q` | Close |

## Window names

The watcher sets `@ssh_host`, so a window name can say where its active pane runs. This format names a window after its agent and task, `claude › fix login` or `legion › fix login` over ssh, then the host of an ssh pane, the folder of a shell, or the command and folder:

```tmux
set -g automatic-rename on
set -g automatic-rename-format '#{?#{&&:#{m/r:^[^a-zA-Z0-9 ]+ ,#{pane_title}},#{!:#{m/r:^(zsh|bash|fish|sh)$,#{pane_current_command}}}},#{?#{@ssh_host},#{@ssh_host},#{pane_current_command}} › #{s|^[^a-zA-Z0-9 ]+ ||:pane_title},#{?#{m/r:^(ssh|mosh-client)$,#{pane_current_command}},#{?#{@ssh_host},#{@ssh_host},ssh},#{?#{m/r:^(zsh|bash|fish|sh)$,#{pane_current_command}},#{b:pane_current_path},#{pane_current_command} #{b:pane_current_path}}}}'
```

## Status bar

The watcher sets the window option `@agent_alert` to `blocked` or `done` while an agent out of view needs you, and clears it when you open the window. Show it in your window format:

```tmux
#{?#{==:#{@agent_alert},blocked},#[fg=colour196] !,}#{?#{==:#{@agent_alert},done},#[fg=colour46] ●,}
```

## Options

| Option | Default | |
|---|---|---|
| `@agents-pick-key` | `Space` | Picker key, after prefix |
| `@agents-sidebar-key` | `a` | Sidebar key, after prefix |
| `@agents-sidebar-width` | `32` | Sidebar width in cells |
| `@agents-notify` | `on` | Desktop notifications |
| `@agents-interval` | `2` | Seconds between scans |
| `@agents-popup-style` | `bg=#101010` | Picker background |
| `@agents-popup-border-style` | `fg=colour238,bg=#101010` | Picker border |
| `@agents-fzf-colors` | dark, orange accent | fzf `--color` value for the picker |

## Tests

```sh
bats tests
```
