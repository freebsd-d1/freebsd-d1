

all: licheerv.img

MD := md99

sun20i_d1_spl/nboot/boot0_sdcard_sun20iw1p1.bin:
	gmake -C sun20i_d1_spl CROSS_COMPILE=riscv64-none-elf- CFG_USE_MAEE=n p=sun20iw1p1 mmc

u-boot.toc1:
	gmake -C opensbi CROSS_COMPILE=riscv64-none-elf- PLATFORM=generic FW_PIC=y
	gmake -C u-boot CROSS_COMPILE=riscv64-none-elf- lichee_rv_defconfig
	gmake -C u-boot CROSS_COMPILE=riscv64-none-elf-
	u-boot/tools/mkimage -T sunxi_toc1 -d toc1.cfg u-boot.toc1

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
	makefs -t ffs -R 10m -o label=mfsroot mfsroot.ufs mfsroot

rootfs.ufs: mfsroot.ufs
rootfs.ufs:
	mkdir -p rootfs
	tar -c -f - -C root boot | tar -x -f - -C rootfs
	cp mfsroot.ufs rootfs
	echo > rootfs/boot/loader.conf
	echo 'rootfs_load="YES"' >> rootfs/boot/loader.conf
	echo 'rootfs_name="/mfsroot.ufs"' >> rootfs/boot/loader.conf
	echo 'rootfs_type="mfs_root"' >> rootfs/boot/loader.conf
	echo 'vfs.root.mountfrom="ufs:/dev/md0"' >> rootfs/boot/loader.conf
	makefs -t ffs -R 10m -o label=rootfs rootfs.ufs rootfs

licheerv.img: sun20i_d1_spl/nboot/boot0_sdcard_sun20iw1p1.bin
licheerv.img: u-boot.toc1
licheerv.img: efisys.fat
licheerv.img: rootfs.ufs
licheerv.img:
	mkimg -s gpt -p efi:=efisys.fat:20m -p freebsd-ufs:=rootfs.ufs -o licheerv.img.tmp
	mdconfig -u $(MD) licheerv.img.tmp
	dd if=sun20i_d1_spl/nboot/boot0_sdcard_sun20iw1p1.bin of=/dev/$(MD) bs=512 seek=256 conv=notrunc
	dd if=u-boot.toc1 of=/dev/$(MD) bs=512 seek=32800 conv=notrunc
	mdconfig -d -u $(MD)
	mv licheerv.img.tmp licheerv.img

