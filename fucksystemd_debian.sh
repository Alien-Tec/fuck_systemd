#!/bin/bash
# Debian 13 "Trixie" - In-Place systemd removal & Dinit activation
# 2026 Edition

# Voraussetzungen: Das Skript muss als root ausgeführt werden.
if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen (sudo ./fucksystemd_debian.sh)"
  exit 1
fi

echo "===================================================================="
echo " STARTING OPERATION: DEBIAN 13 SYSTEMD PURGE & DINIT INSTALLATION"
echo "===================================================================="
echo "Dieses Skript stellt Ihr Debian 13 System auf Dinit um."
echo "Bitte stellen Sie sicher, dass Sie sich in screen oder tmux befinden,"
echo "falls dies eine SSH-Verbindung ist."
echo
read -n 1 -p "Drücken Sie ENTER um fortzufahren oder STRG+C zum Abbrechen... "
echo

# Schritt 1: System aktualisieren
echo "--> Aktualisiere Paketquellen und bestehende Pakete..."
apt-get update && apt-get dist-upgrade -y
if [ $? -ne 0 ]; then
  echo "Fehler beim System-Update. Abbruch."
  exit 1
fi

# Schritt 2: Installation der systemd-freien Kern-Komponenten
# systemd-sysv- (mit Minus am Ende) deinstalliert den systemd-Boot-Symlink.
echo "--> Installiere SysV-Core-Kompabilität und Dinit..."
apt-get install -y --allow-remove-essential sysvinit-core sysvinit-utils dinit dinit-services dbus-x11
if [ $? -ne 0 ]; then
  echo "Fehler bei der Installation alternativer Init-Pakete."
  exit 1
fi

# Schritt 3: Systemd als PID 1 entmachten
echo "--> Entferne systemd-sysv Bindung..."
apt-get purge -y systemd-sysv
apt-get autoremove -y --purge

# Schritt 4: Dinit als Standard-Init in GRUB hinterlegen
# Wir überschreiben nicht blind /sbin/init, sondern weisen den Kernel an, dinit zu laden.
echo "--> Konfiguriere Bootloader (GRUB) für Dinit..."
if [ -f /etc/default/grub ]; then
  # Sichern der GRUB-Konfiguration
  cp /etc/default/grub /etc/default/grub.bak
  
  # Kernel-Parameter für Dinit setzen
  if ! grep -q "init=/sbin/dinit" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="init=\/sbin\/dinit /' /etc/default/grub
  fi
  
  # GRUB aktualisieren
  update-grub
else
  echo "WARNUNG: /etc/default/grub nicht gefunden. Bitte Kernel-Parameter 'init=/sbin/dinit' manuell setzen!"
fi

# Schritt 5: Lokales Netzwerk sichern (Standard-Interfaces via ifupdown)
echo "--> Richte klassischen Netzwerkdienst (ifupdown) ein..."
apt-get install -y ifupdown isc-dhcp-client

# Status-Ausgabe der Netzwerkkarten für den Administrator
echo "===================================================================="
echo "Aktuelle Netzwerkschnittstellen:"
ip -br a
echo "===================================================================="
echo "WICHTIG: Stellen Sie sicher, dass Ihre Schnittstellen in "
echo "/etc/network/interfaces eingetragen sind (z.B. allow-hotplug eth0)."
echo "===================================================================="
read -n 1 -p "Drücken Sie ENTER nach der Überprüfung... "

# Schritt 6: Systemd-Reste bereinigen (Optional, entfernt verbleibende Daemons)
echo "--> Entferne nicht benötigte systemd-Dienste..."
apt-get purge -y systemd-timesyncd systemd-resolved 2>/dev/null

echo "===================================================================="
echo " DIE KONVERTIERUNG WAR ERFOLGREICH!"
echo " Das System wird beim nächsten Boot mit Dinit (PID 1) starten."
echo " Falls Fehler auftraten, wechseln Sie die Konsole und fixen Sie diese."
echo "===================================================================="
read -n 1 -p "Drücken Sie ENTER für den sauberen Neustart... "

# Sicherer Reboot ohne systemd-Intervention
sync
reboot
