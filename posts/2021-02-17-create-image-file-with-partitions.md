---
title: 创建有多个分区的 img 文件并格式化
categories: Dev
tags: [文件系统, 分区, OS]
created: 2021-02-17 12:14:00
---

在 QEMU 中运行 OS 并需要模拟从 SD 卡读取文件时，可以通过 `-drive file=/path/to/sdcard.img,if=sd,format=raw` 参数向虚拟机提供 SD 卡，这里记录一下制作 `sdcard.img` 的过程。

首先需要创建一个空的映像文件，可以使用 `dd` 或 `fallocate`，这里以 `fallocate` 为例：

```bash
fallocate -l 200M sdcard.img
```

这里 `200M` 指的是这个映像文件占 200 MB，也就相当于是一个 200 MB 的 SD 卡。

然后使用 `fdisk` 对其进行分区，直接 `fdisk sdcard.img` 之后操作即可，比如这里分了两个分区：

```
Command (m for help): p
Disk sdcard.img: 200 MiB, 209715200 bytes, 409600 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0xb11e63d6

Device      Boot  Start    End Sectors  Size Id Type
sdcard.img1        2048 206847  204800  100M  c W95 FAT32 (LBA)
sdcard.img2      206848 409599  202752   99M 83 Linux
```

下一步就是要格式化成期望的文件系统，在这之前需要先把 `sdcard.img` 虚拟成一个块设备，通过如下命令做到：

```bash
losetup --partscan --show --find sdcard.img
```

成功后会输出一个设备路径，比如 `/dev/loop0`，与此同时还有两个分区 `/dev/loop0p1` 和 `/dev/loop0p2`。之后使用形如下面的命令格式化分区：

```bash
mkfs.fat -F32 /dev/loop0p1
```

然后移除 loop 设备：

```bash
losetup -d /dev/loop0
```

到这里 `sdcard.img` 就制作完成了。

## 参考资料

- https://unix.stackexchange.com/questions/209566/how-to-format-a-partition-inside-of-an-img-file
