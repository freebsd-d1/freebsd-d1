# Copyright 2022 Julien Cassette <julien.cassette@gmail.com>

COMMON_OPTS += OBJROOT=$(PWD)/freebsd/obj/
COMMON_OPTS += SRCCONF=$(PWD)/src.conf

BUILD_OPTS += $(COMMON_OPTS)
BUILD_OPTS += CROSS_TOOLCHAIN=llvm14
BUILD_OPTS += TARGET=riscv
BUILD_OPTS += TARGET_ARCH=riscv64

INSTALL_OPTS += $(COMMON_OPTS)
INSTALL_OPTS += MACHINE=riscv
INSTALL_OPTS += MACHINE_ARCH=riscv64

MD := md99

.PHONY: all clean spl u-boot opensbi freebsd image

all: freebsd image

clean:
	-chflags -R noschg efisys mfsroot rootfs
	-rm -rf efisys mfsroot rootfs
	-rm -f efisys.fat mfsroot.ufs rootfs.ufs freebsd-d1.img

spl:
	gmake -C sun20i_d1_spl CROSS_COMPILE=riscv64-none-elf- CFG_USE_MAEE=n p=sun20iw1p1 mmc

opensbi:
	gmake -C opensbi CROSS_COMPILE=riscv64-none-elf- PLATFORM=generic FW_PIC=y

u-boot/.config:
	gmake -C u-boot CROSS_COMPILE=riscv64-none-elf- lichee_rv_defconfig

u-boot: u-boot/.config
u-boot:
	gmake -C u-boot CROSS_COMPILE=riscv64-none-elf-

toc1.bin: opensbi u-boot toc1.cfg
	u-boot/tools/mkimage -T sunxi_toc1 -d toc1.cfg toc1.bin

freebsd:
	env -i CCACHE_BASEDIR=$(PWD)/freebsd \
	    bmake -C freebsd/src \
	    $(BUILD_OPTS) \
	    buildworld buildkernel

image: freebsd-d1.img

efisys.fat:
	mkdir -p efisys/efi
	env -i \
	    bmake -C freebsd/src \
	    $(INSTALL_OPTS) \
	    SUBDIR_OVERRIDE="stand/efi/loader_4th" \
	    DESTDIR=$(PWD)/efisys/efi \
	    install
	mv efisys/efi/boot/loader.efi efisys/efi/boot/bootriscv64.efi
	rm efisys/efi/boot/loader*
	makefs -t msdos -s 40m -o fat_type=32,sectors_per_cluster=1,volume_label=EFISYS efisys.fat efisys

mfsroot.ufs:
	mkdir -p mfsroot
	env -i \
	    bmake -C freebsd/src \
	    $(INSTALL_OPTS) \
	    SUBDIR_OVERRIDE="lib libexec rescue usr.sbin/watchdogd" \
	    DESTDIR=$(PWD)/mfsroot \
	    installworld
	ln -s -F /rescue mfsroot/bin
	ln -s -F /rescue mfsroot/sbin
	makefs -t ffs -R 10m -o label=mfsroot mfsroot.ufs mfsroot

rootfs.ufs: mfsroot.ufs
rootfs.ufs:
	mkdir -p rootfs
	env -i \
	    bmake -C freebsd/src \
	    $(INSTALL_OPTS) \
	    SUBDIR_OVERRIDE="stand" \
	    DESTDIR=$(PWD)/rootfs \
	    install installkernel
	cp mfsroot.ufs rootfs
	echo 'boot_verbose="YES"' > rootfs/boot/loader.conf
	echo 'rootfs_load="YES"' >> rootfs/boot/loader.conf
	echo 'rootfs_name="/mfsroot.ufs"' >> rootfs/boot/loader.conf
	echo 'rootfs_type="mfs_root"' >> rootfs/boot/loader.conf
	echo 'vfs.root.mountfrom="ufs:/dev/md0"' >> rootfs/boot/loader.conf
	makefs -t ffs -R 10m -o label=rootfs rootfs.ufs rootfs

freebsd-d1.img: spl toc1.bin efisys.fat rootfs.ufs
	dd if=/dev/zero of=freebsd-d1.img.tmp bs=1m count=320
	mdconfig -u $(MD) freebsd-d1.img.tmp
	gpart create -s gpt $(MD)
	gpart add -t efi -b 20m -s 50m $(MD)
	gpart add -t freebsd-ufs $(MD)
	dd if=sun20i_d1_spl/nboot/boot0_sdcard_sun20iw1p1.bin of=/dev/$(MD) bs=512 seek=256 conv=notrunc
	dd if=toc1.bin of=/dev/$(MD) bs=512 seek=32800 conv=notrunc
	dd if=efisys.fat of=/dev/$(MD)p1 bs=1m conv=notrunc
	dd if=rootfs.ufs of=/dev/$(MD)p2 bs=1m conv=notrunc
	mdconfig -d -u $(MD)
	mv freebsd-d1.img.tmp freebsd-d1.img

