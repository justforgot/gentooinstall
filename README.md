# gentooinstall

THIS SCRIPT INSTALLS GENTOO TO ANY PARTITION MOUNTED ON /mnt/gentoo AND /mnt/gentoo/efi THESE MUST BE FORMATTED.

Run this script while logged in as the root user, this can be done by running the command "sudo -i" on all gentoo installation media.

Requirements:
Gentoo installation media, 2 Partitions Mounted to /mnt/gentoo and /mnt/gentoo/efi respectively, good music, and a computer. Target root partition must be formatted with xfs and efi must be formatted with fat32 or exfat.

Target root partition must be at least 32GB to comfortably install, and the efi partition must be at least 256MB.

This script theoretically works on any linux distro with chronyd, wget, tar, arch-chroot, and the bash shell installed. 

This script uses grub and installs the dist-kernel by default. 

Once the script finishes you must set the password for the new installation by first running `arch-chroot /mnt/gentoo` to enter the chroot. You must then set the password by using the command `passwd` and choosing a secure password. There are no password requirements besides that it must have one or more characters.

Installing gentoo using the official documentation is suggested as if you do not, you will have no idea how to manage the system after the installation.

<img width="1282" height="909" alt="image" src="https://github.com/user-attachments/assets/acad809a-8d89-43d3-8e7d-44d5dfc0125a" />
