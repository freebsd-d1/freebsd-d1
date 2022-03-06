#!/bin/sh



#dd if=/dev/zero of=licheerv.img bs=1M count=200
#md=`mdconfig licheerv.img`
#gpart create -s mbr $md
#gpart add -t fat32 -b 20m -s 54m $md
#gpart add -t freebsd $md

uboot_build() {
	pushd sun20i_d1_spl
	gmake CROSS_COMPILE=riscv64-none-elf- CFG_USE_MAEE=n p=sun20iw1p1 mmc
	popd

	pushd opensbi
	gmake CROSS_COMPILE=riscv64-none-elf- PLATFORM=generic FW_PIC=y
	popd

	pushd u-boot
	gmake CROSS_COMPILE=riscv64-none-elf- lichee_rv_defconfig
	gmake CROSS_COMPILE=riscv64-none-elf-
	cat > toc1.cfg << EOF
[opensbi]
file = ../opensbi/build/platform/generic/firmware/fw_dynamic.bin
addr = 0x40000000
[dtb]
file = arch/riscv/dts/sun20i-d1-lichee-rv.dtb
addr = 0x44000000
[u-boot]
file = u-boot-nodtb.bin
addr = 0x4a000000
EOF
	tools/mkimage -T sunxi_toc1 -d toc1.cfg u-boot.toc1
	popd
}

uboot_install() {
	md=`mdconfig $1`
	dd if=sun20i_d1_spl/nboot/boot0_sdcard_sun20iw1p1.bin of=/dev/$md bs=512 seek=256 conv=notrunc
	dd if=u-boot/u-boot.toc1 of=/dev/$md bs=512 seek=32800 conv=notrunc
	mdconfig -d -u $md	
}

freebsd_build() {
	#sh /usr/src/release/release.sh -c LICHEERV.conf
	pushd freebsd-src
	make CROSS_TOOLCHAIN=riscv64-gcc9 TARGET_ARCH=riscv64 buildworld
	make CROSS_TOOLCHAIN=riscv64-gcc9 TARGET_ARCH=riscv64 buildkernel
	popd
}

freebsd_install() {
}

rescue_build() {
	makefs -s 20m rescue.ufs /scratch/etc/mtree/BSD.root.dist
	md=`mdconfig rescue.ufs`
	mnt=`mktemp -d`
	mount /dev/$md $mnt
	tar -c -f - -C /scratch rescue | tar -x -f - -C $mnt
	ln -s -F /rescue $mnt/bin
	ln -s -F /rescue $mnt/sbin
	umount $mnt
	mdconfig -d -u $md
}

rescue_install() {
	md=`mdconfig $1`
	mnt=`mktemp -d`
	mount /dev/${md}p2 $mnt
	cp rescue.ufs $mnt
	cat >> $mnt/boot/loader.conf << EOF
rootfs_load="YES"
rootfs_name="/rescue.ufs"
rootfs_type="mfs_root"
vfs.root.mountfrom="ufs:/dev/md0"
EOF
	umount $mnt
	mdconfig -d -u $md
}

main() {
	pkg install riscv64-gcc9 riscv64-none-elf-gcc python3 bison swig py38-setuptools
}

img=FreeBSD-13.0-RELEASE-riscv-riscv64-LICHEERV.img
xz -d -c /scratch/R/$img.xz > $img
#uboot_build
uboot_install $img
rescue_build
rescue_install $img

