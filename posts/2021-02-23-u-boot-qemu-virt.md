---
title: 在 QEMU 上使用 U-Boot 启动自制内核
categories: Dev
tags: [QEMU, U-Boot, OS, ARM, AArch64]
created: 2021-02-23 22:38:00
---

为了简单了解 U-Boot 的使用，花了些时间尝试在 QEMU 的 arm64 [virt](https://qemu.readthedocs.io/en/latest/system/arm/virt.html) 虚拟平台上使用 U-Boot 启动自制 OS 内核，这里记录一下过程，以便以后查阅。

## 准备 OS 内核

要想运行，肯定得先有个内核，于是搞了个极简的 helloworld：[qemu-virt-hello](https://github.com/richardchien/qemu-virt-hello)，能够启用 ARM timer，然后打印 tick。写这个 helloworld 的时候是直接用 QEMU 的 `-kernel` 参数传入 ELF 格式的内核来测试运行的，所以其实这次用 U-Boot 运行纯属学习目的，本身并没有简化什么。

上述内核编译完成后得到 ELF 格式的 `build/kernel.img` 和 objcopy 后的纯二进制的 `build/kernel.bin`。

然后需要使用 `mkimage` 命令（Ubuntu 上需安装 `u-boot-tools` 包）生成 U-Boot 能够识别的 image 文件：

```bash
mkimage -A arm64 -C none -T kernel -a 0x40000000 -e 0x40000000 -n qemu-virt-hello -d build/kernel.bin uImage
```

生成的 `uImage` 文件即所需的 image。

## 编译 U-Boot

使用下面命令下载和编译 U-Boot：

```bash
git clone git@github.com:u-boot/u-boot.git --depth 1
cd u-boot

make qemu_arm64_defconfig # 生成针对 QEMU virt 的 config
make -j16 CROSS_COMPILE=aarch64-linux-gnu- # 使用 CROSS_COMPILE 指定的工具链构建
```

完成之后 `u-boot` 目录下会生成一个 `u-boot.bin` 文件，这是 U-Boot 的可直接执行的纯二进制格式，使用下面命令检查是否可以正常进入 U-Boot：

```bash
qemu-system-aarch64 -machine virt -cpu cortex-a57 -bios u-boot.bin -nographic
```

进去之后会有个 autoboot 倒计时，按任意键之后会结束倒计时，到 U-Boot 命令行。

## 准备 Device Tree Blob

> 虽然按理说 U-Boot 可以不指定设备树直接启动不需要设备树的 kernel，但我这边一直不能成功，还没搞懂为什么，所以还是先准备一个设备树。

前面编写测试内核时针对的 QEMU 虚拟平台参数是 `-machine virt -cpu cortex-a57 -smp 1 -m 2G`，所以这里可以使用下面命令来 dump 出设备树：

```bash
qemu-system-aarch64 -machine virt,dumpdtb=virt.dtb -cpu cortex-a57 -smp 1 -m 2G -nographic
```

这会在当前文件夹生成 `virt.dtb` 文件。

## 构造 Flash Image

QEMU virt 平台有两个 flash 区域，分别是 0x0000_0000~0x0400_0000 和 0x0400_0000~0x0800_0000，U-Boot 本身被放在前一个 flash，我们可以通过 QEMU 参数 `-drive if=pflash,format=raw,index=1,file=/path/to/flash.img` 参数传入一个原始二进制格式的 image 文件来作为后一个 flash。

这里为了简单起见，使用 fallocate 和 cat 简单地把前面得到的 `uImage` 和 `virt.dtb` 拼在一起：

```bash
# 把 uImage 和 virt.dtb 分别扩展到 32M
fallocate -l 32M uImage
fallocate -l 32M virt.dtb

# 拼接
cat uImage virt.dtb > flash.img
```

## 运行

使用下面命令运行 QEMU 并进入 U-Boot 命令行：

```bash
qemu-system-aarch64 -nographic \
    -machine virt -cpu cortex-a57 -smp 1 -m 2G \
    -bios u-boot.bin \
    -drive if=pflash,format=raw,index=1,file=flash.img
```

使用 `flinfo` 命令可以查看 flash 信息。由于前面在制作 `flash.img` 时简单的拼接了 `uImage` 和 `virt.dtb`，因此现在 `uImage` 在 0x0400_0000 位置，`virt.dtb` 在 0x0600_0000 位置。

使用 `iminfo 0x04000000` 可以显示位于 0x0400_0000 的 `uImage` 信息，大致如下：

```
=> iminfo 0x04000000

## Checking Image at 04000000 ...
   Legacy image found
   Image Name:   qemu-virt-hello
   Created:      2021-02-22  15:54:06 UTC
   Image Type:   AArch64 Linux Kernel Image (uncompressed)
   Data Size:    12416 Bytes = 12.1 KiB
   Load Address: 40000000
   Entry Point:  40000000
   Verifying Checksum ... OK
```

使用 `fdt addr 0x06000000` 和 `fdt print /` 可以检查设备树是否正确，大致输出如下：

```
=> fdt addr 0x06000000
=> fdt print /
/ {
	interrupt-parent = <0x00008001>;
	#size-cells = <0x00000002>;
...
```

确认无误之后，使用 `bootm 0x04000000 - 0x06000000` 命令即可运行内核，如下：

```
=> bootm 0x04000000 - 0x06000000
## Booting kernel from Legacy Image at 04000000 ...
   Image Name:   qemu-virt-hello
   Created:      2021-02-22  15:54:06 UTC
   Image Type:   AArch64 Linux Kernel Image (uncompressed)
   Data Size:    12416 Bytes = 12.1 KiB
   Load Address: 40000000
   Entry Point:  40000000
   Verifying Checksum ... OK
## Flattened Device Tree blob at 06000000
   Booting using the fdt blob at 0x6000000
   Loading Kernel Image
   Loading Device Tree to 00000000bede5000, end 00000000bede9cdb ... OK

Starting kernel ...

Booting...
...
```

## 参考资料

- https://pandysong.github.io/blog/post/run_u-boot_in_qemu/
- https://u-boot.readthedocs.io/en/stable/board/emulation/qemu-arm.html
- https://github.com/qemu/qemu/blob/master/hw/arm/virt.c
- https://www.96boards.org/documentation/consumer/hikey/hikey620/guides/booting-linux-kernel-using-uboot.md.html
- https://linux.die.net/man/1/mkimage
- https://www.denx.de/wiki/view/DULG/LinuxInFlash
- https://simonthecoder.blogspot.com/2018/12/get-qemu-virt-machine-dts.html
