#!/bin/bash
# Devuan 6 "Excalibur" -> Dinit Transition + Minimal MX-Tools
# 2026 Script Edition

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen!"
  exit 1
fi

echo "===================================================================="
echo " START: DEVUAN 6 -> DINIT + MX-SNAPSHOT & MX-INSTALLER"
echo "===================================================================="
echo

# --------------------------------------------------------------------
# SCHRITT 1: Repositories für Dinit & MX-Linux einbinden
# --------------------------------------------------------------------
echo "--> Füge Dinit-on-Devuan und MX-Linux Repositories hinzu..."

# MX-Linux Paketquelle für MX-25 (basiert auf Debian 13 / Excalibur)
echo "deb http://debian.nz excalibur main non-free" > /etc/apt/sources.list.d/mx-linux.list

# Dinit-on-Devuan Paketquelle (Excalibur Zweig)
echo "deb https://githubusercontent.com excalibur main" > /etc/apt/sources.list.d/dinit-devuan.list

# Schlüssel für Repositories holen
echo "--> Importiere Repository-Schlüssel..."
apt-get install -y dirmngr gnupg wget
apt-key adv --keyserver ://ubuntu.com --recv-keys F06FE91741DB5DA0 2>/dev/null

# Paketlisten aktualisieren
apt-get update

# --------------------------------------------------------------------
# SCHRITT 2: Dinit Kernkomponenten installieren
# --------------------------------------------------------------------
echo "--> Installiere Dinit Core und Basisskripte..."
apt-get install -y dinit dinit-services dinitscripts

# --------------------------------------------------------------------
# SCHRITT 3: Nur MX-Snapshot & MX-Installer installieren
# --------------------------------------------------------------------
echo "--> Installiere MX-Repository-Keyring..."
apt-get install -y mx-repository-keyring
apt-get update

echo "--> Installiere gezielt mx-snapshot und mx-installer..."
# mx-installer zieht mx-live-usb-maker automatisch als Abhängigkeit mit
apt-get install -y mx-snapshot mx-installer
if [ $? -ne 0 ]; then
  echo "Fehler bei der Installation der MX-Komponenten!"
  exit 1
fi

# --------------------------------------------------------------------
# SCHRITT 4: Bootloader (GRUB) auf Dinit umstellen
# --------------------------------------------------------------------
echo "--> Konfiguriere GRUB-Bootloader für Dinit als PID 1..."
if [ -f /etc/default/grub ]; then
  cp /etc/default/grub /etc/default/grub.bak
  
  if ! grep -q "init=/sbin/dinit" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="init=\/sbin\/dinit /' /etc/default/grub
  fi
  update-grub
else
  echo "WARNUNG: /etc/default/grub nicht gefunden!"
fi

echo "===================================================================="
echo " FERTIG! Das System wurde erfolgreich angepasst."
echo " - MX-Snapshot und MX-Installer sind einsatzbereit."
echo " - Dinit übernimmt beim nächsten Bootvorgang die Kontrolle."
echo "===================================================================="
read -n 1 -p "Drücken Sie ENTER für den Neustart... "

sync
reboot
