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

# Agents prefix their title with a state glyph, ✳ idle or ◐ working, which is noise in a name
clean_title() {
  local t=$1
  while [[ $t =~ ^[^[:alnum:][:space:]]+[[:space:]]+(.*)$ ]]; do
    t=${BASH_REMATCH[1]}
  done
  echo "$t"
}

# True when a session matches one of the space separated globs in @agents-headless-sessions
headless_session() {
  local p pats
  read -r -a pats <<<"$2"
  for p in "${pats[@]}"; do
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
  local muted fg green alert yellow surface dim badges
  IFS='|' read -r muted fg green alert yellow surface dim badges <<<"$(tmux display -p '#{@thm_muted}|#{@thm_fg}|#{@thm_green}|#{@thm_alert}|#{@thm_yellow}|#{@thm_surface}|#{@thm_bg_dim}|#{@thm_badges}')"
  c_head=$(colour 38 "$muted" 245)
  c_meta=$(colour 38 "$muted" 242)
  c_name=$(colour 38 "$fg" 252)
  c_on=$(colour 38 "$green" 71)
  c_blocked=$(colour 38 "$alert" 203)
  c_working=$(colour 38 "$yellow" 179)
  c_idle=$(colour 38 "$muted" 245)
  c_sel=$(colour 48 "$surface" 236)
  c_badge_fg=$(colour 38 "$dim" 255)
  read -r -a badge_list <<<"$badges"
}
