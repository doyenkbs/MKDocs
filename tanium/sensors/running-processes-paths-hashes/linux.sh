#!/bin/sh
# Running Processes - Paths - Hashes (Linux)
# POSIX sh. No Python or Incident Response tools required.
# Output: <executable path>|#<hash>   (hash empty when HashType = NONE)
# Hash is computed from /proc/<pid>/exe, so deleted or replaced binaries
# and container processes hash the file actually running.

SEP='|#'
MAX_BYTES=1073741824
TAB=$(printf '\t')

HASH_TYPE='||HashType||'
case "$HASH_TYPE" in
  *HashType*|'') HASH_TYPE='MD5' ;;
esac
HASH_TYPE=$(printf '%s' "$HASH_TYPE" | tr '[:lower:]' '[:upper:]' | tr -d ' ')

case "$HASH_TYPE" in
  MD5)    HASH_CMD='md5sum' ;;
  SHA1)   HASH_CMD='sha1sum' ;;
  SHA256) HASH_CMD='sha256sum' ;;
  NONE)   HASH_CMD='' ;;
  *)
    echo "Error: Unsupported HashType '$HASH_TYPE'. Use MD5, SHA1, SHA256, or NONE."
    exit 0
    ;;
esac

if [ -n "$HASH_CMD" ] && ! command -v "$HASH_CMD" >/dev/null 2>&1; then
  echo "Error: $HASH_CMD not found on this endpoint."
  exit 0
fi

for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  exe=$(readlink "$d/exe" 2>/dev/null) || continue   # kernel threads have no exe
  [ -n "$exe" ] || continue
  printf '%s\t%s\n' "$exe" "$pid"
done | sort -t "$TAB" -k1,1 -u | while IFS="$TAB" read -r exe pid; do

  if [ -z "$HASH_CMD" ]; then
    printf '%s%s\n' "$exe" "$SEP"
    continue
  fi

  src="/proc/$pid/exe"
  size=$(stat -L -c %s "$src" 2>/dev/null)
  if [ -z "$size" ]; then
    echo "Error hashing $exe: process exited or file unreadable"
    continue
  fi
  if [ "$size" -gt "$MAX_BYTES" ]; then
    echo "Error hashing $exe: file exceeds 1 GB"
    continue
  fi

  h=$($HASH_CMD < "$src" 2>/dev/null | awk '{print $1}')
  if [ -n "$h" ]; then
    printf '%s%s%s\n' "$exe" "$SEP" "$h"
  else
    echo "Error hashing $exe: unable to read file"
  fi
done
