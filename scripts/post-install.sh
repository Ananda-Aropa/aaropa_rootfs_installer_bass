#!/bin/bash
# shellcheck disable=SC2046

# # Copy grub2 theme
# cp -r /usr/share/grub/themes /iso/boot/grub
# cp -r /usr/share/grub/themes /boot/grub
# mkdir -p /boot/grub/themes /usr/share/grub/themes
# found_themes="$(find /iso/boot/grub/themes -mindepth 1 -maxdepth 1 -type d -print -quit)"

# Generate a grub-rescue iso so we can use it as the base for the iso
# --themes="$found_themes" \
grub-mkrescue \
	-o /grub-rescue.iso \
	/iso
rm -rf /iso

##############
### INITRD ###
##############

# Generate initrd template
mkdir -p /initrd_lib/usr/{bin,lib,lib64}
ln -st /initrd_lib usr/{bin,lib,lib64}

# Copy binaries and libraries
find_dep() { ldd "$1" | awk '{print $3}' | xargs; }
for b in mount.ntfs-3g dmidecode; do
	b=$(which $b)
	cp -t /initrd_lib/bin $b
	cp -t /initrd_lib/lib $(find_dep "$b")
done

# Busybox is explicitly handled
cp -t /initrd_lib/bin /usr/share/bliss/busybox
cp -t /initrd_lib/lib $(find_dep /initrd_lib/bin/busybox)

# Linker
cp -t /initrd_lib/bin /bin/ld.so
cp -t /initrd_lib/lib /usr/lib/*/ld-linux-x86-64.so.*
cp -t /initrd_lib/lib64 /usr/lib64/ld-linux-x86-64.so.*

# Wrap initrd up
tar -czvf /initrd_lib.tar.gz /initrd_lib

####################
### NEWINSTALLER ###
####################

ARCH=$(dpkg --print-architecture)

case "$ARCH" in
amd64) ARCH=x86_64 ;;
arm64) ARCH=aarch64 ;;
*) ;;
esac

# Generate root template
mkdir -p /install_lib/usr/{bin,lib,share}
ln -s bin /install_lib/usr/sbin
ln -s lib /install_lib/usr/lib64
ln -s . /install_lib/lib/${ARCH}-linux-gnu
ln -st /install_lib usr/{{s,}bin,lib{,64}}

# Copy binaries and libraries
declare -a B=(
	/usr/share/bliss/busybox
	bash
	fdisk
	cfdisk
	sfdisk
	cgdisk
	sgdisk
	dialog
	efibootmgr
	grub-install
	pv
	tune2fs
	dmidecode
)

# Filesystem support
# BTRFS is not included due to not supporting booting sparse files
B+=(
	mkfs
	mke2fs
	mkfs.f2fs
	mkfs.fat
	mkfs.exfat
	mkfs.ntfs
	fsck
	e2fsck
	fsck.f2fs
	fsck.fat
	fsck.exfat
	fsck.ntfs
)

get_next_readlink() {
	local next
	next=$(readlink "$1")
	case "$next" in
	/*) ;;
	*)
		cd $1
		next=$(pwd)/$next
		cd -
		;;
	esac
	export RETURN=$next
}

for b in "${B[@]}"; do
	b=$(readlink -f "$(which "$b")")
	cp -t /install_lib/bin "$b"
	for dep in $(find_dep "$b"); do
		_l=$dep
		get_next_readlink "$_l"
		while [ "$RETURN" != "$_l" ]; do
			cp -t /install_lib/lib "$_l"
			_l="$RETURN"
			get_next_readlink "$_l"
		done
		cp -t /install_lib/lib "$RETURN"
	done
done

# Expand links for filesystems
ln -s mke2fs /install_lib/bin/mkfs.ext4
ln -s mkfs.ext4 /install_lib/bin/mkfs.ext3
ln -s mkfs.ext4 /install_lib/bin/mkfs.ext2

ln -s mkfs.fat /install_lib/bin/mkfs.vfat
ln -s mkfs.fat /install_lib/bin/mkfs.msdos
ln -s mkfs.fat /install_lib/bin/mkdosfs

ln -s e2fsck /install_lib/bin/fsck.ext4
ln -s fsck.ext4 /install_lib/bin/fsck.ext3
ln -s fsck.ext4 /install_lib/bin/fsck.ext2

ln -s fsck.fat /install_lib/bin/fsck.vfat
ln -s fsck.fat /install_lib/bin/fsck.msdos

# Specical packages
cp -rt /install_lib/lib /usr/lib/grub
ln -s grub /install_lib/usr/lib/grub2
cp -rt /install_lib/usr/share /usr/share/grub

# Linker
cp -t /install_lib/bin /bin/ld.so
cp -t /install_lib/lib /usr/lib/*/ld-linux-${ARCH}.so.*
cp -t /initrd_lib/lib64 /usr/lib64/ld-linux-${ARCH}.so.*

# Wrap initrd up
tar -czvf /install_lib.tar.gz /install_lib

exit 0
