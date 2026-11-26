#!/usr/bin/env bash
# TPM entry point: binds the picker and the sidebar, then starts the watcher
dir=$(cd "$(dirname "$0")" && pwd)

option() {
  local v
  v=$(tmux show -gqv "$1")
  echo "${v:-$2}"
}

# tmux 3.8 draws popups on a grey theme colour, so give the picker the dark background of a pane
popup="-b rounded -s '$(option @agents-popup-style 'bg=#101010')' -S '$(option @agents-popup-border-style 'fg=colour238,bg=#101010')'"
tmux bind -N "Go to anywhere: agents, sessions, windows, servers" "$(option @agents-pick-key Space)" run-shell "tmux display-popup -E -c '#{client_name}' -w 70% -h 60% $popup -T ' go to ' \"'$dir/scripts/agents' pick '#{client_name}'\""
tmux bind -N "Agents sidebar, open or close" "$(option @agents-sidebar-key a)" run-shell "'$dir/scripts/sidebar' toggle '#{window_id}'"
tmux run-shell -b "'$dir/scripts/agents' watch"

# With tmux-resurrect, note each agent's session on save and start it again after a restore. resurrect runs a
# hook as shell code, so ours goes on its own line after one already there. @agents-resume off leaves it alone
if [[ $(option @agents-resume on) == on ]]; then
  for kind in save:post-save-all before:pre-restore-all restore:post-restore-all; do
    name="@resurrect-hook-${kind#*:}"
    cmd="'$dir/scripts/resume' ${kind%%:*}"
    cur=$(tmux show -gqv "$name")
    if [[ $cur != *"$cmd"* ]]; then
      tmux set -g "$name" "${cur:+$cur$'\n'}$cmd"
    fi
  done
fi
