#!/bin/bash
# Devuan 6 "Excalibur" -> Dinit Transition + Minimal MX-Tools
# Copyright 2026 Alien-Tec.com

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen!"
  exit 1
fi

echo "===================================================================="
echo " START: DEVUAN 6 (EXCALIBUR) -> DINIT + MX-SNAPSHOT & MX-INSTALLER"
echo "===================================================================="
echo

# --------------------------------------------------------------------
# SCHRITT 1: Repositories & Schlüssel sauber einrichten
# --------------------------------------------------------------------
echo "--> Installiere benötigte Basiswerkzeuge..."
apt-get update && apt-get install -y wget gnupg dirmngr dpkg-dev

echo "--> Bereite Schlüsselverzeichnis vor..."
mkdir -p /etc/apt/keyrings

echo "--> Konfiguriere Devuan 6 Excalibur Hauptquellen..."
cat <<EOF > /etc/apt/sources.list
deb http://devuan.org excalibur main contrib non-free non-free-firmware
deb http://devuan.org excalibur-security main contrib non-free non-free-firmware
deb http://devuan.org excalibur-updates main contrib non-free non-free-firmware
deb http://devuan.org excalibur-proposed main contrib non-free non-free-firmware
EOF

echo "--> Hole MX-Linux (Trixie) Repository-Schlüssel..."
# Absolut korrekter Pfad zum offiziellen Paket
wget -q http://mxrepo.com -O /tmp/mx-keyring.deb

if [ -f /tmp/mx-keyring.deb ] && [ -s /tmp/mx-keyring.deb ]; then
  mkdir -p /tmp/mx-keyring-extracted
  dpkg-deb -x /tmp/mx-keyring.deb /tmp/mx-keyring-extracted
  cp /tmp/mx-keyring-extracted/usr/share/keyrings/mx25-archive-keyring.gpg /etc/apt/keyrings/mx-archive-keyring.gpg
  rm -rf /tmp/mx-keyring*
  echo "    [OK] MX-Schlüssel erfolgreich hinterlegt."
else
  echo "    [FEHLER] Download des MX-Keyrings fehlgeschlagen!"
  exit 1
fi

echo "--> Konfiguriere MX-Linux 25 (Trixie) Werkzeugquellen..."
echo "deb [signed-by=/etc/apt/keyrings/mx-archive-keyring.gpg] http://mxrepo.com trixie main non-free" > /etc/apt/sources.list.d/mx-tools.list

echo "--> Aktualisiere Paketlisten..."
apt-get update

# --------------------------------------------------------------------
# SCHRITT 2: Dinit Kernkomponenten installieren
# --------------------------------------------------------------------
echo "--> Installiere Dinit Core und das Umschaltpaket dinit-sysv..."
apt-get install -y dinit dinit-sysv sysvinit-core-

# --------------------------------------------------------------------
# SCHRITT 3: Dinit-Kompatibilität für MX-Tools (WICHTIGE KORREKTUR)
# --------------------------------------------------------------------
echo "--> Installiere Systemd-Dummy-Bibliotheken für GUI-Kompatibilität..."
# Ermöglicht das Ausführen der MX-Tools ohne echtes Systemd als PID 1
apt-get install -y libsystemd0 systemd-standalone-sysusers systemd-standalone-tmpfiles 2>/dev/null

echo "--> Installiere gezielt mx-snapshot und mx-installer..."
apt-get install -y --no-install-recommends mx-snapshot mx-installer

if [ $? -ne 0 ]; then
  echo "Fehler bei der Installation der MX-Komponenten aufgrund von Abhängigkeiten!"
  exit 1
fi

# --------------------------------------------------------------------
# SCHRITT 4: Bootloader (GRUB) aktualisieren
# --------------------------------------------------------------------
echo "--> Aktualisiere GRUB-Bootloader..."
if [ -f /etc/default/grub ]; then
  cp /etc/default/grub /etc/default/grub.bak
  update-grub
else
  echo "WARNUNG: /etc/default/grub nicht gefunden!"
fi

# --------------------------------------------------------------------
# SCHRITT 5: Dinit Pre-Boot-Sicherheitscheck
# --------------------------------------------------------------------
echo "--> Führe Dinit Sicherheits-Validierung durch..."
MISSING_SERVICES=0
CRITICAL_SERVICES=("boot" "udev" "rootfs")

for service in "${CRITICAL_SERVICES[@]}"; do
  # Korrekte ODER-Prüfung: Es reicht, wenn der Dienst in einem der Ordner existiert
  if [ ! -f "/etc/dinit.d/$service" ] && [ ! -f "/lib/dinit.d/$service" ]; then
    echo "    [WARNUNG] Kritischer Dinit-Dienst fehlt: $service"
    MISSING_SERVICES=$((MISSING_SERVICES + 1))
  fi
done

if [ "$MISSING_SERVICES" -gt 0 ]; then
  echo "ACHTUNG: Sicherheitssperre aktiv. Dienste fehlen."
  exit 1
else
  echo "    [OK] Alle kritischen Basisservices für Dinit sind vorhanden."
fi

echo "===================================================================="
echo " FERTIG! System ist bereit für den Neustart."
echo "===================================================================="
read -n 1 -p "Drücken Sie ENTER für den sicheren Neustart... "
echo

sync
reboot
