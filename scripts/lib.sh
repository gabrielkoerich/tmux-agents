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
