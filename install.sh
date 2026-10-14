#!/bin/bash 

#THIS SCRIPT INSTALLS GENTOO TO ANY PARTITION MOUNTED ON
#/mnt/gentoo AND /mnt/gentoo/efi THESE MUST BE FORMATTED
#Requirements:
#Gentoo installation media, 2 Partitions Mounted to /mnt/gentoo and
#/mnt/gentoo/efi, good music, and a computer.
#Target root partition must be formatted with xfs.
#This script theoretically works on any linux distro with
#chronyd,wget, tar, and the bash shell installed.
#This script uses grub and installs the dist-kernel by
#default.
#Installing gentoo using the official documentation is suggested
#as if you do not, you will have no idea how to manage the system
#after the installation.
echo "STARTING"

echo "Syncing time using chronyd"
chronyd -q
#Syncing time is not required, this line can be removed if time
#has already been set on the host.

echo "Entering mounted root partition"
cd /mnt/gentoo
echo "Downloading stage file with wget"
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20261011T170049Z/stage3-amd64-desktop-openrc-20261011T170049Z.tar.xz

echo "Extracting the stage file to /mnt/gentoo"
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo 

echo "Removing remnants of the stage tarball"
rm stage3-*.tar.xz

echo "Removing the old make.conf…"
rm /mnt/gentoo/etc/portage/make.conf

echo "Inserting the new make.conf"
cat << 'EOF' > /mnt/gentoo/etc/portage/make.conf
#These settings were set by the installation script you used.
#Please consult /usr/share/portage/config/make.conf.example for a more
#detailed example.

# Compiler flags to set for all languages
COMMON_FLAGS="-march=native -O2 -pipe"
# Use the same settings for both variables
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
RUSTFLAGS="${RUSTFLAGS} -C target-cpu=native"

#Default USE flags set by installer:
USE="-systemd bindist dist-kernel xfs stack-realign networkmanager grub"

#Default value for gpu drivers set by installer:
VIDEO_CARDS="nouveau intel i915 virgl amdgpu radeonsi"

#Default build options set by installer:
EMERGE_DEFAULT_OPTS="--quiet-build=y --complete-graph --with-bdeps=y"

#Default license variable set by installer:
ACCEPT_LICENSE="*"

#Default mirror set by installer:
GENTOO_MIRRORS="http://distfiles.gentoo.org"

#NOTE: This stage was built with the bindist USE flag enabled

#This sets the language of build output to English.
#Please keep this setting intact when reporting bugs.
LC_MESSAGES=C.UTF-8
EOF

echo "Setting CPU flags"
emerge --sync --quiet
emerge -1 app-portage/cpuid2cpuflags
echo "*/* $(cpuid2cpuflags)" > /mnt/gentoo/etc/portage/package.use/00cpu-flags

echo "Copying DNS info"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

echo "Entering chroot"
arch-chroot /mnt/gentoo << 'EOF'

echo "Configuring locales"
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set 4
env-update && source /etc/profile

echo "Setting dracut local flag for installkernel"
echo "sys-kernel/installkernel dracut" >> /etc/portage/package.use/installkernel

echo "Setting up portage"
emerge-webrsync
emerge --sync --quiet

echo "Installing Grub, Kernel, and Firmware"
emerge sys-kernel/gentoo-kernel
emerge sys-kernel/linux-firmware

echo "Installing networkmanager and adding it to default runlevel"
emerge networkmanager
rc-update add NetworkManager default

echo "Installing genfstab"
emerge -1 sys-fs/genfstab

echo "Setting up dbus"
dbus-uuidgen --ensure=/etc/machine-id

echo "Installing and enabling system tools"
emerge net-misc/chrony
rc-update add chronyd default
emerge sys-block/io-scheduler-udev-rules

echo "Installing grub"
grub-install --target=x86_64-efi --efi-directory=/efi --removable
grub-mkconfig -o /boot/grub/grub.cfg

echo "Updating packages to match USE flags set by new profile and make.conf"
emerge --verbose --update --deep --changed-use @world
EOF

echo "Generating fstab"
genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab

echo 'Exit chroot, the install is almost complete. Please run the command "arch-chroot /mnt/gentoo" and then set your password ussing the "passwd" command.'
echo "Once the new system has booted, please set hostname in /etc/hosts and /etc/hostname, along with a new root password, the default is 'localhost'"
echo "Installing app-portage/gentoolkit, is heavily suggested."
