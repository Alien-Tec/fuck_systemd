#!/bin/bash
# Alien-Tec, 2026 (arch2artix with dinit)

# How to use
# wget URL
# chmod +x fucksystemd.sh
# sudo ./fucksystemd.sh

source /usr/share/makepkg/util/message.sh
colorize

echo "$ALL_OFF$BOLD You should run this from inside screen(1) or tmux(1),"
echo "$BOLD especially if this is a remote box."
echo "$BOLD Use a terminal/session with a large scrollback buffer"
echo
read -n 1 -p "$RED Last chance to press CTRL-C, ENTER to continue. "
echo
echo "$CYAN Starting operation FUCKTHESKULLOFSYSTEMD (Dinit Edition)"
echo

testerror() { [[ $res > 0 ]] && { echo "$RED An error occured, aborting to prevent incomplete conversion. Fix it and re-run the script FROM THE LAST STEP ONWARDS.$ALL_OFF"; exit 1; } }

rm -f /var/lib/pacman/db.lck
sed -i s/Arch/Artix/g /etc/default/grub

echo "$GREEN Updating Arch system first, if this fails abort and update manually; then re-run the script $ALL_OFF"
pacman -Syu --noconfirm
res=$?; testerror
pacman -S --needed --noconfirm wget nano rsync iproute2
res=$?; testerror

cd /etc
echo
echo "$GREEN Replacing Arch repositories with Artix $ALL_OFF"
mv -vf pacman.conf pacman.conf.arch
wget https://artixlinux.org -O /etc/pacman.conf
res=$?; testerror
sed -i 's/#Parallel/Parallel/' /etc/pacman.conf
mv -vf pacman.d/mirrorlist pacman.d/mirrorlist-arch
wget https://artixlinux.org -O pacman.d/mirrorlist
res=$?; testerror
cp -vf pacman.d/mirrorlist pacman.d/mirrorlist.artix
sed -i 's/Required DatabaseOptional/Never/' /etc/pacman.conf
rm -fr /var/cache/pacman/pkg/*

echo "$GREEN Refreshing package databases $ALL_OFF"
pacman -Syy --noconfirm
res=$?; testerror
echo

echo "$GREEN Importing Artix keys $ALL_OFF"
pacman -S --noconfirm artix-keyring
res=$?; testerror
pacman-key --populate artix
res=$?; testerror
pacman-key --lsign-key 95AEC5D0C1E294FC9F82B253573A673A53C01BC2
res=$?; testerror

[ -x /bin/systemctl ] && systemctl list-units --state=running | grep -v systemd | awk '{print $1}' | grep service > /root/daemon.list
echo "$MAGENTA Your systemd running units are saved in /root/daemon.list.$ALL_OFF"
echo
read -n 1 -p "$RED Do not proceed if you've seen errors above - press CTRL-C to abort or ENTER to continue $ALL_OFF "
echo

echo "$GREEN Downloading systemd-free packages from Artix (Dinit) $ALL_OFF"
pacman -Sw --noconfirm base base-devel dinit-system grub linux-lts linux-lts-headers elogind-dinit dinit grub mkinitcpio rsync nano lsb-release esysusers etmpfiles
res=$?; testerror
echo

echo "$YELLOW This is the best part: removing systemd $ALL_OFF"
pacman -Rdd --noconfirm systemd systemd-libs systemd-sysvcompat dbus
pacman -Rdd --noconfirm pacman-mirrorlist

# Previous pacman-mirrorlist removal also deleted this, restoring
cp -vf pacman.d/mirrorlist.artix pacman.d/mirrorlist

echo "$GREEN Installing clean Artix packages $ALL_OFF"
pacman -S --noconfirm elogind-dinit
pacman -Qqn | pacman -S --noconfirm --overwrite '*' -
res=$?; testerror

echo "$GREEN Installing Artix Dinit system packages $ALL_OFF"
pacman -S --noconfirm --needed --overwrite '*' base base-devel dinit-system linux-lts linux-lts-headers elogind-dinit dinit grub mkinitcpio rsync nano lsb-release esysusers etmpfiles artix-branding-base
res=$?; testerror

echo "$GREEN Installing Dinit service files $ALL_OFF"
pacman -S --noconfirm --needed openssh-dinit dbus-dinit cronie-dinit haveged-dinit
res=$?; testerror

echo "$YELLOW Removing left-over cruft $ALL_OFF"
rm -fv /etc/resolv.conf

echo "$GREEN Enabling basic services in Dinit $ALL_OFF"
# In Dinit werden Dienste per Symlink im boot.d-Verzeichnis aktiviert
mkdir -p /etc/dinit.d/boot.d
ln -sf ../sshd /etc/dinit.d/boot.d/sshd
ln -sf ../dbus /etc/dinit.d/boot.d/dbus
ln -sf ../haveged /etc/dinit.d/boot.d/haveged

echo
echo "$BOLD Activating standard network interface naming (i.e. eth0)."
read -n 1 -p "Press ENTER $ALL_OFF"
echo 'GRUB_CMDLINE_LINUX="net.ifnames=0"' >>/etc/default/grub
echo 'GRUB_DISABLE_OS_PROBER="false"' >>/etc/default/grub

echo "============================="
echo "$BOLD Your current Network State (via 'ip'):$ALL_OFF"
echo "============================="
ip a
ip r
echo "==============================================================="
echo "$BOLD Default setting uses Artix's native dinit network scripts. $ALL_OFF"
echo "==============================================================="

# Good riddance
echo "$YELLOW Removing more systemd cruft $ALL_OFF"
for user in journal journal-gateway timesync network bus-proxy journal-remote journal-upload resolve coredump; do 
  userdel systemd-$user 2>/dev/null
done
rm -vfr /{etc,var/lib}/systemd

echo "$GREEN Restoring pacman.conf security settings $ALL_OFF"
sed -i 's/= Never/= Required DatabaseOptional/' /etc/pacman.conf

echo "$GREEN Replacing Arch with Artix in hostname and issue $ALL_OFF"
sed -i 's/Arch/Artix/ig' /etc/hostname /etc/issue 2>/dev/null

echo "$GREEN Recreating initrds $ALL_OFF"
mkinitcpio -P

echo "$GREEN Recreating grub.cfg $ALL_OFF"
cp -vf /boot/grub/grub.cfg /boot/grub/grub.cfg.arch
grub-mkconfig -o /boot/grub/grub.cfg
res=$?; testerror

echo "============================================="
echo "=       If you haven't seen any errors      ="
echo "=            press ENTER to reboot          ="
echo "=   Otherwise switch console and fix them   ="
echo "=                                           ="
echo "=       Press CTRL-C to stop reboot         ="
echo "============================================="
read -n 1 -p " "
sync
mount -f / -o remount,ro
echo s >| /proc/sysrq-trigger
echo u >| /proc/sysrq-trigger
echo b >| /proc/sysrq-trigger
