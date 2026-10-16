#!/bin/bash

printf "STARTING justforgot/gentooinstall SCRIPT v1.1 r26!!\n\n\n"

# error handler that prints the failed line number in this script
set -eE
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }
trap 'rc=$?; printf "\nERROR: command failed at line %s (exit code %s)\n" "$LINENO" "$rc" >&2' ERR

# misc sanity checks
[ "$(id -u)" -eq 0 ] || die "Run this script as root."
[ -d /sys/firmware/efi ] || die "Live system was not booted in UEFI mode (no /sys/firmware/efi). This script only installs UEFI bootloaders."
mountpoint -q /mnt/gentoo || die "/mnt/gentoo is not a mount point. Partition, format and mount your root partition there first (and /boot too, if it is a separate partition)."

# unmounts previous left-over gentoo chroots that could cause an installation failure
findmnt -rn -R -o TARGET,FSTYPE /mnt/gentoo | tac | while read -r tgt fst; do
    [ "$tgt" = "/mnt/gentoo" ] && continue
    case "$fst" in
        proc|sysfs|efivarfs|devtmpfs|devpts|tmpfs|overlay|mqueue|cgroup2)
            printf "Unmounting leftover mount: %s (%s)\n" "$tgt" "$fst"
            umount "$tgt" 2> /dev/null || umount -l "$tgt" ;;
    esac
done

printf "Syncing time using chronyd...\n"
chronyd -u root -q || printf "WARNING: time sync failed, continuing anyway.\n"
hwclock -w || printf "WARNING: could not write the hardware clock, continuing anyway.\n"

# gets the latest amd64 stage3 tarballs for normal openrc and systemd, along with the hardened ones
# you probably could expand this list to the other special stage3 types if wanted lol
printf "Retrieving available stage files from Gentoo autobuilds...\n"
DISTFILES_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/"
SUBDIRS=(
    "current-stage3-amd64-desktop-openrc"
    "current-stage3-amd64-desktop-systemd"
    "current-stage3-amd64-hardened-openrc"
    "current-stage3-amd64-hardened-systemd"
)
mapfile -t stages < <(
    ls -1v stage3-*.tar.xz 2>/dev/null ||
    (
        echo "Fetching stage list from Gentoo mirror..." >&2
        for sub in "${SUBDIRS[@]}"; do
            curl -s "${DISTFILES_BASE}${sub}/" | grep -oP 'stage3-.*?\.tar\.xz' | sort -V | tail -n 1
        done | sort -u
    )
)
[ "${#stages[@]}" -gt 0 ] || die "Could not find or fetch any stage3 files."

printf "Available stage files:\n"
for idx in "${!stages[@]}"; do
    printf "%d) %s\n" $((idx+1)) "${stages[$idx]}"
done

read -r -p "Select stage file by number (default 1): " STAGE_CHOICE
stage_index=${STAGE_CHOICE:-1}
if ! [[ "$stage_index" =~ ^[0-9]+$ ]] || [ "$stage_index" -lt 1 ] || [ "$stage_index" -gt "${#stages[@]}" ]; then
    die "Invalid stage selection: $stage_index"
fi
STAGE_FILE="${stages[$((stage_index-1))]}"

if [ ! -f "$STAGE_FILE" ]; then
    echo "Downloading $STAGE_FILE from ${DISTFILES_BASE}..."
    for sub in "${SUBDIRS[@]}"; do
        if echo "$STAGE_FILE" | grep -q "${sub#current-}"; then
            wget -O "$STAGE_FILE" "${DISTFILES_BASE}${sub}/${STAGE_FILE}" || { rm -f "$STAGE_FILE"; die "Download of $STAGE_FILE failed."; }
            break
        fi
    done
fi

if [[ "$STAGE_FILE" == *openrc* ]]; then
    INIT_SYSTEM=openrc
elif [[ "$STAGE_FILE" == *systemd* ]]; then
    INIT_SYSTEM=systemd
else
    INIT_SYSTEM=openrc
fi

# ONLY GRUB IS IMPLEMENTED ATM lol could probably just remove the other bootloader options unless we wanna expand this script
read -r -p "Choose bootloader ONLY GRUB IS SUPPORTED AT THIS TIME (1) limine (2) grub (3) refind (4) efi stub (5) systemd-boot [2]: " BOOTLOADER_CHOICE
case "$BOOTLOADER_CHOICE" in
  1) BOOTLOADER=limine ;;
  2) BOOTLOADER=grub ;;
  3) BOOTLOADER=refind ;;
  4) BOOTLOADER=efi-stub ;;
  5) BOOTLOADER=systemd-boot ;;
  *) BOOTLOADER=grub ;;
esac

if [ "$BOOTLOADER" != "grub" ]; then
    die "Bootloader '$BOOTLOADER' is not implemented in this script yet. Re-run and choose grub (2)."
fi

read -r -p "Enter your EFI system partition device (e.g., /dev/sda1 or /dev/nvme0n1p1): " EFI_PART
[ -b "$EFI_PART" ] || die "'$EFI_PART' is not a block device."

read -r -p "Choose network manager (1) NetworkManager (2) dhcpcd [1]: " NM_CHOICE
[[ -z "${NM_CHOICE}" || "${NM_CHOICE}" != "2" ]] && NM_PACKAGE=networkmanager || NM_PACKAGE=dhcpcd

read -r -p "Choose fstab generator (1) genfstab (2) systemd-fstab-generator [1]: " FSTAB_CHOICE
[[ -z "${FSTAB_CHOICE}" || "${FSTAB_CHOICE}" != "2" ]] && FSTAB_GEN=genfstab || FSTAB_GEN=sd-fstab-generator

printf "Detecting GPU for USE flags...\n"
GPU_FLAGS=""
GPU_INFO=$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible|3D controller|Display controller' || true)
if grep -qi 'nvidia' <<< "$GPU_INFO"; then
    # FIX ME: not including nouveau might make this incompatible with older NVIDIA gpus that dont have a propietary driver available through the nvidia keyword
    # but the propietary nvidia driver is preferred over the outdated nouveau driver.
    GPU_FLAGS="$GPU_FLAGS nvidia"
fi
if grep -qi 'intel' <<< "$GPU_INFO"; then
    GPU_FLAGS="$GPU_FLAGS intel i915 i965"
fi
# case sensitive search for amd gpus
if grep -qE 'AMD|Advanced Micro Devices|Radeon' <<< "$GPU_INFO"; then
    GPU_FLAGS="$GPU_FLAGS amdgpu radeonsi"
fi
GPU_FLAGS="${GPU_FLAGS# }"

# set preliminary use flags, and then check if we actually wanted systemd or openrc
USE_FLAGS="-systemd bindist dist-kernel xfs stack-realign"
[[ "$INIT_SYSTEM" == "systemd" ]] && USE_FLAGS="$USE_FLAGS systemd" || USE_FLAGS="$USE_FLAGS openrc"
# assemble the final use flags
USE_FLAGS="$USE_FLAGS $NM_PACKAGE $GPU_FLAGS"

[ -f "$STAGE_FILE" ] || die "stage file $STAGE_FILE not found."

printf "Extracting stage file to /mnt/gentoo\n"
# in my testing the --xattrs-include='*.*' caused some errors so if it fails, we try again without including attributes
# it is very much preferred for the tarball attributes to be included though...
TAR_LOG=$(mktemp /tmp/stage3-tar.XXXXXX.log)
if ! tar xpvf ./"$STAGE_FILE" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo 2> "$TAR_LOG"; then
    printf "\nWARNING: extraction with xattrs failed. The actual tar errors were:\n"
    grep '^tar:' "$TAR_LOG" | head -n 15 || true
    printf "\nRetrying without xattrs...\n"
    if ! tar xpvf ./"$STAGE_FILE" --numeric-owner -C /mnt/gentoo 2> "$TAR_LOG"; then
        printf "\nThe actual tar errors were:\n"
        grep '^tar:' "$TAR_LOG" | head -n 30 || true
        die "Extracting $STAGE_FILE failed even without xattrs. Full tar error log: $TAR_LOG"
    fi
fi

mkdir -p /mnt/gentoo/efi
mountpoint -q /mnt/gentoo/efi || mount "$EFI_PART" /mnt/gentoo/efi

printf "Entering mounted root partition\n"
cd /mnt/gentoo

# clear leftover stage3 tarball and clear the existing make.conf so we can insert our own make.conf
# (idk if the stage3 tarball remove actually works though because right before this we changed directory to /mnt/gentoo which is NOT where the tarball was downloaded into originally)
rm -f stage3-*.tar.xz
rm -f /mnt/gentoo/etc/portage/make.conf

NCPU=$(grep -c ^processor /proc/cpuinfo)

cat << EOF > /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="-march=native -O2 -pipe"
CXXFLAGS="-march=native -O2 -pipe"
FCFLAGS="-march=native -O2 -pipe"
FFLAGS="-march=native -O2 -pipe"
RUSTFLAGS="${RUSTFLAGS} -C target-cpu=native"

USE="$USE_FLAGS"
VIDEO_CARDS="$GPU_FLAGS"

MAKEOPTS="-j${NCPU:-1} -l${NCPU:-1}"
ACCEPT_LICENSE="*"
EOF

if [ "$BOOTLOADER" = "grub" ]; then
    echo 'GRUB_PLATFORMS="efi-64"' >> /mnt/gentoo/etc/portage/make.conf
fi

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# fabricate a chroot-install.sh script and run it
# this works better than the bullshit before lol
mkdir -p /mnt/gentoo/root
cat << 'CHROOT_EOF' > /mnt/gentoo/root/chroot-install.sh
#!/bin/bash
source /etc/profile
env-update

set -eE
die() { printf "\nERROR (chroot): %s\n" "$*" >&2; exit 1; }
trap 'rc=$?; printf "\nERROR (chroot): command failed at line %s (exit code %s)\n" "$LINENO" "$rc" >&2' ERR

: "${BOOTLOADER:?}" "${NM_PACKAGE:?}" "${INIT_SYSTEM:?}"

printf "Configuring package.use override for curl...\n"
mkdir -p /etc/portage/package.use
echo "net-misc/curl -http3 -quic" > /etc/portage/package.use/curl

printf "Configuring locales\n"
grep -qxF "en_US.UTF-8 UTF-8" /etc/locale.gen 2> /dev/null || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8 || printf "WARNING: could not set the system locale.\n"
env-update

printf "Cleaning stale timestamp file...\n"
rm -f /var/db/repos/gentoo/metadata/timestamp.x

printf "Setting up portage securely via webrsync\n"
emerge-webrsync

printf "Setting CPU flags\n"
emerge -1 app-portage/cpuid2cpuflags
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags

printf "Setting dracut + grub flags for installkernel\n"
echo "sys-kernel/installkernel dracut grub" > /etc/portage/package.use/installkernel

printf "Installing bullshit dependencies\n"
emerge sys-devel/bc app-text/asciidoc
FEATURES="-collision-detect -protect-owned" emerge --oneshot app-arch/cpio

# installkernel must exist before linux-firmware/gentoo-kernel are merged: with the
# dist-kernel USE flag their post-install step calls it, and fails with
# "installkernel: command not found" otherwise.
printf "Installing installkernel\n"
emerge sys-kernel/installkernel

printf "Installing dracut initramfs generator\n"
emerge sys-kernel/dracut

printf "Configuring custom MAKEOPTS for gentoo-kernel...\n"
mkdir -p /etc/portage/env
echo 'MAKEOPTS="-j3 -l4"' > /etc/portage/env/kernel-makeopts.conf
grep -qxF "sys-kernel/gentoo-kernel kernel-makeopts.conf" /etc/portage/package.env 2> /dev/null || echo "sys-kernel/gentoo-kernel kernel-makeopts.conf" >> /etc/portage/package.env

printf "Installing linux-firmware (before the kernel so the initramfs can use it)\n"
emerge sys-kernel/linux-firmware

printf "Installing gentoo-kernel with restricted parallel jobs\n"
emerge sys-kernel/gentoo-kernel

# check if the kernel was actually installed correctly, and reconfiguring it if it wasnt
if ! ls /boot/vmlinuz-* > /dev/null 2>&1; then
    printf "No kernel in /boot yet, asking gentoo-kernel to redeploy it...\n"
    emerge --config sys-kernel/gentoo-kernel || true
fi

# sanity check for the kernel image and initramfs actually existing, the installed gentoo will not be bootable if they dont exist
ls /boot/vmlinuz-* > /dev/null 2>&1 || die "No kernel image (/boot/vmlinuz-*) after installing gentoo-kernel. Check the emerge output above. If /boot is a separate partition it must be mounted at /mnt/gentoo/boot before running this script."
ls /boot/initramfs-* > /dev/null 2>&1 || printf "WARNING: no initramfs found in /boot. The system may not boot if root needs one.\n"

printf "Installing network manager\n"
emerge "$NM_PACKAGE"
if [ "$INIT_SYSTEM" = "systemd" ]; then
    if [ "$NM_PACKAGE" = "networkmanager" ]; then
        systemctl enable NetworkManager
    else
        systemctl enable dhcpcd
    fi
else
    if [ "$NM_PACKAGE" = "networkmanager" ]; then
        rc-update add NetworkManager default
    else
        rc-update add dhcpcd default
    fi
fi

dbus-uuidgen --ensure=/etc/machine-id || true

echo "localhost" > /etc/hostname
grep -qxF "127.0.0.1 localhost" /etc/hosts 2> /dev/null || echo "127.0.0.1 localhost" >> /etc/hosts

emerge net-misc/chrony

printf "Installing bootloader: $BOOTLOADER\n"
emerge sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=gentoo --recheck
grub-mkconfig -o /boot/grub/grub.cfg
grep -q 'vmlinuz' /boot/grub/grub.cfg || die "grub.cfg contains no kernel entries. Check that /boot/vmlinuz-* exists and re-run grub-mkconfig."

printf "Updating world with new USE flags\n"
emerge --verbose --update --deep --changed-use @world
CHROOT_EOF
chmod 700 /mnt/gentoo/root/chroot-install.sh

#here we enter the chroot and simply execute the previously fabricated chroot-install.sh
printf "Entering chroot\n"
arch-chroot /mnt/gentoo /usr/bin/env \
    BOOTLOADER="$BOOTLOADER" NM_PACKAGE="$NM_PACKAGE" INIT_SYSTEM="$INIT_SYSTEM" FSTAB_GEN="$FSTAB_GEN" \
    /bin/bash /root/chroot-install.sh
rm -f /mnt/gentoo/root/chroot-install.sh

printf "Generating fstab\n"
if [ "$FSTAB_GEN" = "genfstab" ]; then
    genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab
fi

# THE DEFAULT USERNAME AND PASSWORD ARE "gentoo", YOU MUST CHANGE THE PASSWORD AFTER INSTALLATION!!!!!!!
printf "\n\nSetting root password (default: gentoo)\n"
arch-chroot /mnt/gentoo passwd <<EOF
gentoo
gentoo
EOF

printf "Installation complete! You can now reboot into your new system.\n"
