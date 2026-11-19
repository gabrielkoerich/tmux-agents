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
