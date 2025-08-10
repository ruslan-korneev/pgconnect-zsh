#!/usr/bin/env zsh
# pgfz – interactive Postgres service picker + actions via fzf

# ---------- environment defaults ----------
: ${PGFZ_SERVICE_CONF:=$HOME/.pg_service.conf}
: ${PGFZ_PGCLI_CMD:=pgcli}
: ${PGFZ_PGCLI_ARGS:=}
: ${PGFZ_PSQL_CMD:=psql}
: ${PGFZ_PGDUMP_CMD:=pg_dump}
: ${PGFZ_FZF_PROMPT:="Select a database service: "}
: ${PGFZ_FZF_COMMON_OPTS:=}
: ${PGFZ_FZF_OPTS:=}
: ${PGFZ_PREVIEW_TABLE_LIMIT:=50}
: ${PGFZ_PREVIEW_TIMEOUT:=2}
: ${PGFZ_DUMP_DIR:=.}
: ${PGFZ_DUMP_FORMAT:=c}
# PGFZ_CLIP_CMD optional

# ---------- helpers ----------
pgfz::_die() { print -u2 -- "$*"; return 1; }

pgfz::_need() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || pgfz::_die "Error: '$c' not found in PATH"
  done
}

# Return section names (services) from pg_service.conf robustly (preserves order)
pgfz::_list_services() {
  local conf="$1"
  awk '
    function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
    /^[ \t]*[#;]/{ next }
    /^[ \t]*\[/ {
      if ($0 ~ /^[ \t]*\[[^]]+\][ \t]*$/) {
        name=$0
        sub(/^[ \t]*\[/, "", name)
        sub(/\][ \t]*$/, "", name)
        name=trim(name)
        if (name != "") print name
      }
    }
  ' "$conf"
}

# URL encode helper
pgfz::__urlencode() {
  emulate -L zsh
  local s="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$s" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -MURI::Escape -e 'print uri_escape($ARGV[0])' -- "$s"
    return
  fi
  local out="${s// /%20}"
  print -r -- "$out"
}

# Create a simple postgres URL from the service file values
pgfz::_url_from_service() {
  local conf="$1" svc="$2"
  local host port user db ssl line
  while IFS= read -r line; do
    case "$line" in
      host=*)     host="${line#*=}";;
      hostaddr=*) host="${line#*=}";;
      port=*)     port="${line#*=}";;
      user=*)     user="${line#*=}";;
      dbname=*)   db="${line#*=}";;
      sslmode=*)  ssl="${line#*=}";;
    esac
  done < <(awk -v target="$svc" '
    function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
    /^[ \t]*\[/ {
      name=$0; sub(/^[ \t]*\[/,"",name); sub(/\][ \t]*$/,"",name); name=trim(name)
      hit=(name==target); next
    }
    hit && $0 !~ /^[ \t]*([#;]|$)/ { print trim($0) }
  ' "$conf")

  local euser ehost edb u
  euser=$(pgfz::__urlencode "${user:-}")
  ehost=$(pgfz::__urlencode "${host:-localhost}")
  edb=$(pgfz::__urlencode "${db:-${user:-postgres}}")
  u="postgresql://"
  if [[ -n "$euser" ]]; then u+="$euser@"; fi
  u+="$ehost"
  if [[ -n "$port" ]]; then u+=":${port}"; fi
  u+="/$edb"
  local -a qs=()
  if [[ -n "$ssl" ]]; then qs+=("sslmode=$(pgfz::__urlencode "$ssl")"); fi
  if (( ${#qs[@]} )); then u+="?${(j:&:)qs}"; fi
  print -- "$u"
}

pgfz::_clip() {
  local data="$1"
  if [[ -n "$PGFZ_CLIP_CMD" ]]; then
    print -n -- "$data" | eval "$PGFZ_CLIP_CMD" && return 0
  fi
  if command -v pbcopy >/dev/null 2>&1; then
    print -n -- "$data" | pbcopy && return 0
  elif command -v wl-copy >/dev/null 2>&1; then
    print -n -- "$data" | wl-copy && return 0
  elif command -v xclip >/dev/null 2>&1; then
    print -n -- "$data" | xclip -selection clipboard && return 0
  fi
  return 1
}

pgfz::_connect_pgcli() {
  local svc="$1"
  local -a args
  args=(${=PGFZ_PGCLI_ARGS})
  print -u2 -- "Connecting with ${PGFZ_PGCLI_CMD} to service='$svc' ..."
  exec "${PGFZ_PGCLI_CMD}" "service=${svc}" "${args[@]}"
}

pgfz::_connect_psql() {
  local svc="$1"
  print -u2 -- "Connecting with ${PGFZ_PSQL_CMD} to service='$svc' ..."
  exec "${PGFZ_PSQL_CMD}" "service=${svc}"
}

pgfz::_dump() {
  local svc="$1"
  local ts file fmt
  fmt="${PGFZ_DUMP_FORMAT}"
  ts=$(date +%Y%m%d-%H%M%S)
  mkdir -p -- "$PGFZ_DUMP_DIR" || return 1
  case "$fmt" in
    c) file="${PGFZ_DUMP_DIR}/dump-${svc}-${ts}.dump";;
    p) file="${PGFZ_DUMP_DIR}/dump-${svc}-${ts}.sql";;
    d) file="${PGFZ_DUMP_DIR}/dump-${svc}-${ts}"; mkdir -p -- "$file";;
    t) file="${PGFZ_DUMP_DIR}/dump-${svc}-${ts}.tar";;
    *) fmt=c; file="${PGFZ_DUMP_DIR}/dump-${svc}-${ts}.dump";;
  esac
  print -u2 -- "Dumping service='$svc' to '$file' (format=$fmt) ..."
  PGSERVICE="$svc" "${PGFZ_PGDUMP_CMD}" -F "$fmt" -f "$file" || return 1
  print -u2 -- "Done."
}

pgfz::_exec_sql_file() {
  local svc="$1"
  local file
  if command -v fd >/dev/null 2>&1; then
    file=$(fd -t f -e sql . | fzf --prompt="Select .sql to run: " --height=40% --layout=reverse --border=rounded)
  else
    file=$(find . -type f -name '*.sql' 2>/dev/null | sed 's|^\./||' | fzf --prompt="Select .sql to run: " --height=40% --layout=reverse --border=rounded)
  fi
  [[ -z "$file" ]] && { print -u2 -- "No file selected."; return 1; }
  print -u2 -- "Running '$file' on service='$svc' ..."
  PGSERVICE="$svc" "${PGFZ_PSQL_CMD}" -v ON_ERROR_STOP=1 -f "$file"
}

# ---------- main ----------
pgfz() {
  emulate -L zsh
  setopt pipefail

  pgfz::_need fzf
  [[ -f "$PGFZ_SERVICE_CONF" ]] || pgfz::_die "Error: file not found → $PGFZ_SERVICE_CONF"

  # Build services array safely
  local -a services
  services=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && services+=("$line")
  done < <(pgfz::_list_services "$PGFZ_SERVICE_CONF")
  (( ${#services} )) || pgfz::_die "No services found in $PGFZ_SERVICE_CONF"

  # Export variables used by the preview subshell
  export PGFZ_SERVICE_CONF PGFZ_PREVIEW_TABLE_LIMIT PGFZ_PREVIEW_TIMEOUT PGFZ_PSQL_CMD

  # Preview command: dequote the fzf placeholder to get the raw service name
  local preview_cmd
  preview_cmd=$(cat <<'PREVIEW_SH'
raw="{}"
if [ -z "$raw" ]; then
  echo "Select a service on the left."
  exit 0
fi

# Turn shell-quoted string from fzf into the raw value
eval "set -- $raw"
svc="$1"

printf "\033[1;34mService:\033[0m %s\n\n" "$svc"

printf "\033[1;33mParameters from %s\033[0m\n" "$PGFZ_SERVICE_CONF"
awk -v target="$svc" '
  function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
  BEGIN{ hit=0 }
  /^[ \t]*\[/ {
    name=$0; sub(/^[ \t]*\[/,"",name); sub(/\][ \t]*$/,"",name); name=trim(name)
    hit=(name==target); next
  }
  hit {
    if ($0 ~ /^[ \t]*([#;]|$)/) next
    if ($0 ~ /^[ \t]*\[/) { hit=0; next }
    kv=$0
    if (index(kv, "=") > 0) {
      key=substr(kv, 1, index(kv,"=")-1)
      val=substr(kv, index(kv,"=")+1)
      key=trim(key); val=trim(val)
      if ( key ~ /^(host|hostaddr|port|user|dbname|sslmode|options|service)$/ ) {
        printf "  %-8s %s\n", key, val
      }
    }
  }
' "$PGFZ_SERVICE_CONF" || true
echo

printf "\033[1;33mTables (first %s)\033[0m\n" "${PGFZ_PREVIEW_TABLE_LIMIT:-50}"
TABCHAR=$(printf '\t')
if command -v "${PGFZ_PSQL_CMD:-psql}" >/dev/null 2>&1; then
  PGSERVICE="$svc" PGCONNECT_TIMEOUT="${PGFZ_PREVIEW_TIMEOUT:-2}" \
    "${PGFZ_PSQL_CMD:-psql}" -X -q -A -t -w -F "$TABCHAR" \
    -c "select n.nspname, c.relname
          from pg_class c
          join pg_namespace n on n.oid=c.relnamespace
         where c.relkind in ('r','p')
           and n.nspname not in ('pg_catalog','information_schema')
         order by 1,2
         limit ${PGFZ_PREVIEW_TABLE_LIMIT:-50}" 2>/dev/null \
    | if command -v column >/dev/null 2>&1; then column -t -s "$TABCHAR"; else cat; fi
else
  echo "  (psql not found; install it to see tables)"
fi
PREVIEW_SH
)

  # fzf options and key actions
  # Keep ctrl-p for previous item; connect with psql on Alt-p
  local -a fzf_opts user_fzf_opts
  fzf_opts=(
    --prompt="$PGFZ_FZF_PROMPT"
    --height=40%
    --layout=reverse
    --border=rounded
    --info=inline
    --preview="$preview_cmd"
    --preview-window=right,50%,border-left
    --header=$'enter: pgcli | M-p: psql | M-d: pg_dump \nM-e: run .sql | M-c: copy URL | C-y: copy env\n'
    --header-first
    --expect=alt-p,alt-d,alt-e,alt-c,ctrl-y
  )
  user_fzf_opts=(${=PGFZ_FZF_OPTS})

  local out
  out=$(
    printf '%s\n' "${services[@]}" | \
    FZF_DEFAULT_OPTS="${PGFZ_FZF_COMMON_OPTS:-$FZF_DEFAULT_OPTS}" \
    fzf "${fzf_opts[@]}" "${user_fzf_opts[@]}"
  )

  [[ -z "$out" ]] && { print -u2 -- "Cancelled."; return 1; }

  # Parse fzf output robustly: last line is selection, first line may be a key
  local -a lines
  lines=("${(@f)out}")
  local key="" svc=""
  if (( ${#lines[@]} == 1 )); then
    svc="${lines[1]}"
  else
    key="${lines[1]}"
    svc="${lines[-1]}"
  fi
  [[ -z "$svc" ]] && { print -u2 -- "Cancelled."; return 1; }

  case "$key" in
    "")        pgfz::_connect_pgcli "$svc" ;;
    alt-p)     pgfz::_connect_psql "$svc"  ;;
    alt-d)     pgfz::_dump "$svc"          ;;
    alt-e)     pgfz::_exec_sql_file "$svc" ;;
    alt-c)
      local url; url="$(pgfz::_url_from_service "$PGFZ_SERVICE_CONF" "$svc")"
      if pgfz::_clip "$url"; then
        print -u2 -- "Copied URL to clipboard: $url"
      else
        print -u2 -- "$url"
      fi
      ;;
    ctrl-y)
      local envstr="PGSERVICE=$svc"
      if pgfz::_clip "$envstr"; then
        print -u2 -- "Copied: $envstr"
      else
        print -u2 -- "$envstr"
      fi
      ;;
    *) pgfz::_connect_pgcli "$svc" ;;
  esac
}

# Auto-run if executed (not sourced)
if [[ "$ZSH_EVAL_CONTEXT" != *:file ]]; then
  pgfz "$@"
fi
