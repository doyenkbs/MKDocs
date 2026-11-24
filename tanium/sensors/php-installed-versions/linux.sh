#!/bin/sh
# Tanium sensor: PHP - Installed Versions (Linux)
#
# Sensor settings
#   Script type : UnixShell
#   Parameters  : none
#   Result type : Text, split into columns, delimiter |
#   Columns     : PHP Path | Type | Version | Package | Running
#                 (all Text)
#
# Finds the PHP programs (php, php-cgi, php-fpm, phpdbg, lsphp) and the Apache
# PHP module (libphp*.so) in the usual install folders and in running processes.
# For each one it returns the PHP version, the package that installed it, and
# whether a process uses it now.
# Skips helper scripts such as php-config and phpize. Does not look inside
# containers.
# POSIX sh. No Python or Incident Response tools required.
# Read-only: nothing is written.

TIME_LIMIT=20   # seconds; keep below the sensor timeout
start=$(date -u +%s)

PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export LC_ALL=C

NL='
'

# A | inside a value would split the row into the wrong columns.
clean() { printf '%s' "$1" | tr '|\t\r\n' '/   '; }

over_time() { [ $(($(date -u +%s) - start)) -ge "$TIME_LIMIT" ]; }

# A real program or library starts with the 4 bytes 0x7F E L F.
# This skips shell wrapper scripts with PHP names.
is_elf() { [ "$(dd if="$1" bs=1 skip=1 count=3 2>/dev/null)" = "ELF" ]; }

# The kind of PHP file, from its name. Empty means "not a PHP program".
php_type() {
    case "${1##*/}" in
        libphp*.so)          echo "Apache module" ;;
        php-fpm*|php*-fpm)   echo "FPM" ;;
        php-cgi*|php*-cgi)   echo "CGI" ;;
        phpdbg*)             echo "Debugger" ;;
        lsphp*)              echo "LiteSpeed" ;;
        php|php[0-9]*)       echo "CLI" ;;
        *)                   echo "" ;;
    esac
}

# --- Find the PHP files -------------------------------------------------------
# Each file is kept once, by its real path (symbolic links resolved).
found=''
add() {
    real=$(readlink -f "$1" 2>/dev/null) || return 0
    [ -f "$real" ] || return 0
    [ -n "$(php_type "$real")" ] || return 0
    is_elf "$real" || return 0
    case "$NL$found" in *"$NL$real$NL"*) return 0 ;; esac
    found="$found$real$NL"
}

# 1. Usual install folders: distribution packages, Remi, Red Hat Software
#    Collections, cPanel, Plesk, LiteSpeed, and builds in /usr/local.
for f in /usr/bin/php* /usr/sbin/php* /usr/local/bin/php* /usr/local/sbin/php* \
         /usr/local/php*/bin/php* /usr/local/php*/sbin/php* \
         /opt/remi/php*/root/usr/bin/php* /opt/remi/php*/root/usr/sbin/php* \
         /opt/rh/*php*/root/usr/bin/php* /opt/rh/*php*/root/usr/sbin/php* \
         /opt/cpanel/ea-php*/root/usr/bin/php* /opt/cpanel/ea-php*/root/usr/sbin/php* \
         /opt/plesk/php/*/bin/php* /opt/plesk/php/*/sbin/php* \
         /usr/local/lsws/lsphp*/bin/lsphp \
         /usr/lib64/httpd/modules/libphp*.so /usr/lib/httpd/modules/libphp*.so \
         /usr/lib/apache2/modules/libphp*.so /usr/local/apache2/modules/libphp*.so \
         /opt/remi/php*/root/usr/lib64/httpd/modules/libphp*.so; do
    [ -e "$f" ] && add "$f"
done

# 2. Running processes. This finds PHP in folders that are not in the list above.
#    An upgraded program that still runs shows as "<path> (deleted)".
procs=''
for d in /proc/[0-9]*; do
    exe=$(readlink "$d/exe" 2>/dev/null) || continue   # kernel threads have no exe
    procs="$procs$exe$NL"
    case "${exe##*/}" in php*|lsphp*) add "${exe% (deleted)}" ;; esac
done

# Libraries that running processes use (for the Apache module).
maps=$(cat /proc/[0-9]*/maps 2>/dev/null | grep -F 'libphp' | awk '{print $6, $7}' | sort -u)

# --- Facts about each file ----------------------------------------------------
# Package that installed the file: "name version", or nothing.
pkg_info() {
    if command -v rpm >/dev/null 2>&1; then
        out=$(rpm -qf --qf '%{NAME} %{VERSION}-%{RELEASE}\n' "$1" 2>/dev/null) || out=''
        if [ -n "$out" ]; then printf '%s' "$out" | head -1; return; fi
    fi
    if command -v dpkg-query >/dev/null 2>&1; then
        name=$(dpkg-query -S "$1" 2>/dev/null | head -1 | sed 's/: .*//')
        if [ -n "$name" ]; then
            ver=$(dpkg-query -W -f='${Version}' "$name" 2>/dev/null)
            printf '%s %s' "${name%%:*}" "$ver"
        fi
    fi
}

# PHP version from the program itself. -n: no php.ini, so no extension loads.
# Needs the timeout command, so a program that does not answer cannot stop the sensor.
bin_version() {
    command -v timeout >/dev/null 2>&1 || return 0
    timeout 5 "$1" -n -v </dev/null 2>/dev/null | sed -n '1s/^PHP \([0-9][0-9.]*[0-9]\).*/\1/p'
}

# "Yes", "Yes, restart needed" (the file was replaced after the process started), or "No".
running_state() {
    if [ "$2" = "Apache module" ]; then
        if printf '%s\n' "$maps" | grep -qxF "$1 "; then echo "Yes"; return; fi
        if printf '%s\n' "$maps" | grep -qxF "$1 (deleted)"; then echo "Yes, restart needed"; return; fi
    else
        if printf '%s' "$procs" | grep -qxF "$1"; then echo "Yes"; return; fi
        if printf '%s' "$procs" | grep -qxF "$1 (deleted)"; then echo "Yes, restart needed"; return; fi
    fi
    echo "No"
}

rows=''
timed=0
oldifs=$IFS
IFS=$NL
for p in $found; do
    IFS=$oldifs
    if over_time; then timed=1; break; fi

    type=$(php_type "$p")
    pkg=$(pkg_info "$p")
    [ -n "$pkg" ] || pkg="No package"

    ver=''
    [ "$type" = "Apache module" ] || ver=$(bin_version "$p")
    if [ -z "$ver" ] && [ "$pkg" != "No package" ]; then
        # Package version without the epoch ("2:") and the distribution suffix.
        ver=$(printf '%s' "${pkg#* }" | sed -n 's/^[0-9]*://; s/^\([0-9][0-9.]*[0-9]\).*/\1/p')
    fi
    [ -n "$ver" ] || ver="Unknown"

    run=$(running_state "$p" "$type")

    rows="$rows$(clean "$p")|$(clean "$type")|$(clean "$ver")|$(clean "$pkg")|$(clean "$run")$NL"
done
IFS=$oldifs

# --- Output: never empty ------------------------------------------------------
#   None            no PHP found
#   Error: <reason> something failed
[ -n "$rows" ] && printf '%s' "$rows" | sort -u
[ "$timed" -eq 1 ] && echo "Error: Time limit reached, results incomplete||||"
[ -z "$rows" ] && [ "$timed" -eq 0 ] && echo "None||||"
exit 0
