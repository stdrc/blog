---
title: 编译一个 AArch64 平台的最小 Linux 内核
categories: Dev
tags: [Linux, OS, 内核, BusyBox, QEMU, ARM, AArch64]
created: 2020-09-12 10:06:00
---

总结一下最近折腾的事情，方便以后查阅。

> 所有内容都假设已经安装了必须的构建工具链，如果没有装，可以在报错的时候再根据提示安装。

## 编译 BusyBox

需要先编译一个 BusyBox 作准备，之后作为 rootfs 加载。

在 [这里](https://busybox.net/downloads/) 下载适当版本的 BusyBox 源码并解压，然后运行：

```bash
cd busybox-1.32.0
mkdir build

make O=build ARCH=arm64 defconfig
make O=build ARCH=arm64 menuconfig
```

这会首先生成默认配置，然后开启一个配置菜单。在「Settings」里面修改下面几项配置：

```
[*] Don't use /usr
[*] Build static binary (no shared libs)
(aarch64-linux-gnu-) Cross compiler prefix
```

然后保存并退出。运行：

```bash
make O=build # -j8
make O=build install
cd build/_install
```

这会使用刚刚保存的配置进行编译，然后安装到 `build/_install` 目录，此时该目录如下：

```bash
$ tree -L 1 .
.
├── bin
├── linuxrc -> bin/busybox
└── sbin

2 directories, 1 file
```

接着创建一些空目录：

```bash
mkdir -pv {etc,proc,sys,usr/{bin,sbin}}
```

然后创建一个 `init` 文件，内容如下：

```bash
#!/bin/sh

mount -t proc none /proc
mount -t sysfs none /sys

echo -e "\nBoot took $(cut -d' ' -f1 /proc/uptime) seconds\n"

exec /bin/sh
```

修改 `init` 文件为可执行：

```bash
chmod +x init
```

此时当前目录（`build/_install`）内容如下：

```bash
$ tree -L 1 .
.
├── bin
├── etc
├── init
├── linuxrc -> bin/busybox
├── proc
├── sbin
├── sys
└── usr

6 directories, 2 files
```

把这些目录和文件打包：

```bash
find . -print0 | cpio --null -ov --format=newc | gzip > ../initramfs.cpio.gz
```

生成的 gzip 压缩后的 cpio 映像放在了 `build/initramfs.cpio.gz`，此时 BusyBox ramdisk 就做好了，保存备用。

## 编译最小配置的 Linux 内核

在 [这里](https://www.kernel.org/) 下载适当版本的内核源码并解压，然后运行：

```bash
cd linux-5.8.8
mkdir build

make O=build ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- allnoconfig
make O=build ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
```

这会首先初始化一个最小的配置（`allnoconfig`），然后打开配置菜单。在配置菜单中做以下修改：

```
-> General setup
[*] Initial RAM filesystem and RAM disk (initramfs/initrd) support

-> General setup
  -> Configure standard kernel features
[*] Enable support for printk

-> Executable file formats / Emulations
[*] Kernel support for ELF binaries
[*] Kernel support for scripts starting with #!

-> Device Drivers
  -> Generic Driver Options
[*] Maintain a devtmpfs filesystem to mount at /dev
[*]   Automount devtmpfs at /dev, after the kernel mounted the rootfs

-> Device Drivers
  -> Character devices
[*] Enable TTY

-> Device Drivers
  -> Character devices
    -> Serial drivers
[*] ARM AMBA PL010 serial port support
[*]   Support for console on AMBA serial port
[*] ARM AMBA PL011 serial port support
[*]   Support for console on AMBA serial port

-> File systems
  -> Pseudo filesystems
[*] /proc file system support
[*] sysfs file system support
```

完成后保存并退出，再运行：

```bash
make O=build ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- # -j8
```

即可编译 Linux 内核，编译出来的两个东西比较有用，一个是 `build/vmlinux`，另一个是 `build/arch/arm64/boot/Image`，前者是 ELF 格式的内核，可以用来在 GDB 中加载调试信息，后者是可启动的内核映像文件。

## 编译 qemu-system-aarch64

这一步是可选的，直接使用包管理器安装 QEMU 也可以。

在 [这里](https://download.qemu.org/) 下载适当版本的 QEMU 源码并解压，然后运行：

```bash
cd qemu-5.0.0

mkdir build
cd build

../configure --target-list=aarch64-softmmu
make # -j8
```

即可编译 AArch64 目标架构的 QEMU。

## 启动 Linux

为了清晰起见，回到上面三个源码目录的外层，即当前目录中内容如下：

```bash
$ tree -L 1 .
.
├── busybox-1.32.0
├── linux-5.8.8
└── qemu-5.0.0

3 directories, 0 files
```

然后使用 QEMU 启动刚刚编译的 Linux：

```bash
./qemu-5.0.0/build/aarch64-softmmu/qemu-system-aarch64 \
    -machine virt -cpu cortex-a53 -smp 1 -m 2G \
    -kernel ./linux-5.8.8/build/arch/arm64/boot/Image \
    -append "console=ttyAMA0" \
    -initrd ./busybox-1.32.0/build/initramfs.cpio.gz \
    -nographic
```

这里使用了 QEMU 的 [virt](https://www.qemu.org/docs/master/system/arm/virt.html) 平台。

## 参考资料

- [How to Build A Custom Linux Kernel For Qemu](https://mgalgs.github.io/2015/05/16/how-to-build-a-custom-linux-kernel-for-qemu-2015-edition.html)
- [Busybox构建根文件系统和制作Ramdisk](https://www.cnblogs.com/lotgu/p/7020418.html)
- [Building a minimal AArch64 root filesystem for network booting](http://wiki.loverpi.com/faq:sbc:libre-aml-s805x-minimal-rootfs)
- [Build and run minimal Linux / Busybox systems in Qemu](https://gist.github.com/chrisdone/02e165a0004be33734ac2334f215380e)
- [Download QEMU](https://www.qemu.org/download/#source)
