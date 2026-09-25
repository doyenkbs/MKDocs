#!/bin/sh
# Tanium sensor: Certificate Expiration (macOS)
#
# NOT YET TESTED ON A MAC. Parsing logic is shared with the Linux script, which is tested.
#
# Sensor settings
#   Script type : UnixShell
#   Parameters  : none
#   Result type : Text, split into columns, delimiter |
#   Columns     : Subject | Issuer | Expiration Date | Days Left | Thumbprint | Store or Path
#                 (Days Left = Integer, Expiration Date = Date/Time (RFC822), others = Text)
#
# Reads the System keychain. Apple's trust roots (SystemRootCertificates.keychain) are
# skipped on purpose. Read-only: certificates are exported to stdout only, no temp files.

KEYCHAIN=/Library/Keychains/System.keychain

if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: openssl not found|||||"
    exit 0
fi

if ! pems=$(security find-certificate -a -p "$KEYCHAIN" 2>/dev/null); then
    echo "Error: Cannot read System keychain|||||"
    exit 0
fi

tab=$(printf '\t')
us=$(printf '\037')
cr=$(printf '\r')
now=$(date -u +%s)
# RFC 2253 names with ", " between parts, so Subject and Issuer read like Windows (CN first).
NAMEOPT="esc_2253,esc_ctrl,esc_msb,utf8,dump_nostr,dump_unknown,dump_der,sep_comma_plus_space,dn_rev,sname"

# Pass 1: one openssl call per certificate (read from stdin). Prints path, subject,
# issuer, notAfter, and fingerprint separated by \037.
parse_cert() {
    cert=$(cat)
    info=$(printf '%s\n' "$cert" | openssl x509 -noout -subject -issuer -enddate -fingerprint -sha1 -nameopt "$NAMEOPT" 2>/dev/null) || return 0

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

    # Empty Subject: fall back to the first DNS name in the Subject Alternative Name.
    if [ -z "${s# }" ]; then
        san=$(printf '%s\n' "$cert" | openssl x509 -noout -ext subjectAltName 2>/dev/null |
              awk 'NR == 2 { n = split($0, a, ", "); for (j = 1; j <= n; j++) { x = a[j]; sub(/^ +/, "", x)
                                if (x ~ /^DNS:/) { sub(/^DNS:/, "", x); print x; exit } } }')
        if [ -n "$san" ]; then s="SAN: $san"; else s="(no subject)"; fi
    fi

    printf '%s%s%s%s%s%s%s%s%s\n' "$KEYCHAIN" "$us" "$s" "$us" "$i" "$us" "$e" "$us" "$fp"
}

raw=$(printf '%s\n' "$pems" | while IFS= read -r line; do
    case "$line" in
        *"BEGIN CERTIFICATE"*) pem=$line ;;
        *"END CERTIFICATE"*)   printf '%s\n%s\n' "$pem" "$line" | parse_cert; pem= ;;
        *)                     [ -n "$pem" ] && pem="$pem
$line" ;;
    esac
done)

# Pass 2: one awk call formats every row. notAfter looks like "Jan  1 00:00:00 2027 GMT"
# and is already UTC, so the date is converted with plain arithmetic (no date command).
printf '%s\n' "$raw" | awk -F "$us" -v now="$now" '
    function days_from_civil(y, m, d,    era, yoe, doy, doe) {
        y -= (m <= 2)
        era = int(y / 400)
        yoe = y - era * 400
        doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
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
    END { if (!rows) printf "0\tNone|||||\n" }' | sort -t "$tab" -k1,1n | cut -f2-
exit 0
