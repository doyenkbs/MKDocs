#!/bin/sh
# Tanium sensor: Certificate Expiration (Linux)
#
# Sensor settings
#   Script type : UnixShell
#   Parameters  : none
#   Result type : Text, split into columns, delimiter |
#   Columns     : Subject | Issuer | Expiration Date | Days Left | Thumbprint | Store or Path
#                 (Days Left = Integer, Expiration Date = Date/Time (RFC822), others = Text)
#
# Linux has no machine certificate store, so this reads certificate files in common
# service locations, plus certificate folders mounted into Docker or Podman containers.
# It does not scan the whole disk. Skipped on purpose: system trust stores (CA bundles,
# ca-trust, NSS databases, Java cacerts), old copies in backup and archive folders,
# and sample certificates.
# Read-only: files are only read by openssl. Nothing is written.

# Extra folders or files to scan, separated by spaces. Leave blank in the library copy.
# Add client-specific locations only in that client's copy. Paths cannot contain spaces.
EXTRA_PATHS=""

SCAN_PATHS="/etc/ssl /etc/pki/tls /etc/nginx /etc/httpd /etc/apache2 /etc/haproxy
/etc/postfix /etc/dovecot /etc/cockpit/ws-certs.d /etc/pve /etc/letsencrypt $EXTRA_PATHS"
MAX_FILES=500
TIME_LIMIT=20   # seconds; keep below the sensor timeout
SKIP='/ca-trust/|/nssdb/|/java/|/backups?/|/archive/|/([^/]*[-_.])?(examples?|samples?)/|/(ca-certificates\.crt|ca-bundle[^/]*\.crt|tls-ca-bundle\.pem|email-ca-bundle\.pem|objsign-ca-bundle\.pem)$'

if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: openssl not found|||||"
    exit 0
fi

# Container hosts: add host folders mounted into running Docker or Podman containers
# when the folder name looks like a certificate folder (ssl, cert, tls, acme,
# letsencrypt). Only the last part of the path is matched, so a parent folder's name
# does not pull in unrelated mounts. This is a read-only query to the local engine,
# limited to 5 seconds in case it hangs.
run_limited() {
    if command -v timeout >/dev/null 2>&1; then timeout 5 "$@"; else "$@"; fi
}
container_paths() {
    for engine in docker podman; do
        command -v "$engine" >/dev/null 2>&1 || continue
        ids=$(run_limited "$engine" ps -q 2>/dev/null) || continue
        [ -n "$ids" ] || continue
        run_limited "$engine" inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' $ids 2>/dev/null
    done | awk -F/ 'tolower($NF) ~ /ssl|cert|tls|acme|letsencrypt/' | sort -u
}
SCAN_PATHS="$SCAN_PATHS $(container_paths)"

tab=$(printf '\t')
us=$(printf '\037')
cr=$(printf '\r')
now=$(date -u +%s)
# RFC 2253 names with ", " between parts, so Subject and Issuer read like Windows (CN first).
NAMEOPT="esc_2253,esc_ctrl,esc_msb,utf8,dump_nostr,dump_unknown,dump_der,sep_comma_plus_space,dn_rev,sname"
OPTS="-noout -subject -issuer -enddate -fingerprint -sha1 -nameopt $NAMEOPT"

list_files() {
    for p in $SCAN_PATHS; do
        if [ -d "$p" ]; then
            find "$p" -maxdepth 4 -type f -size -64k \( -name '*.crt' -o -name '*.pem' \
                -o -name '*.cer' -o -name '*.cert' -o -name '*.der' \) 2>/dev/null
            # Let's Encrypt layout (certbot, and containers that mount it): the current
            # certificate is a symlink under live/, which find -type f skips.
            for f in "$p"/live/*/cert.pem; do
                [ -f "$f" ] && echo "$f"
            done
        elif [ -f "$p" ]; then
            echo "$p"
        fi
    done
}

files=$(list_files | grep -Ev "$SKIP" | sort -u)
count=$(printf '%s\n' "$files" | grep -c .)

# Pass 1: one openssl call per file. Prints path, subject, issuer, notAfter, and
# fingerprint separated by \037. Stops early if the time limit is reached.
raw=$(printf '%s\n' "$files" | head -n "$MAX_FILES" | {
    n=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        n=$((n + 1))
        if [ $((n % 25)) -eq 0 ] && [ $(($(date -u +%s) - now)) -ge "$TIME_LIMIT" ]; then
            echo "TIME_LIMIT"
            break
        fi

        inform=""
        info=$(openssl x509 -in "$f" $OPTS 2>/dev/null) ||
            { inform="-inform DER"; info=$(openssl x509 -in "$f" $inform $OPTS 2>/dev/null); } || continue

        s=""; i=""; e=""; fp=""
        while IFS= read -r line; do
            line=${line%"$cr"}
            case $line in
                subject=*)      s=${line#subject=} ;;
                issuer=*)       i=${line#issuer=} ;;
                notAfter=*)     e=${line#notAfter=} ;;
                *Fingerprint=*) fp=${line#*Fingerprint=} ;;
            esac
        done <<EOF
$info
EOF

        # Empty Subject: fall back to the first DNS name in the Subject Alternative Name
        # (needs OpenSSL 1.1.1+).
        if [ -z "${s# }" ]; then
            san=$(openssl x509 -in "$f" $inform -noout -ext subjectAltName 2>/dev/null |
                  awk 'NR == 2 { n = split($0, a, ", "); for (j = 1; j <= n; j++) { x = a[j]; sub(/^ +/, "", x)
                                    if (x ~ /^DNS:/) { sub(/^DNS:/, "", x); print x; exit } } }')
            if [ -n "$san" ]; then s="SAN: $san"; else s="(no subject)"; fi
        fi

        printf '%s%s%s%s%s%s%s%s%s\n' "$f" "$us" "$s" "$us" "$i" "$us" "$e" "$us" "$fp"
    done
})

# Pass 2: one awk call formats every row. notAfter looks like "Jan  1 00:00:00 2027 GMT"
# and is already UTC, so the date is converted with plain arithmetic (no date command).
printf '%s\n' "$raw" | awk -F "$us" -v now="$now" -v count="$count" -v max="$MAX_FILES" '
    function days_from_civil(y, m, d,    era, yoe, doy, doe) {
        y -= (m <= 2)
        era = int(y / 400)
        yoe = y - era * 400
        doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
    $0 == "TIME_LIMIT" { timed = 1; next }
    NF < 5 { next }
    {
        path = $1; s = $2; i = $3; e = $4; fp = $5
        sub(/^ +/, "", s); sub(/^ +/, "", i)
        gsub(/\|/, "/", s); gsub(/\|/, "/", i); gsub(/\|/, "/", path)
        gsub(/:/, "", fp); fp = toupper(fp)

        split(e, a, " ")
        mon = (index("JanFebMarAprMayJunJulAugSepOctNovDec", a[1]) + 2) / 3
        split(a[3], t, ":")
        if (mon == int(mon) && mon >= 1 && a[4] > 0) {
            epoch = days_from_civil(a[4], mon, a[2]) * 86400 + t[1] * 3600 + t[2] * 60 + t[3]
            diff = epoch - now
            days = diff >= 0 ? int(diff / 86400) : -int((-diff + 86399) / 86400)
            expires = sprintf("%04d-%02d-%02d %02d:%02d:%02d", a[4], mon, a[2], t[1], t[2], t[3])
            key = days
        } else {
            days = "Unknown"; expires = e; key = 999999
        }
        printf "%s\t%s|%s|%s|%s|%s|%s\n", key, s, i, expires, days, fp, path
        rows++
    }
    END {
        if (timed)       printf "9999998\tError: Time limit reached, results incomplete|||||\n"
        if (count > max) printf "9999999\tError: File limit reached, results incomplete|||||\n"
        if (!rows && !timed && count <= max) printf "0\tNone|||||\n"
    }' | sort -t "$tab" -k1,1n | cut -f2-
exit 0
