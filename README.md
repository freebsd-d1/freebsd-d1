# FreeBSD on Allwinner D1

## Usage

```
pkg install ccache llvm14
make -C freebsd-src CROSS_TOOLCHAIN=llvm14 TARGET_ARCH=riscv64 SRCCONF=$PWD/src.conf buildworld buildkernel
make -C freebsd-src CROSS_TOOLCHAIN=llvm14 TARGET_ARCH=riscv64 SRCCONF=$PWD/src.conf DESTDIR=$PWD/root installworld distribution installkernel
pkg install riscv64-none-elf-gcc python3 bison swig py38-setuptools
gmake
dd if=freebsd-d1.img of=/dev/mmc0
```

