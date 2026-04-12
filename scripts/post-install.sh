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

ARCH=${ARCH//_/-}

# Generate root template
mkdir -p /install_lib/{etc/grub.d,usr/{bin,lib,share}}
ln -s bin /install_lib/usr/sbin
ln -s lib /install_lib/usr/lib64
ln -s . /install_lib/usr/lib/${ARCH}-linux-gnu
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
	pv
	tune2fs
	dmidecode
	linux-boot-prober
	os-prober
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

# GRUB
B+=(
	grub-bios-setup
	grub-editenv
	grub-file
	grub-fstest
	grub-glue-efi
	grub-install
	grub-kbdcomp
	grub-macbless
	grub-menulst2cfg
	grub-mkconfig
	grub-mkfont
	grub-mkimage
	grub-mklayout
	grub-mknetdir
	grub-mkpasswd-pbkdf2
	grub-mkrelpath
	grub-mkrescue
	grub-mkstandalone
	grub-mount
	grub-ofpathname
	grub-probe
	grub-protect
	grub-reboot
	grub-render-label
	grub-script-check
	grub-set-default
)

get_next_readlink() {
	if [ ! -h "$1" ]; then
		export RETURN=$1
		return
	fi

	local next
	next=$(readlink "$1")
	case "$next" in
	/*) ;;
	'') next=$1 ;;
	*) next=$(dirname "$1")/$next ;;
	esac
	export RETURN=$next
}

for b in "${B[@]}"; do
	b=$(readlink -f "$(which "$b")")
	cp -t /install_lib/usr/bin "$b"
	for dep in $(find_dep "$b"); do
		_l=$dep
		get_next_readlink "$_l"
		while [ "$RETURN" != "$_l" ]; do
			cp -t /install_lib/usr/lib "$_l"
			_l="$RETURN"
			get_next_readlink "$_l"
		done
		cp -t /install_lib/usr/lib "$RETURN"
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
# grub
cp -rt /install_lib/lib /usr/lib/grub
ln -s grub /install_lib/usr/lib/grub2
cp -rt /install_lib/usr/share /usr/share/grub
cp -rt /install_lib/etc/grub.d /etc/grub.d/{00_header,25_bli,30_os-prober,40_custom,41_custom}
# os-prober
cp -rt /install_lib/lib /usr/lib/{os-prober,os-probes,linux-boot-probes}
cp -rt /install_lib/usr/share /usr/share/os-prober

# Linker
cp -t /install_lib/bin /bin/ld.so
cp -t /install_lib/lib /usr/lib/*/ld-linux-${ARCH}.so.*
cp -t /initrd_lib/lib64 /usr/lib64/ld-linux-${ARCH}.so.* # In case the command above fails

# Wrap initrd up
tar -czvf /install_lib.tar.gz /install_lib

exit 0
