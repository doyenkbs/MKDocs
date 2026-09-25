#!/bin/bash
# =====================================================================
# Java - Runtime Inventory - Dependencies (Linux)
#
# Finds every Java runtime (JDK or JRE, package or tarball, standalone
# or bundled) and returns ALL of them, with what uses each one.
# No version list is built in: decide which versions are vulnerable with
# your vulnerability scanner or Interact filters on Java Line and Version.
#
# One row per Java runtime per dependency:
#   Java Path | Java Line | Version | Version String | Type | Vendor |
#   Installed By | Uninstall Command | Used By Type | Used By
#
# Command lines are never returned in full: only the jar name or main
# class is shown.
# =====================================================================
SCAN_SECONDS=30
EXTRA_SCAN_ROOTS=""     # optional, space separated, e.g. "/data/apps"

PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export LC_ALL=C
WORK=$(mktemp -d 2>/dev/null || { mkdir -p "/tmp/javavuln.$$"; echo "/tmp/javavuln.$$"; })
trap 'rm -rf "$WORK"' EXIT
HOMES="$WORK/homes"; RUNTIMES="$WORK/vuln"; DEPS="$WORK/deps"; REFS="$WORK/refs"
: > "$HOMES"; : > "$RUNTIMES"; : > "$DEPS"; : > "$REFS"

clean() { printf '%s' "$1" | tr '|\t\r\n' '/   '; }

add_home() {
    # $1 = a java binary or a Java home directory
    local p h parent
    [ -n "$1" ] || return 0
    p=$(readlink -f "$1" 2>/dev/null) || return 0
    if [ -f "$p" ]; then h=$(dirname "$(dirname "$p")"); else h="$p"; fi
    [ -x "$h/bin/java" ] || return 0
    case "$h" in
        */jre)
            parent=$(dirname "$h")
            if [ -x "$parent/bin/javac" ] || [ -f "$parent/release" ]; then h="$parent"; fi ;;
    esac
    echo "$h" >> "$HOMES"
}

# ---------- discovery ----------
for f in /usr/lib/jvm/*/bin/java /usr/lib/jvm/*/jre/bin/java /usr/java/*/bin/java /usr/java/*/jre/bin/java \
         /usr/lib64/jvm/*/bin/java /usr/local/java/*/bin/java /usr/local/jdk*/bin/java; do
    [ -x "$f" ] && add_home "$f"
done
command -v java >/dev/null 2>&1 && add_home "$(command -v java)"
[ -e /etc/alternatives/java ] && add_home /etc/alternatives/java
DEFAULT_HOME=""
if command -v java >/dev/null 2>&1; then
    d=$(readlink -f "$(command -v java)" 2>/dev/null)
    [ -n "$d" ] && DEFAULT_HOME=$(dirname "$(dirname "$d")")
    case "$DEFAULT_HOME" in */jre) [ -x "$(dirname "$DEFAULT_HOME")/bin/javac" ] && DEFAULT_HOME=$(dirname "$DEFAULT_HOME");; esac
fi

# Running Java processes
for pd in /proc/[0-9]*; do
    exe=$(readlink "$pd/exe" 2>/dev/null) || continue
    case "$exe" in */bin/java) add_home "$exe" ;; esac
done

# JAVA_HOME in system environment files
for f in /etc/environment /etc/profile /etc/profile.d/*.sh /etc/default/*; do
    [ -f "$f" ] || continue
    grep -hE '^[[:space:]]*(export[[:space:]]+)?(JAVA_HOME|JRE_HOME)=' "$f" 2>/dev/null |
        sed -E 's/^[^=]*=//; s/["'\'']//g; s/[[:space:]].*$//' | while read -r v; do add_home "$v"; done
done

# Folder search (stays on each folder's own file system, skips network mounts)
# SCAN_SECONDS is the total for all folders, not per folder.
ROOTS="/opt /usr/local /srv /app /apps /u01 /data $EXTRA_SCAN_ROOTS"
START=$(date +%s)
for r in $ROOTS; do
    [ -d "$r" ] || continue
    left=$((SCAN_SECONDS - ($(date +%s) - START)))
    [ "$left" -gt 0 ] || { touch "$WORK/truncated"; break; }
    timeout "$left" find "$r" -xdev -maxdepth 7 -type f -name java -path '*/bin/java' 2>/dev/null
    [ $? -eq 124 ] && touch "$WORK/truncated"
done | while read -r f; do add_home "$f"; done

sort -u "$HOMES" -o "$HOMES"

# ---------- version and vendor ----------
pkg_owner() {  # prints "package|remove command" or nothing
    local f="$1" out
    if command -v rpm >/dev/null 2>&1; then
        out=$(rpm -qf --qf '%{NAME}\n' "$f" 2>/dev/null | head -1)
        case "$out" in ""|*"not owned"*|*"No such"*) ;; *)
            if command -v dnf >/dev/null 2>&1; then echo "$out|dnf remove $out"; else echo "$out|yum remove $out"; fi; return ;; esac
    fi
    if command -v dpkg >/dev/null 2>&1; then
        out=$(dpkg -S "$f" 2>/dev/null | head -1 | cut -d: -f1)
        [ -n "$out" ] && { echo "$out|apt-get remove $out"; return; }
    fi
}

while read -r h; do
    [ -n "$h" ] || continue
    jv=""; impl=""
    if [ -f "$h/release" ]; then
        jv=$(sed -n 's/^JAVA_VERSION="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$h/release" | head -1)
        impl=$(sed -n 's/^IMPLEMENTOR="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$h/release" | head -1)
    fi
    if [ -z "$jv" ]; then
        jv=$(timeout 10 "$h/bin/java" -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -1)
    fi
    if [ -z "$impl" ]; then
        case "$(timeout 10 "$h/bin/java" -version 2>&1 | sed -n '2p')" in
            *"Java(TM)"*) impl="Oracle Corporation" ;;
            *OpenJDK*) impl="OpenJDK" ;;
            *IBM*) impl="IBM" ;;
            *) impl="unknown" ;;
        esac
    fi
    maj=""; min=0; pat=0
    case "$jv" in
        1.*) maj=$(echo "$jv" | cut -d. -f2 | tr -cd '0-9')
             pat=$(echo "$jv" | sed -n 's/^[^_]*_\([0-9]*\).*/\1/p') ;;
        [0-9]*) maj=$(echo "$jv" | cut -d. -f1 | tr -cd '0-9')
             min=$(echo "$jv" | cut -s -d. -f2 | sed 's/[^0-9].*//')
             pat=$(echo "$jv" | cut -s -d. -f3 | sed 's/[^0-9].*//') ;;
    esac
    [ -z "$min" ] && min=0; [ -z "$pat" ] && pat=0
    if [ -n "$maj" ]; then line="$maj"; norm="$maj.$min.$pat"; else line=unknown; norm=unknown; fi
    if [ -x "$h/bin/javac" ]; then type=JDK; else type=JRE; fi
    [ -z "$jv" ] && jv=unknown
    real=$(readlink -f "$h/bin/java")
    owner=$(pkg_owner "$real")
    if [ -n "$owner" ]; then
        by="Package ${owner%%|*}"; un="${owner#*|}"
    else
        case "$h" in
            /opt/*) app=$(echo "$h" | cut -d/ -f1-3); by="No package owner (inside $app)" ;;
            *) by="No package owner found" ;;
        esac
        un="None registered"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$h" "$h/bin/java" "$line" "$norm" "$jv" "$type" "$impl" "$by" "$un" >> "$RUNTIMES"
done < "$HOMES"

# ---------- dependencies ----------
if [ -s "$RUNTIMES" ]; then
    cut -f1 "$RUNTIMES" > "$WORK/runtimehomes"

    home_of() {  # prints the Java home that path $1 lives in
        local r h
        r=$(readlink -f "$1" 2>/dev/null) || return 1
        while read -r h; do
            case "$r" in "$h"|"$h"/*) echo "$h"; return 0 ;; esac
        done < "$WORK/runtimehomes"
        return 1
    }
    add_dep() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$DEPS"; }

    # Collect path references (resolved through symlinks) from config files
    scan_refs() {  # $1 = file, $2 = type label, $3 = detail
        local f="$1" t h
        grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -oE '/[A-Za-z0-9._/+-]+' | sort -u | while read -r t; do
            case "$t" in *java*|*jvm*|*jre*|*jdk*|*Java*|*JDK*|*JRE*)
                h=$(home_of "$t") && add_dep "$h" "$2" "$3" ;;
            esac
        done
        if [ -n "$DEFAULT_HOME" ] && grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -qE '(^|[[:space:]"=;&(])java[[:space:]]'; then
            h=$(home_of "$DEFAULT_HOME") && add_dep "$h" "$2 (java from PATH)" "$3"
        fi
    }

    # systemd services
    for f in /etc/systemd/system/*.service /usr/lib/systemd/system/*.service /lib/systemd/system/*.service \
             /run/systemd/system/*.service /etc/systemd/system/*.service.d/*.conf; do
        [ -f "$f" ] || continue
        grep -qiE 'java|jvm|jre|jdk' "$f" 2>/dev/null || continue
        unit=$(basename "$f"); case "$f" in *.service.d/*) unit=$(basename "$(dirname "$f")" .d) ;; esac
        state=$(systemctl is-enabled "$unit" 2>/dev/null); active=$(systemctl is-active "$unit" 2>/dev/null)
        scan_refs "$f" "Service (systemd)" "$unit ${active:-unknown}, ${state:-unknown}"
    done
    # SysV init scripts
    for f in /etc/init.d/*; do [ -f "$f" ] && scan_refs "$f" "Service (init script)" "$(basename "$f")"; done
    # cron
    for f in /etc/crontab /etc/cron.d/* /var/spool/cron/* /var/spool/cron/crontabs/*; do
        [ -f "$f" ] && scan_refs "$f" "Cron Job" "$f"
    done
    # environment files
    for f in /etc/environment /etc/profile /etc/profile.d/*.sh /etc/default/*; do
        [ -f "$f" ] && scan_refs "$f" "Environment File" "$f"
    done

    # running processes
    for pd in /proc/[0-9]*; do
        exe=$(readlink "$pd/exe" 2>/dev/null) || continue
        h=$(home_of "$exe") || continue
        pid=${pd##*/}
        name=$(cat "$pd/comm" 2>/dev/null)
        user=$(stat -c %U "$pd" 2>/dev/null)
        unit=$(grep -oE '[^/]+\.service' "$pd/cgroup" 2>/dev/null | head -1)
        hint=$(tr '\0' '\n' < "$pd/cmdline" 2>/dev/null | awk '
            NR==1 {next}
            skip {skip=0; next}
            $0=="-jar" {getline j; n=split(j,a,"/"); print "jar " a[n]; exit}
            $0=="-m" || $0=="--module" {getline m; print "module " m; exit}
            $0=="-cp" || $0=="-classpath" || $0=="--class-path" || $0=="-p" || $0=="--module-path" {skip=1; next}
            /^-/ || /^@/ {next}
            {print ($0=="org.apache.catalina.startup.Bootstrap" ? "Apache Tomcat (org.apache.catalina.startup.Bootstrap)" : "class " $0); exit}')
        detail="$name PID $pid, user ${user:-unknown}"
        [ -n "$unit" ] && detail="$detail (service $unit)"
        [ -n "$hint" ] && detail="$detail - $hint"
        add_dep "$h" "Running Process" "$detail"
    done

    # default java on PATH (/usr/bin/java, alternatives)
    if [ -n "$DEFAULT_HOME" ]; then
        h=$(home_of "$DEFAULT_HOME") && add_dep "$h" "Default Java" "/usr/bin/java points here (alternatives)"
    fi
fi

# ---------- output ----------
sort -u "$DEPS" -o "$DEPS"
while IFS="$(printf '\t')" read -r h path line norm jv type impl by un; do
    base="$(clean "$path")|$(clean "$line")|$(clean "$norm")|$(clean "$jv")|$(clean "$type")|$(clean "$impl")|$(clean "$by")|$(clean "$un")"
    found=0
    while IFS="$(printf '\t')" read -r dh dt dd; do
        [ "$dh" = "$h" ] || continue
        found=1
        echo "$base|$(clean "$dt")|$(clean "$dd")"
    done < "$DEPS"
    [ $found -eq 0 ] && echo "$base|None found|No service, process, cron job, or environment file references it"
done < "$RUNTIMES" | sort -u
[ -f "$WORK/truncated" ] && echo "Scan incomplete||||||||Scan incomplete|Folder search stopped after $SCAN_SECONDS seconds. Some folders were not checked."
exit 0
