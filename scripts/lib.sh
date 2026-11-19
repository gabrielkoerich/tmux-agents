# Shared by the watcher and the sidebar, sourced, not run
sep=$'\x1f'
ssh_cmds='^(ssh|mosh-client)$'

# Prints the host of an ssh command line, skipping options that take a value
ssh_target() {
  local a skip= host=
  set -f
  set -- $1
  set +f
  shift
  for a in "$@"; do
    if [[ -n $skip ]]; then
      skip=
      continue
    fi

    case $a in
      (-[BbcDEeFIiJLlmOoPpQRSWw]) skip=1 ;;
      (-*) ;;
      (*) host=$a; break ;;
    esac
  done
  echo "${host#*@}"
}

# Prints the host an ssh pane points at, from its own process or the ssh it started
ssh_host_of() {
  local args
  args=$(awk -v p="$1" '($1 == p || $2 == p) && $3 ~ /^ssh$|\/ssh$/ { $1 = $2 = ""; print; exit }' <<<"$2")
  ssh_target "${args#"${args%%[![:space:]]*}"}"
}

# A title comes from whatever runs in the pane, a server too, so only plain text of it ever reaches a screen
plain() {
  printf '%s' "${1//[[:cntrl:]]/}"
}

# Agents prefix their title with a state glyph, ✳ idle or ◐ working, which is noise in a name
clean_title() {
  local t
  t=$(plain "$1")
  while [[ $t =~ ^[^[:alnum:][:space:]]+[[:space:]]+(.*)$ ]]; do
    t=${BASH_REMATCH[1]}
  done
  echo "$t"
}

# True when a session matches one of the space separated globs in @agents-headless-sessions
headless_session() {
  local p pats
  read -r -a pats <<<"$2"
  for p in ${pats[@]+"${pats[@]}"}; do
    if [[ $1 == $p ]]; then
      return 0
    fi
  done
  return 1
}

# A runner that works in a worktree names the task after its folder, minus a leading id like internal-596326- or gh-issue-4133-
task_name() {
  local slug=${1##*/}
  if [[ $slug =~ ^[A-Za-z][A-Za-z-]*-[0-9]+-(.+)$ ]]; then
    slug=${BASH_REMATCH[1]}
  fi
  echo "$slug"
}

# An escape for a colour, kind 38 for text or 48 for background, from a #rrggbb theme value or a 256 colour fallback
colour() {
  if [[ $2 =~ ^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$ ]]; then
    printf '\e[%s;2;%d;%d;%dm' "$1" "0x${BASH_REMATCH[1]}" "0x${BASH_REMATCH[2]}" "0x${BASH_REMATCH[3]}"
  else
    printf '\e[%s;5;%sm' "$1" "$3"
  fi
}

# Reads the @thm_* palette a tmux theme sets, so the sidebar and picker follow it, with fixed colours when there is none
load_palette() {
  local muted fg green alert yellow blue surface dim badges
  IFS='|' read -r muted fg green alert yellow blue surface dim badges <<<"$(tmux display -p '#{@thm_muted}|#{@thm_fg}|#{@thm_green}|#{@thm_alert}|#{@thm_yellow}|#{@thm_blue}|#{@thm_surface}|#{@thm_bg_dim}|#{@thm_badges}')"
  c_head=$(colour 38 "$muted" 245)
  c_meta=$(colour 38 "$muted" 242)
  c_name=$(colour 38 "$fg" 252)
  c_on=$(colour 38 "$green" 71)
  c_blocked=$(colour 38 "$alert" 203)
  c_working=$(colour 38 "$yellow" 179)
  c_asking=$(colour 38 "$blue" 75)
  c_idle=$(colour 38 "$muted" 245)
  c_sel=$(colour 48 "$surface" 236)
  c_badge_fg=$(colour 38 "$dim" 255)
  read -r -a badge_list <<<"$badges"
}

# True when a title starts with an agent's state glyph and a space, like "✳ Fix login" or "◐ Fix login"
agent_title() {
  [[ $1 =~ ^[^[:alnum:][:space:]]+[[:space:]] ]]
}

# The user ssh logs in as, from the target or the ssh config, resolved locally without connecting
ssh_user_of() {
  if [[ $1 == *@* ]]; then
    echo "${1%%@*}"
    return
  fi

  ssh -G "$1" 2>/dev/null | awk '$1 == "user" { print $2; exit }'
}

# Prints user@host and the folder its title shows for a pane on a server, and fails for a local pane
remote_of() {
  local cmd host user rsess pid title folder=''
  IFS=$sep read -r cmd host user rsess pid title <<<"$(tmux display -p -t "$1" "#{pane_current_command}$sep#{@ssh_host}$sep#{@ssh_user}$sep#{@remote_session}$sep#{pane_pid}$sep#{pane_title}")"
  if [[ ! $cmd =~ $ssh_cmds && -z $rsess ]]; then
    return 1
  fi

  if [[ -z $host ]]; then
    host=$(ssh_host_of "$pid" "$(ps -A -o pid=,ppid=,args=)")
  fi

  if [[ -z $host ]]; then
    return 1
  fi

  # The title comes from the server, so take only plain path characters from it
  title=$(plain "$title")
  if [[ $title =~ :[[:space:]]*(~|~?/[A-Za-z0-9._/~-]*)$ ]]; then
    folder=${BASH_REMATCH[1]}
  fi
  printf '%s%s%s\n' "${user:+$user@}$host" "$sep" "$folder"
}

# The cd a server runs before a command, quoted for its shell, with ~ left for that shell to expand
remote_cd() {
  if [[ $1 == "~" ]]; then
    printf 'cd ~ 2>/dev/null; '
  elif [[ $1 == "~/"* ]]; then
    printf 'cd ~/%q 2>/dev/null; ' "${1#\~/}"
  elif [[ -n $1 ]]; then
    printf 'cd %q 2>/dev/null; ' "$1"
  fi
}

option() {
  local v
  v=$(tmux show -gqv "$1")
  echo "${v:-$2}"
}
