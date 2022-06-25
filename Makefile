# Copyright 2022 Julien Cassette <julien.cassette@gmail.com>

MD := md99

.PHONY: all clean spl u-boot opensbi

all: freebsd-d1.img

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

efisys.fat:
	mkdir -p efisys/EFI/BOOT
	cp root/boot/loader.efi efisys/EFI/BOOT/BOOTRISCV64.EFI
	makefs -t msdos -s 40m -o fat_type=32,sectors_per_cluster=1,volume_label=EFISYS efisys.fat efisys

mfsroot.ufs:
	mkdir -p mfsroot
	mtree -d -e -U -f root/etc/mtree/BSD.root.dist -p mfsroot
	tar -c -f - -C root rescue | tar -x -f - -C mfsroot
	ln -s -F /rescue mfsroot/bin
	ln -s -F /rescue mfsroot/sbin
	tar -c -f - -C root lib | tar -x -f - -C mfsroot
	tar -c -f - -C root libexec | tar -x -f - -C mfsroot
	tar -c -f - -C root usr/sbin/watchdog | tar -x -f - -C mfsroot
	-tar -c -f - -C root boot/kernel/aw_mmc.ko | tar -x -f - -C mfsroot
	makefs -t ffs -R 10m -o label=mfsroot mfsroot.ufs mfsroot

rootfs.ufs: mfsroot.ufs
rootfs.ufs:
	mkdir -p rootfs
	tar -c -f - -C root boot | tar -x -f - -C rootfs
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

