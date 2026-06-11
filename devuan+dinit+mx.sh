#!/bin/bash
# Devuan 6 "Excalibur" -> Dinit Transition + Minimal MX-Tools (überarbeitet)
# Copyright 2026 Alien-Tec.com (angepasst)
# Usage: ./script.sh [--dry-run] [--no-reboot]

set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
NO_REBOOT=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-reboot) NO_REBOOT=1 ;;
    *) echo "Unbekannte Option: $arg"; exit 2 ;;
  esac
done

LOGFILE="/var/log/dinit-migration.log"
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
exec 3>&1 1>>"$LOGFILE" 2>&1

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log() { printf "%s %s\n" "$(timestamp)" "$*"; }

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen!" >&3
  exit 1
fi

echo "====================================================================" >&3
echo " START: DEVUAN 6 (EXCALIBUR) -> DINIT + MX-SNAPSHOT & MX-INSTALLER" >&3
echo "====================================================================" >&3
echo >&3

log "Skript gestartet (dry-run=${DRY_RUN}, no-reboot=${NO_REBOOT})"

# Improved PID 1 detection: prefer /proc/1/exe -> basename, fallback to ps
if [ -r /proc/1/exe ]; then
  CURRENT_INIT="$(basename "$(readlink -f /proc/1/exe)" 2>/dev/null || true)"
fi
if [ -z "${CURRENT_INIT:-}" ]; then
  CURRENT_INIT="$(ps -p 1 -o comm= | tr -d '[:space:]' || true)"
fi
CURRENT_INIT="${CURRENT_INIT:-unknown}"
log "PID 1: ${CURRENT_INIT}"
if [ "${CURRENT_INIT}" = "systemd" ]; then
  echo "Systemd ist aktuell PID 1 — Abbruch (Operation nicht sicher auf systemd-Systems)." >&3
  exit 1
fi

# Helper run function (respects dry-run) — returns command exit status
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] $*" >&3
    return 0
  else
    log "RUN: $*"
    bash -c "$@"
    return $?
  fi
}

# Tempdir
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --------------------------------------------------------------------
# Schritt 1: Basis-Tools & APT Quellen
# --------------------------------------------------------------------
run "apt-get update || { echo 'apt-get update failed' >&3; exit 1; }" || exit 1
run "apt-get install -y --no-install-recommends wget gnupg dirmngr dpkg-dev || { echo 'Base package install failed' >&3; exit 1; }" || exit 1

# secure keyrings dir
run "mkdir -p /etc/apt/keyrings && chmod 0755 /etc/apt/keyrings" || exit 1

# Backup existing sources.list
if [ -f /etc/apt/sources.list ]; then
  run "cp -a /etc/apt/sources.list /etc/apt/sources.list.bak" || exit 1
fi

cat <<'EOF' > "${TMPDIR}/sources.list.new"
deb http://devuan.org excalibur main contrib non-free non-free-firmware
deb http://devuan.org excalibur-security main contrib non-free non-free-firmware
deb http://devuan.org excalibur-updates main contrib non-free non-free-firmware
deb http://devuan.org excalibur-proposed main contrib non-free non-free-firmware
EOF

# Install new sources atomically
run "cp -a ${TMPDIR}/sources.list.new /etc/apt/sources.list" || exit 1
log "APT sources updated (backup kept as /etc/apt/sources.list.bak if existed)"

# --------------------------------------------------------------------
# Schritt 1b: MX-Keyring sicher herunterladen und prüfen
# --------------------------------------------------------------------
# HINWEIS: URL prüfen und ggf. anpassen auf aktuelle mx keyring .deb
MX_KEY_DEB_URL="https://mxrepo.com/mx/repo/mx25-archive-keyring_25_all.deb"

MX_DEB="$TMPDIR/mx-keyring.deb"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[DRY-RUN] Would download MX keyring from ${MX_KEY_DEB_URL}" >&3
else
  log "Lade MX keyring: ${MX_KEY_DEB_URL}"
  if ! wget --content-disposition -O "$MX_DEB" --tries=3 --timeout=30 "$MX_KEY_DEB_URL"; then
    echo "FEHLER: MX-Keyring Download fehlgeschlagen: ${MX_KEY_DEB_URL}" >&3
    exit 1
  fi
fi

# Extract and find keyring file (ensure absolute path)
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[DRY-RUN] Would extract $MX_DEB and install keyring" >&3
else
  dpkg-deb -x "$MX_DEB" "$TMPDIR/mx-extracted"
  KEYFILE_REL="$(find "$TMPDIR/mx-extracted" -type f -iname '*mx*-archive-keyring*.gpg' -print -quit || true)"
  if [ -z "$KEYFILE_REL" ]; then
    echo "FEHLER: MX keyring .gpg nicht im .deb gefunden" >&3
    exit 1
  fi
  KEYFILE="$(readlink -f "$KEYFILE_REL")"
  if [ -z "$KEYFILE" ] || [ ! -f "$KEYFILE" ]; then
    echo "FEHLER: Gefundene KEYFILE Pfad ungültig: $KEYFILE_REL" >&3
    exit 1
  fi
  install -m 0644 "$KEYFILE" /etc/apt/keyrings/mx-archive-keyring.gpg
  log "MX keyring installiert: /etc/apt/keyrings/mx-archive-keyring.gpg"
fi

# Configure MX repo list (use signed-by)
MX_LIST="/etc/apt/sources.list.d/mx-tools.list"
echo "deb [signed-by=/etc/apt/keyrings/mx-archive-keyring.gpg] https://mxrepo.com trixie main non-free" > "$TMPDIR/mx-tools.list.new"
run "cp -a $TMPDIR/mx-tools.list.new $MX_LIST" || exit 1
run "chmod 0644 $MX_LIST" || exit 1
log "MX repo configured ($MX_LIST)"

# Update package lists and check for errors
run "apt-get update || { echo 'apt-get update failed after adding repos' >&3; exit 1; }" || exit 1

# --------------------------------------------------------------------
# Schritt 2: Installiere Dinit-Komponenten (mit Pre-Checks)
# --------------------------------------------------------------------
# Verify availability with Candidate check
for pkg in dinit dinit-sysv sysvinit-core; do
  log "Checking availability of $pkg"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] apt-cache policy $pkg" >&3
  else
    CANDIDATE="$(apt-cache policy "$pkg" | awk '/Candidate:/ {print $2}' || true)"
    if [ -z "$CANDIDATE" ] || [ "$CANDIDATE" = "(none)" ]; then
      log "Warnung: Paket $pkg hat keinen Candidate (nicht verfügbar)"
    else
      log "Paket $pkg Candidate: $CANDIDATE"
    fi
  fi
done

run "apt-get install -y dinit dinit-sysv sysvinit-core" || { echo "Installation von dinit/sysvinit fehlgeschlagen"; exit 1; }

# --------------------------------------------------------------------
# Schritt 3: Systemd-Dummy / MX-Tools (vorsichtig)
# --------------------------------------------------------------------
# Prüfe simulierten Install (resolve deps) und parse output for failure indicators
SIM_PKGS="libsystemd0 systemd-standalone-sysusers systemd-standalone-tmpfiles mx-snapshot mx-installer"
log "Führe Simulation zur Prüfung von systemd-kompat-Paketen und mx-tools durch"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[DRY-RUN] apt-get -s install ${SIM_PKGS}" >&3
else
  SIM_OUT="$TMPDIR/apt-sim.out"
  if ! apt-get -s install $SIM_PKGS >"$SIM_OUT" 2>&1; then
    log "apt-get -s exitcode != 0 (mögliche Probleme); siehe Simulation"
    echo "FEHLER: apt Simulation meldet Fehler (siehe Log)." >&3
    sed -n '1,200p' "$SIM_OUT" >&3
    exit 1
  fi
  if grep -E -i "Unable to correct problems|Could not|Depends:|Broken packages|Conflicts:" "$SIM_OUT" >/dev/null 2>&1; then
    log "Simulation weist auf Abhängigkeits- oder Konfliktprobleme hin"
    echo "FEHLER: Simulation erkennt Abhängigkeits- oder Konfliktprobleme bei MX-Paketen. Abbruch." >&3
    sed -n '1,200p' "$SIM_OUT" >&3
    exit 1
  fi
  run "apt-get install -y --no-install-recommends $SIM_PKGS" || { echo 'Installation MX-Komponenten fehlgeschlagen'; exit 1; }
fi

# --------------------------------------------------------------------
# Schritt 4: GRUB Sicher aktualisieren
# --------------------------------------------------------------------
if [ -f /etc/default/grub ]; then
  run "cp -a /etc/default/grub /etc/default/grub.bak" || exit 1
  if command -v update-grub >/dev/null 2>&1; then
    run "update-grub" || { echo 'update-grub fehlgeschlagen'; exit 1; }
  else
    log "update-grub nicht gefunden; übersprungen"
  fi
else
  log "WARNUNG: /etc/default/grub nicht gefunden"
fi

# --------------------------------------------------------------------
# Schritt 5: Dinit Pre-Boot Validierung
# --------------------------------------------------------------------
log "Prüfe kritische Dinit-Dienste"
MISSING_SERVICES=0
CRITICAL_SERVICES=("boot" "udev" "rootfs" "sysinit" "mounts")
for service in "${CRITICAL_SERVICES[@]}"; do
  if [ ! -e "/etc/dinit.d/${service}" ] && [ ! -e "/lib/dinit.d/${service}" ]; then
    echo "    [WARNUNG] Kritischer Dinit-Dienst fehlt: $service" >&3
    MISSING_SERVICES=$((MISSING_SERVICES + 1))
  else
    log "Dienst vorhanden: $service"
  fi
done

if [ "$MISSING_SERVICES" -gt 0 ]; then
  echo "ACHTUNG: $MISSING_SERVICES kritische(n) Dienst(e) fehlen. Beenden." >&3
  exit 1
else
  echo "    [OK] Alle geprüften kritischen Basisservices für Dinit sind vorhanden." >&3
fi

# --------------------------------------------------------------------
# Abschluss: Hinweise, Sync & optionaler Reboot
# --------------------------------------------------------------------
echo "====================================================================" >&3
echo " FERTIG: Migration-Skriptschritte abgeschlossen (siehe Log: $LOGFILE)" >&3
echo "====================================================================" >&3

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry-run beendet. Keine Änderungen wurden angewendet." >&3
  exit 0
fi

if [ "$NO_REBOOT" -eq 1 ]; then
  echo "Kein Neustart gewünscht (--no-reboot). Bitte manuell prüfen und neu starten wenn bereit." >&3
  exit 0
fi

# Confirm interactive TTY before reboot
if [ -t 0 ]; then
  read -rp $'Drücken Sie ENTER zum Neustart oder STRG-C zum Abbrechen... ' _ || true
  log "User bestätigte Reboot"
  sync
  run "reboot" || { echo "Reboot-Befehl fehlgeschlagen" >&3; exit 1; }
else
  echo "Nicht-interaktives Terminal: kein automatischer Reboot." >&3
  exit 0
fi
