# gentooinstall

THIS SCRIPT INSTALLS GENTOO TO ANY PARTITION MOUNTED ON /mnt/gentoo AND /mnt/gentoo/efi THESE MUST BE FORMATTED.

Requirements:
Gentoo LiveGUI, 2 Partitions Mounted to /mnt/gentoo and /mnt/gentoo/efi, good music, and a computer. Target root partition must be formatted with xfs and efi must be formatted with fat32 or exfat.

This script theoretically works on any linux distro with chronyd,wget, tar, and the bash shell installed. 

This script uses grub and installs the dist-kernel by default. 

Installing gentoo using the official documentation is suggested as if you do not, you will have no idea how to manage the system after the installation.
