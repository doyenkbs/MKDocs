#!/bin/bash
# ---------------------------------------------------------------------------
# runcommand.sh
# Break-glass package: checks one operator-supplied shell command and, in Run
# mode, runs it in bash.
# Built for a Tanium action package. For Linux and macOS.
# Tanium runs it as the client user, normally root.
#
# SECURITY MODEL: the real control is the content set and RBAC that limit who
# can deploy this package. The checks prevent accidents. They are a list of
# known patterns, not a security boundary, and weaker than the Windows checks
# (there is no real shell parser). A trusted operator who wants to get around
# them can. Do not widen deploy rights because the checks exist.
#
# Tanium command line:
#   /bin/bash runcommand.sh "$1" "$2"
#
# Parameters (positional):
#   $1  Mode     Audit = run the checks and report, run nothing (default)
#                Run   = run the checks, then run the command if they pass
#   $2  Command  The shell command to run (bash). Required.
#
# Exit codes:
#   0  Finished. Run: the command ran and returned 0. Audit: always 0
#      (read the BLOCKED or WOULD RUN line).
#   1  The command ran and returned a non-zero exit code. The log line gives
#      the command's own code ("systemctl status" returns 3 for a stopped unit).
#   2  A parameter was wrong (Mode, empty command, the value was split, or a
#      NUL byte). Nothing ran.
#   3  Stopped by a check: protected system path, or a raw disk or file
#      system write. Nothing ran.
#   4  Unexpected problem (a temp file could not be made). Nothing ran.
#   5  Stopped by a check: protected security agent. Nothing ran.
#   6  Stopped by a check: decode-and-run command. Nothing ran.
#   The first check that trips decides the code.
#
# Log:
#   The Tanium action log shows the important lines and the first 60 lines of
#   the command's output (standard output and errors together), because the
#   console shows about 100 lines. Every line, with up to 5000 output lines,
#   also goes to /var/log/runcommand.log when the script can write there.
#   The command is logged as typed. A password or token in it is logged too.
#
# Written for bash 3.2 and later (macOS ships 3.2). Only POSIX regex classes
# are used with grep, no \b or \s.
# ---------------------------------------------------------------------------

set -o pipefail
set -f      # no filename expansion inside this wrapper. The command itself runs in its own bash.

SCRIPT_NAME="runcommand"
SCRIPT_VERSION="2.0.0"
HOST=$(hostname)
LOG_FILE="/var/log/runcommand.log"
# How many lines of the command's output to show in the Tanium action log, and
# to keep in the log file. Keep the first number well under 100.
MAX_ACTION_LOG_OUTPUT_LINES=60
MAX_FILE_OUTPUT_LINES=5000

# ----- logging and exit helpers ---------------------------------------
# Never call wrong_input, block or finish inside $( ) or a pipe: they must
# exit the main shell.

# The log file is used only when it is a normal file (not a link) that this
# script can write, in a folder that only root can write. Over 1 MB, one old
# copy is kept.
LOG_FD_OK=0
if [ -d /var/log ] && [ -w /var/log ] && [ ! -L "$LOG_FILE" ]; then
  if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$LOG_FILE" "$LOG_FILE.old" 2>/dev/null
  fi
  if exec 3>>"$LOG_FILE"; then LOG_FD_OK=1; fi
fi 2>/dev/null

# log: action log and log file. log_file_only: log file only.
log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  printf '%s\n' "$line"
  if [ "$LOG_FD_OK" -eq 1 ]; then printf '%s\n' "$line" >&3; fi
}
log_file_only() {
  if [ "$LOG_FD_OK" -eq 1 ]; then printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&3; fi
}
pad() { printf '%-14s' "$1"; }

# finish CODE [SUMMARY]: writes the summary and the last line, then exits.
finish() {
  if [ -n "$2" ]; then log "$2"; fi
  log "===== Finished with exit code $1 ====="
  exit "$1"
}
wrong_input() {
  log "ERROR: $(pad 'WRONG INPUT')$1 Nothing ran."
  case "$MODE" in
    Audit|Run) finish 2 "Summary ($MODE): wrong input, nothing ran" ;;
    *)         finish 2 "Summary: wrong input, nothing ran" ;;
  esac
}
# block CODE TEXT: a check stopped the command. Audit mode always exits 0.
block() {
  log "WARNING: $(pad BLOCKED)$2"
  if [ "$MODE" = "Audit" ]; then finish 0 "Summary (Audit, nothing changed): would run=0; blocked=1"; fi
  finish "$1" "Summary (Run): blocked=1; nothing ran"
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ----- 1. URL-decode (matches .NET UnescapeDataString: '+' stays '+') -
# Only %XX with two hex digits is decoded. A real backslash is kept as typed
# (the old decoder passed the text through printf %b, which turned \n, \t and
# \c into control actions if a backslash ever arrived unencoded).
urldecode() {
  local s="${1//\\/\\\\}"
  s="$(printf '%s' "$s" | sed 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
  printf '%b' "$s"
}

# ----- 0. Parameters ----------------------------------------------------
# Decodes one parameter, strips spaces and quotes at both ends, and falls back
# to the default when the value is empty. Used for Mode. The command itself is
# decoded only, because a command can start or end with a quote.
get_param() {
  local value
  value="$(urldecode "$1" | sed -e "s/^[[:space:]\"']*//" -e "s/[[:space:]\"']*\$//")"
  if [ -n "$value" ]; then printf '%s' "$value"; else printf '%s' "$2"; fi
}
MODE="$(get_param "$1" "Audit")"
RAW="$2"
# A NUL byte cannot be held in a shell variable. Such a value is not decoded; it is refused below.
case "$RAW" in
  *%00*) CMD="$RAW" ;;
  *)     CMD="$(urldecode "$RAW")" ;;
esac

log "===== $SCRIPT_NAME $SCRIPT_VERSION started on $HOST ====="
# The command is logged as typed, so a secret in it is logged too.
log "Settings: mode=$MODE; command=$CMD"

case "$(lower "$MODE")" in
  audit) MODE="Audit" ;;
  run)   MODE="Run" ;;
  *)     wrong_input "Mode must be Audit or Run. Got: $MODE." ;;
esac
if [ "$#" -gt 2 ]; then
  wrong_input "the script received $# values instead of 2. The command was split before it reached the script, so the quoting or URL-encoding broke."
fi
case "$RAW" in
  *%00*) wrong_input "the command contains a NUL byte (%00)." ;;
esac
if [ -z "${CMD//[[:space:]]/}" ]; then
  wrong_input "the command is empty."
fi

# lowercase, whitespace-collapsed copy, for matching only (WS keeps the case)
WS="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')"
LC="$(lower "$WS")"
B='(^|[^[:alnum:]_])'      # word start
E='([^[:alnum:]_]|$)'      # word end
# B and E each consume one character, so "systemctl stop" needs two spaces between
# the words for E and B to both match. The copies used for matching get every space doubled.
LCM=" $(printf '%s' "$LC" | sed 's/ /  /g') "
WSM=" $(printf '%s' "$WS" | sed 's/ /  /g') "
has()    { printf '%s' "$LCM" | grep -Eq -- "$1"; }
has_cs() { printf '%s' "$WSM" | grep -Eq -- "$1"; }

# ----- 2. Hard blocks (decode-and-execute) ---------------------------
if has "base64[^|;&]*[[:space:]](-[a-z]*d[a-z]*|--decode)${E}" && \
   has "\\|[[:space:]]*(sudo[[:space:]]+)?([a-z0-9_./-]*/)?(ba|da|z|k)?sh${E}|${B}(eval|source)${E}|${B}(ba|da|z|k)?sh[[:space:]]+-[a-z]*c${E}|<\\("; then
  block 6 "decode-and-execute pattern is not allowed."
fi

# ----- protected-path lists (all lowercase, no spaces) ----------------
# ALLOWED : may be deleted even though the folder above is protected
# SUBTREE : the folder and everything in it
# EXACT   : the folder itself and "folder/*", but not single items inside it
# AGENT   : security agent folders (reported with exit code 4)
# A path is also protected when it is a PARENT of a protected folder
# (/var holds /var/lib), and when a wildcard in it could match one (/e*).
ALLOWED_ROOTS="/usr/local /var/lib/apt/lists /dev/shm"
SUBTREE_ROOTS="/bin /sbin /boot /lib /lib32 /lib64 /libx32 /usr /etc /var/lib /var/db /dev /proc /sys /system /library/launchdaemons /private/etc /private/var/db"
EXACT_ROOTS="/var /home /root /opt /srv /mnt /media /run /private /private/var /users /applications /library /volumes"
AGENT_ROOTS="/opt/crowdstrike /opt/tanium /opt/cyberark /opt/carkaim /library/tanium /library/cs /applications/falcon.app"
AGENT_VENDOR='crowdstrike|falcon|cyberark|cybr|carkaim|tanium'

# When Tanium runs this, the script sits in <TaniumClient>/Downloads/Action_<id>.
# Protect the client folder wherever it is installed, but let the operator
# clean this action's own folder.
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
case "$SCRIPT_DIR" in
  *" "*) ;;
  */Downloads/Action_*)
    AGENT_ROOTS="$AGENT_ROOTS $(lower "${SCRIPT_DIR%/Downloads/Action_*}")"
    ALLOWED_ROOTS="$ALLOWED_ROOTS $(lower "$SCRIPT_DIR")"
    ;;
esac

split_path() {   # $1 = normalized absolute path. Fills SEGS with its parts.
  local IFS=/
  SEGS=($1)
  SEGS=("${SEGS[@]:1}")
}

norm_path() {    # collapses //, /./ and /../ . Result in NP.
  local p="$1" out="" seg IFS=/
  for seg in $p; do
    case "$seg" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  [ -z "$out" ] && out="/"
  NP="$out"
}

canon_path() {   # resolves symlinks in the part before the first wildcard. Result in CP, or empty.
  CP=""
  command -v realpath >/dev/null 2>&1 || return 0
  local p="$1" prefix="" rest="" seg glob=0 r IFS=/
  for seg in $p; do
    [ -z "$seg" ] && continue
    if [ "$glob" -eq 0 ]; then case "$seg" in *[*?[]*) glob=1 ;; esac; fi
    if [ "$glob" -eq 0 ]; then prefix="$prefix/$seg"; else rest="$rest/$seg"; fi
  done
  [ -z "$prefix" ] && return 0
  r="$(realpath -m -- "$prefix" 2>/dev/null || realpath -- "$prefix" 2>/dev/null)"
  if [ -n "$r" ] && [ "$r" != "$prefix" ]; then CP="$r$rest"; fi
  return 0
}

root_overlap() { # compares PSEG (typed path) with RSEG (protected root).
                 # OV: 0 no overlap, 1 typed path is the root or a parent of it, 2 typed path is inside the root
  local n=${#PSEG[@]} m=${#RSEG[@]} k i
  k=$n; [ "$m" -lt "$k" ] && k=$m
  for ((i = 0; i < k; i++)); do
    # the right side is a glob pattern on purpose: a typed "e*" matches the root "etc"
    [[ "${RSEG[i]}" == ${PSEG[i]} ]] || { OV=0; return 0; }
  done
  if [ "$n" -le "$m" ]; then OV=1; else OV=2; fi
  return 0
}

check_path() {   # $1 = lowercase normalized path, $2 = rm | find. Returns 0 and sets KIND (os/agent) when protected.
  local p="$1" mode="$2" r i n m last same
  KIND=""
  split_path "$p"; PSEG=("${SEGS[@]}")
  n=${#PSEG[@]}
  for r in $ALLOWED_ROOTS; do                       # allow wins
    split_path "$r"; RSEG=("${SEGS[@]}")
    m=${#RSEG[@]}
    if [ "$n" -ge "$m" ]; then
      same=1
      for ((i = 0; i < m; i++)); do [ "${PSEG[i]}" = "${RSEG[i]}" ] || { same=0; break; }; done
      [ "$same" -eq 1 ] && return 1
    fi
  done
  if [ "$n" -eq 0 ]; then KIND=os; return 0; fi     # "/" itself
  last="${PSEG[n-1]}"
  for r in $SUBTREE_ROOTS; do
    split_path "$r"; RSEG=("${SEGS[@]}")
    root_overlap
    if [ "$OV" -ne 0 ]; then KIND=os; return 0; fi
  done
  for r in $EXACT_ROOTS; do
    split_path "$r"; RSEG=("${SEGS[@]}")
    m=${#RSEG[@]}
    root_overlap
    if [ "$OV" -eq 1 ]; then
      # "find /home -name x -delete" is not the same as deleting /home, so find may start at an EXACT root
      if [ "$mode" = find ] && [ "$n" -eq "$m" ]; then :; else KIND=os; return 0; fi
    elif [ "$OV" -eq 2 ] && [ "$mode" != find ] && [ "$n" -eq $((m + 1)) ] && [ "$last" = "*" ]; then
      KIND=os; return 0
    fi
  done
  for r in $AGENT_ROOTS; do
    split_path "$r"; RSEG=("${SEGS[@]}")
    root_overlap
    if [ "$OV" -ne 0 ]; then KIND=agent; return 0; fi
  done
  return 1
}

# ----- command reader --------------------------------------------------
# Not a real shell parser. It splits the command into words (honouring quotes
# and backslashes), finds rm / unlink / rmdir / shred / find -delete / rsync
# --delete / cd / kill, and looks inside sh -c "..." and eval "...".
SEP=$'\001'      # marks ; | & ( ) < > and newlines
tokenize() {     # $1 = text. Fills TOK.
  local s="$1" n=${#1} i c nx w="" inw=0 q=""
  TOK=()
  for ((i = 0; i < n; i++)); do
    c="${s:i:1}"
    if [ "$q" = "'" ]; then
      if [ "$c" = "'" ]; then q=""; else w+="$c"; fi
      continue
    fi
    if [ "$q" = '"' ]; then
      case "$c" in
        '"') q="" ;;
        '\') nx="${s:i+1:1}"
             case "$nx" in '"'|'\'|'$'|'`') w+="$nx"; i=$((i + 1)) ;; *) w+="$c" ;; esac ;;
        '`') w+='$' ;;                              # command substitution: mark the word as dynamic
        *)   w+="$c" ;;
      esac
      continue
    fi
    case "$c" in
      "'"|'"') q="$c"; inw=1 ;;
      '\') nx="${s:i+1:1}"; i=$((i + 1))
           if [ "$nx" != $'\n' ]; then w+="$nx"; inw=1; fi ;;
      ' '|$'\t')
           if [ "$inw" -eq 1 ]; then TOK+=("$w"); w=""; inw=0; fi ;;
      ';'|'|'|'&'|'('|')'|'<'|'>'|$'\n'|$'\r')
           if [ "$inw" -eq 1 ]; then TOK+=("$w"); w=""; inw=0; fi
           TOK+=("$SEP") ;;
      '`') w+='$'; TOK+=("$w"); w=""; inw=0; TOK+=("$SEP") ;;
      '#') if [ "$inw" -eq 0 ]; then
             while [ "$i" -lt "$n" ] && [ "${s:i:1}" != $'\n' ]; do i=$((i + 1)); done
             i=$((i - 1))
           else w+="$c"; fi ;;
      *)   w+="$c"; inw=1 ;;
    esac
  done
  if [ "$inw" -eq 1 ]; then TOK+=("$w"); fi
  return 0
}

DEL_ARGS=()        # paths handed to rm / unlink / rmdir / shred / srm, and rsync --delete targets
FIND_ROOTS=()      # start folders of a find that deletes
CD_TARGETS=()      # cd / pushd targets, in order
ALL_WORDS=()       # every word seen at any depth, for the conservative scan
KILL_PIDS=()       # numeric arguments of kill
delete_seen=0      # a delete command was found
delete_unbound=0   # a delete whose paths arrive on stdin (xargs rm)

seg_end() {        # closes one command. Uses the locals of scan_text (bash dynamic scope).
  local lastarg
  if [ "$infind" -eq 1 ] && [ "$find_deletes" -eq 1 ]; then
    if [ "${#froots[@]}" -eq 0 ]; then froots=("."); fi
    FIND_ROOTS+=("${froots[@]}")
    delete_seen=1
  fi
  if [ "$mode" = rsync ] && [ "$rs_delete" -eq 1 ] && [ "${#rs_args[@]}" -ge 2 ]; then
    lastarg="${rs_args[${#rs_args[@]}-1]}"
    case "$lastarg" in
      *:*) ;;                                       # remote target: not checked
      *)   DEL_ARGS+=("$lastarg"); delete_seen=1 ;;
    esac
  fi
  if [ "$mode" = cd ] && [ "$cd_seen" -eq 0 ]; then CD_TARGETS+=("${HOME:-/root}"); fi   # plain "cd" goes home
  expect=1; mode=""; wrapper=""; optsdone=0; skipnext=0; chroot_dir=0
  infind=0; inexec=0; find_deletes=0; find_roots_open=0; via_xargs=0; cd_seen=0
  froots=(); rs_args=(); rs_delete=0
  return 0
}

scan_text() {      # $1 = command text, $2 = nesting depth
  local depth="$2"
  [ "$depth" -gt 6 ] && return 0
  tokenize "$1"
  local -a W=("${TOK[@]}")
  local n=${#W[@]} i=0 w lw rest
  local expect=1 mode="" wrapper="" optsdone=0 skipnext=0 chroot_dir=0
  local infind=0 inexec=0 find_deletes=0 find_roots_open=0 via_xargs=0 cd_seen=0 rs_delete=0
  local -a froots=() rs_args=()

  while [ "$i" -lt "$n" ]; do
    w="${W[i]}"; i=$((i + 1))
    if [ "$w" = "$SEP" ]; then seg_end; continue; fi
    ALL_WORDS+=("$w")
    if [ "$skipnext" -eq 1 ]; then skipnext=0; continue; fi

    if [ "$expect" -eq 1 ]; then
      # --- still looking for the command word
      case "$w" in
        -*)
          # an option of a wrapper such as sudo, xargs, bash, timeout
          case "$wrapper" in
            sh|su)
              case "$w" in
                --*) ;;
                -*c*)                               # sh -c "text": read the text as a command
                  if [ "$i" -lt "$n" ] && [ "${W[i]}" != "$SEP" ]; then
                    ALL_WORDS+=("${W[i]}")
                    scan_text "${W[i]}" $((depth + 1))
                    i=$((i + 1))
                  fi
                  mode=other; expect=0 ;;
              esac ;;
            sudo)   case "$w" in -u|-g|-U|-h|-p|-C|-r|-t|-T|-D) skipnext=1 ;; esac ;;
            xargs)  case "$w" in -n|-I|-P|-L|-d|-a|-s|-E) skipnext=1 ;; esac ;;
            nice)   case "$w" in -n) skipnext=1 ;; esac ;;
            ionice) case "$w" in -c|-n|-p) skipnext=1 ;; esac ;;
            timeout) case "$w" in -s|-k) skipnext=1 ;; esac ;;
            env)    case "$w" in -u|-C) skipnext=1 ;; esac ;;
          esac
          continue ;;
        *=*) continue ;;                            # VAR=value in front of the command
      esac
      if [ -n "$wrapper" ]; then
        case "$w" in
          [0-9]|[0-9]*[0-9smhd]) case "$w" in *[!0-9.smhd]*) ;; *) continue ;; esac ;;   # timeout 30s, nice 10
        esac
        if [ "$wrapper" = chroot ] && [ "$chroot_dir" -eq 0 ]; then chroot_dir=1; continue; fi
        if [ "$wrapper" = su ]; then continue; fi   # su - user -c "..."
      fi
      lw="$(lower "${w##*/}")"
      case "$lw" in
        sudo|xargs|nice|ionice|timeout|env|chroot)
          wrapper="$lw"; [ "$lw" = xargs ] && via_xargs=1; continue ;;
        doas|nohup|time|command|exec|builtin|busybox|stdbuf|setsid|watch|then|else|elif|do|if|while|until|'!'|'{')
          wrapper=gen; continue ;;
        sh|bash|dash|zsh|ksh|ash)
          wrapper=sh; continue ;;
        su|runuser)
          wrapper=su; continue ;;
        eval)
          rest=""
          while [ "$i" -lt "$n" ] && [ "${W[i]}" != "$SEP" ]; do
            ALL_WORDS+=("${W[i]}"); rest="$rest ${W[i]}"; i=$((i + 1))
          done
          scan_text "$rest" $((depth + 1))
          mode=other; expect=0 ;;
        rm|unlink|rmdir|shred|srm)
          mode=del; expect=0; optsdone=0; delete_seen=1
          [ "$via_xargs" -eq 1 ] && delete_unbound=1 ;;
        find)
          mode=find; expect=0; infind=1; find_roots_open=1; find_deletes=0; froots=() ;;
        cd|pushd)
          mode=cd; expect=0; cd_seen=0 ;;
        rsync)
          mode=rsync; expect=0; rs_args=(); rs_delete=0 ;;
        kill)
          mode=kill; expect=0 ;;
        *)
          mode=other; expect=0 ;;
      esac
      continue
    fi

    # --- arguments of the command
    if [ "$inexec" -eq 1 ] && { [ "$w" = ";" ] || [ "$w" = "+" ]; }; then
      mode=find; inexec=0; continue                 # end of find -exec ... \;
    fi
    case "$mode" in
      del)
        if [ "$inexec" -eq 1 ] && [ "$w" = "{}" ]; then find_deletes=1; continue; fi
        if [ "$optsdone" -eq 0 ]; then
          if [ "$w" = "--" ]; then optsdone=1; continue; fi
          case "$w" in -*) continue ;; esac
        fi
        DEL_ARGS+=("$w") ;;
      find)
        if [ "$find_roots_open" -eq 1 ]; then
          case "$w" in
            -*|'!'|'(') find_roots_open=0 ;;
            *) froots+=("$w"); continue ;;
          esac
        fi
        case "$w" in
          -delete) find_deletes=1 ;;
          -exec|-execdir|-ok|-okdir) expect=1; wrapper=""; inexec=1 ;;
        esac ;;
      cd)
        if [ "$cd_seen" -eq 0 ]; then
          case "$w" in
            -) CD_TARGETS+=('$OLDPWD'); cd_seen=1 ;;
            -*) ;;
            *) CD_TARGETS+=("$w"); cd_seen=1 ;;
          esac
        fi ;;
      rsync)
        case "$w" in
          --delete*|--del|--remove-source-files) rs_delete=1 ;;
          -*) ;;
          *) rs_args+=("$w") ;;
        esac ;;
      kill)
        case "$w" in
          -*|*[!0-9]*) ;;
          *) KILL_PIDS+=("$w") ;;
        esac ;;
    esac
  done
  seg_end
  return 0
}

BASES=("$PWD")     # folders a relative path could be resolved against
cd_dynamic=0       # a cd whose target this script cannot read
resolve_arg() {    # $1 = path as typed. Fills RES with absolute normalized forms. Sets RES_UNKNOWN=1 for ~user.
  local a="$1" b
  RES=(); RES_UNKNOWN=0
  # {a,b} and {1..3} can expand to anything in the list: treat them as a wildcard
  a="$(printf '%s' "$a" | sed 's/{[^{}]*[,.][^{}]*}/*/g')"
  case "$a" in
    "~")   a="${HOME:-/root}" ;;
    "~/"*) a="${HOME:-/root}/${a#??}" ;;
    "~"*)  RES_UNKNOWN=1; return 0 ;;
  esac
  case "$a" in
    /*) norm_path "$a"; RES=("$NP") ;;
    *)  for b in "${BASES[@]}"; do norm_path "$b/$a"; RES+=("$NP"); done ;;
  esac
  return 0
}

HIT_KIND=""; HIT_TYPED=""; HIT_PATH=""; DYNAMIC_ARG=""; REL_AFTER_CD=""
check_delete_arg() {   # $1 = argument as typed, $2 = rm | find. Records the first protected hit.
  local a="$1" mode="$2" p cand low
  [ -n "$HIT_KIND" ] && return 0
  case "$a" in
    *'$'*) [ -z "$DYNAMIC_ARG" ] && DYNAMIC_ARG="$a"; return 0 ;;
  esac
  resolve_arg "$a"
  if [ "$RES_UNKNOWN" -eq 1 ]; then [ -z "$DYNAMIC_ARG" ] && DYNAMIC_ARG="$a"; return 0; fi
  case "$a" in
    /*|"~"*) ;;
    *) if [ "$cd_dynamic" -eq 1 ] && [ -z "$REL_AFTER_CD" ]; then REL_AFTER_CD="$a"; fi ;;
  esac
  for p in "${RES[@]}"; do
    canon_path "$p"
    for cand in "$p" "$CP"; do
      [ -z "$cand" ] && continue
      low="$(lower "$cand")"
      if check_path "$low" "$mode"; then
        HIT_KIND="$KIND"; HIT_TYPED="$a"; HIT_PATH="$cand"
        return 0
      fi
    done
  done
  return 0
}

scan_text "$CMD" 0

# folders a relative path could mean: the current folder plus every cd target
for t in "${CD_TARGETS[@]}"; do
  case "$t" in
    *'$'*) cd_dynamic=1; continue ;;
  esac
  resolve_arg "$t"
  if [ "$RES_UNKNOWN" -eq 1 ]; then cd_dynamic=1; continue; fi
  for p in "${RES[@]}"; do BASES+=("$p"); done
done

# ----- 3. Delete protection ------------------------------------------
if [ "$delete_seen" -eq 1 ]; then
  if has '--no-preserve-root'; then
    block 3 "--no-preserve-root is not allowed."
  fi

  for a in "${DEL_ARGS[@]}";   do check_delete_arg "$a" rm;   done
  for a in "${FIND_ROOTS[@]}"; do check_delete_arg "$a" find; done

  # a delete fed by xargs has no paths of its own: test every absolute path in the command
  if [ "$delete_unbound" -eq 1 ]; then
    saved_dynamic="$DYNAMIC_ARG"
    for a in "${ALL_WORDS[@]}"; do
      case "$a" in /*|"~"|"~/"*) check_delete_arg "$a" rm ;; esac
    done
    DYNAMIC_ARG="$saved_dynamic"
  fi

  # rm against / or /*  (root)
  if [ -z "$HIT_KIND" ] && has "${B}rm${E}[^|;&]*[[:space:]](/|/\\*)([[:space:]]|\$)"; then
    HIT_KIND=os; HIT_TYPED="/"; HIT_PATH="/"
  fi

  if [ -n "$HIT_KIND" ]; then
    shown="'$HIT_PATH'"
    [ "$HIT_TYPED" != "$HIT_PATH" ] && shown="'$HIT_TYPED' (checked as '$HIT_PATH')"
    if [ "$HIT_KIND" = agent ]; then
      block 5 "command deletes $shown, which belongs to a protected security agent (CrowdStrike, Tanium, or CyberArk)."
    fi
    block 3 "command deletes $shown, a protected OS path."
  fi
  if [ -n "$DYNAMIC_ARG" ]; then
    block 3 "command deletes '$DYNAMIC_ARG', a path built from a variable or a command substitution, so this script cannot check it."
  fi
  if [ -n "$REL_AFTER_CD" ]; then
    block 3 "command deletes the relative path '$REL_AFTER_CD' after a cd whose target this script cannot read."
  fi
fi

# disk / filesystem wipes - blocked outright
disk_hit=0
DISK="${B}(mkfs(\\.[a-z0-9]+)?|wipefs|blkdiscard|lvremove|vgremove|pvremove)${E}"
DISK="$DISK|${B}(zpool|zfs)[[:space:]]+destroy${E}"
DISK="$DISK|${B}parted${E}[^|;&]*[[:space:]](rm|mklabel|mktable)${E}"
DISK="$DISK|${B}cryptsetup${E}[^|;&]*[[:space:]](luksformat|lukserase|erase)${E}"
DISK="$DISK|${B}nvme[[:space:]]+format${E}"
DISK="$DISK|${B}diskutil[[:space:]]+(erasedisk|erasevolume|reformat|zerodisk|randomdisk|secureerase|partitiondisk|apfs[[:space:]]+delete[a-z]*)${E}"
DISK="$DISK|>[[:space:]]*/dev/(sd|nvme|disk|rdisk|vd|xvd|hd|mmcblk|dm-|mapper/|md)"
if has "$DISK"; then disk_hit=1; fi
# sgdisk: -Z/-z/-o wipe, but -O only prints, so this one is case-sensitive
if has_cs "${B}sgdisk${E}[^|;&]*[[:space:]](-z|-Z|-o|--zap|--zap-all|--clear)${E}"; then disk_hit=1; fi
# dd to a device, except the harmless ones (of=/dev/null and friends)
if has "${B}dd${E}"; then
  while IFS= read -r target; do
    case "$target" in
      ''|of=/dev/null|of=/dev/zero|of=/dev/full|of=/dev/stdout|of=/dev/stderr|of=/dev/tty*|of=/dev/fd/*|of=/dev/shm/*|of=/dev/random|of=/dev/urandom) ;;
      *) disk_hit=1 ;;
    esac
  done <<EOF
$(printf '%s' "$LC" | grep -Eo 'of=/dev/[^[:space:]|;&]*')
EOF
fi
if [ "$disk_hit" -eq 1 ]; then
  block 3 "raw disk/filesystem write (mkfs/dd/wipefs or a partition tool on a device) is not allowed."
fi

# power off. A powered-off endpoint cannot be started again from Tanium. A restart is allowed.
# shutdown with no -r (Linux shutdown powers off by default), poweroff, halt, init 0,
# systemctl poweroff/halt/suspend/hibernate.
# CMDPOS: the word is where a command starts (start of the line, after ; & | ( or a
# backtick, after sudo/doas/nohup/exec, or right after sh -c), so "last -x shutdown" is not a hit.
CMDPOS="(^|[;&|(\`]|sudo|doas|nohup|exec|-c[[:space:]]+[\"']?)[[:space:]]*([^[:space:]]*/)?"
power_off=0
if has "${CMDPOS}(poweroff|halt)${E}|${B}(tel)?init[[:space:]]+0${E}|${B}systemctl${E}[^|;&]*${B}(poweroff|halt|suspend|hibernate|hybrid-sleep|suspend-then-hibernate)${E}"; then
  power_off=1
fi
if has "${CMDPOS}shutdown${E}" && ! has "${CMDPOS}shutdown${E}[^|;&]*[[:space:]](-r|--reboot|-c|-k)${E}"; then
  power_off=1
fi
if [ "$power_off" -eq 1 ]; then
  block 3 "command shuts down, powers off, or suspends the endpoint. Tanium cannot start it again. Use a restart instead (shutdown -r now or reboot)."
fi

# ----- 4. Security-agent protection ----------------------------------
agent_verb=0
VERB="${B}(systemctl|service)${E}[^|;&]*${B}(stop|disable|mask|kill)${E}"
VERB="$VERB|init\\.d/[^[:space:]]+[[:space:]]+stop${E}"
VERB="$VERB|${B}launchctl${E}[^|;&]*${B}(unload|bootout|disable|remove|stop|kill)${E}"
VERB="$VERB|${B}(kill|pkill|killall)${E}"
VERB="$VERB|${B}rpm${E}[^|;&]*[[:space:]](-[a-z]*e[a-z]*|--erase)${E}"
VERB="$VERB|${B}(apt|apt-get|aptitude|yum|dnf|zypper|snap)${E}[^|;&]*${B}(remove|purge|erase|autoremove)${E}"
VERB="$VERB|${B}brew${E}[^|;&]*uninstall|${B}pkgutil${E}[^|;&]*--forget"
VERB="$VERB|${B}chkconfig${E}[^|;&]*[[:space:]](off|--del)${E}|${B}update-rc\\.d${E}[^|;&]*${B}(disable|remove)${E}"
# falconctl -g (read a setting) is allowed. -s (set), -d (delete) and uninstall/unload/disable are not.
VERB="$VERB|${B}falconctl${E}[^|;&]*[[:space:]](-[a-z]*[sd][a-z]*|uninstall|unload|disable)${E}"
if has "$VERB"; then agent_verb=1; fi
# dpkg: -r and -P remove, but -p only prints, so this one is case-sensitive
if has_cs "${B}dpkg${E}[^|;&]*[[:space:]](-r|-P|--remove|--purge)${E}"; then agent_verb=1; fi

if [ "$agent_verb" -eq 1 ] && has "$AGENT_VENDOR"; then
  block 5 "command targets a protected security agent (CrowdStrike, Tanium, or CyberArk)."
fi

# kill by PID has no vendor word in it: look the PID up and test what it really is
for pid in "${KILL_PIDS[@]}"; do
  pinfo="$(ps -p "$pid" -o args= 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  if [ -n "$pinfo" ] && printf '%s' "$pinfo" | grep -Eq -- "$AGENT_VENDOR"; then
    block 5 "command kills process $pid, which belongs to a protected security agent (CrowdStrike, Tanium, or CyberArk)."
  fi
done

# ----- 5. Run ---------------------------------------------------------
if [ "$MODE" = "Audit" ]; then
  log "WOULD RUN     the checks passed. Run mode would run the command."
  finish 0 "Summary (Audit, nothing changed): would run=1; blocked=0"
fi

log "$(pad RUNNING)the checks passed. Output follows."
out_total=0
rc=0
# >>> EXECUTE-BEGIN  (test tools swap this block out to build a copy that never runs the command)
RC_FILE="$(mktemp 2>/dev/null)"
if [ -z "$RC_FILE" ]; then
  log "ERROR: could not make a temp file, so the command did not run."
  finish 4 "Summary (Run): unexpected problem, nothing ran"
fi
# Standard output and errors of the command, together. Blank lines are dropped so
# they do not use up the action log lines.
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac
  out_total=$((out_total + 1))
  if [ "$out_total" -le "$MAX_ACTION_LOG_OUTPUT_LINES" ]; then printf '%s\n' "$line"; fi
  if [ "$LOG_FD_OK" -eq 1 ] && [ "$out_total" -le "$MAX_FILE_OUTPUT_LINES" ]; then printf '%s\n' "$line" >&3; fi
done < <(bash -c "$CMD" 2>&1; printf '%s' "$?" > "$RC_FILE")
rc="$(cat "$RC_FILE" 2>/dev/null)"
rm -f "$RC_FILE"
[ -z "$rc" ] && rc=1
# <<< EXECUTE-END

log_file_only "Output lines: $out_total"
if [ "$out_total" -gt "$MAX_ACTION_LOG_OUTPUT_LINES" ]; then
  if [ "$LOG_FD_OK" -eq 1 ]; then where="The log file $LOG_FILE has up to $MAX_FILE_OUTPUT_LINES."
  else where="There is no log file (the script cannot write $LOG_FILE)."; fi
  log "WARNING: $(pad TRUNCATED)the action log shows the first $MAX_ACTION_LOG_OUTPUT_LINES of $out_total output lines. $where"
fi
if [ "$rc" != "0" ]; then
  log "ERROR: $(pad FAILED)the command returned exit code $rc."
  finish 1 "Summary (Run): ran=1; failed=1; command exit code=$rc"
fi
log "$(pad RAN)the command returned exit code 0."
finish 0 "Summary (Run): ran=1; failed=0"
