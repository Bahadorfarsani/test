#!/usr/bin/env bash
# optimize.sh - Ressourcen auf dem Ubuntu SSH-Server sparen
# Aufruf: sudo bash optimize.sh
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Bitte als root ausführen: sudo bash $0" >&2
    exit 1
fi

echo "=== 1/3: pam_systemd für SSH deaktivieren ==="
PAM_FILE="/etc/pam.d/sshd"
if [[ ! -f "${PAM_FILE}.bak" ]]; then
    cp "$PAM_FILE" "${PAM_FILE}.bak"
    echo "Backup erstellt: ${PAM_FILE}.bak"
else
    echo "Backup existiert bereits: ${PAM_FILE}.bak (wird nicht überschrieben)"
fi
sed -i 's/^\(session\s\+optional\s\+pam_systemd.so\)/#\1/' "$PAM_FILE"
grep pam_systemd "$PAM_FILE" || echo "(keine pam_systemd-Zeile in $PAM_FILE gefunden)"

echo
echo "=== 2/3: Überflüssige Dienste deaktivieren ==="
systemctl disable --now multipathd multipathd.socket || true
systemctl disable --now packagekit                   || true
systemctl disable --now irqbalance                   || true
systemctl disable --now serial-getty@ttyS0           || true
touch /etc/cloud/cloud-init.disabled
echo "cloud-init deaktiviert (/etc/cloud/cloud-init.disabled)"

echo
echo "=== 3/3: journald konfigurieren ==="
CONF="/etc/systemd/journald.conf"
[[ -f "${CONF}.bak" ]] || cp "$CONF" "${CONF}.bak"

# Sicherstellen, dass die [Journal]-Sektion existiert
grep -q '^\[Journal\]' "$CONF" || printf '\n[Journal]\n' >> "$CONF"

# Setzt einen Schlüssel: ersetzt (auch auskommentierte) Zeile oder fügt sie unter [Journal] ein
set_opt() {
    local key="$1" val="$2"
    if grep -qE "^[#[:space:]]*${key}=" "$CONF"; then
        sed -i -E "0,/^[#[:space:]]*${key}=.*/ s/^[#[:space:]]*${key}=.*/${key}=${val}/" "$CONF"
    else
        sed -i "/^\[Journal\]/a ${key}=${val}" "$CONF"
    fi
}

set_opt SystemMaxUse         50M
set_opt RuntimeMaxUse        30M
set_opt MaxLevelStore        warning
set_opt RateLimitIntervalSec 30s
set_opt RateLimitBurst       200
set_opt ForwardToSyslog      no

journalctl --vacuum-size=50M
systemctl restart systemd-journald

echo
echo "=== Ergebnis ==="
grep -E '^(SystemMaxUse|RuntimeMaxUse|MaxLevelStore|RateLimitIntervalSec|RateLimitBurst|ForwardToSyslog)=' "$CONF"
echo
journalctl --disk-usage
free -h
echo
echo "Fertig. Teste jetzt einen neuen SSH-Login in einem zweiten Fenster,"
echo "bevor du die aktuelle Session schließt."
