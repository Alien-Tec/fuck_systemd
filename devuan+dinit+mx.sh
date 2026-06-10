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
# Wir laden das offizielle Keyring-Paket von MX Linux direkt aus dem Pool herunter
wget -q http://mxrepo.com -O /tmp/mx-keyring.deb

if [ -f /tmp/mx-keyring.deb ]; then
  # Schlüssel extrahieren und an den sicheren Ort verschieben
  dpkg-deb -x /tmp/mx-keyring.deb /tmp/mx-keyring-extracted
  cp /tmp/mx-keyring-extracted/usr/share/keyrings/mx-archive-keyring.gpg /etc/apt/keyrings/mx-archive-keyring.gpg
  rm -rf /tmp/mx-keyring*
  echo "    [OK] MX-Schlüssel erfolgreich hinterlegt."
else
  echo "    [FEHLER] Konnte MX-Keyring-Paket nicht herunterladen!"
  exit 1
fi

echo "--> Konfiguriere MX-Linux 25 (Trixie) Werkzeugquellen..."
# Wir binden die MX-Tools ein und verknüpfen sie direkt mit dem gerade extrahierten GPG-Schlüssel
echo "deb [signed-by=/etc/apt/keyrings/mx-archive-keyring.gpg] http://mxrepo.com/mx/repo/ trixie main ahs" > /etc/apt/sources.list.d/mx-tools.list

echo "--> Aktualisiere Paketlisten..."
apt-get update

# --------------------------------------------------------------------
# SCHRITT 2: Dinit Kernkomponenten installieren
# --------------------------------------------------------------------
echo "--> Installiere Dinit Core und das Umschaltpaket dinit-sysv..."
# dinit-sysv stellt sicher, dass SysV-Skripte sauber an Dinit übergeben werden
apt-get install -y dinit dinit-sysv

# --------------------------------------------------------------------
# SCHRITT 3: Nur MX-Snapshot & MX-Installer installieren
# --------------------------------------------------------------------
echo "--> Installiere gezielt mx-snapshot und mx-installer..."
# --no-install-recommends verhindert, dass unbemerkt systemd-Pakete aus den MX-Quellen mitgezogen werden
apt-get install -y --no-install-recommends mx-snapshot mx-installer

if [ $? -ne 0 ]; then
  echo "Fehler bei der Installation der MX-Komponenten!"
  exit 1
fi

# --------------------------------------------------------------------
# SCHRITT 4: Bootloader (GRUB) aktualisieren
# --------------------------------------------------------------------
echo "--> Aktualisiere GRUB-Bootloader..."
if [ -f /etc/default/grub ]; then
  cp /etc/default/grub /etc/default/grub.bak
  # Das Paket dinit-sysv verknüpft /sbin/init um. Ein einfaches update-grub reicht aus.
  update-grub
else
  echo "WARNUNG: /etc/default/grub nicht gefunden! Bootloader-Update übersprungen."
fi

echo "===================================================================="
echo " FERTIG! Die Paketquellen wurden perfekt synchronisiert."
echo " - Devuan arbeitet auf der Basis 'excalibur'"
echo " - MX-Tools werden aus der Basis 'trixie' bezogen"
echo " - Dinit übernimmt beim nächsten Bootvorgang die Kontrolle."
echo "===================================================================="
read -n 1 -p "Drücken Sie ENTER für den Neustart... "

sync
reboot
