---
title: 使用 Tinc 组建虚拟局域网
categories: Ops
tags: [Tinc, VPN, 网络, 虚拟局域网]
created: 2021-05-04 22:56:00
---

以前曾经用过 [ZeroTier](https://www.zerotier.com/) 给自己多个分布在不同地方的设备组建大内网，后来用不着了，就没再折腾，前段时间又想重新组一下网，于是尝试了一下另一个同类的开源软件 [Tinc](https://www.tinc-vpn.org/)。本文记录一下使用 Tinc 搭建虚拟网的关键步骤。

## 安装

Ubuntu/Debian 上直接 `apt-get install tinc` 安装，其它系统可以网上搜索，基本默认包管理器都可以直接安装。

## 节点结构

首先想要网络中的节点要如何相连，以三个节点、其中一个有公网 IP 为例，如下图，`node2` 和 `node3` 需要主动连接到 `node1`，从而交换相关元信息，并在 `node1` 的辅助下建立连接。

![](/static/images/2021-05-04/tinc-nodes.png)

## 目录结构

在每个节点上创建如下目录结构：

```
/etc/tinc
└── mynet
    ├── hosts
    │   ├── .
    │   └── ..
    ├── .
    ├── ..
```

这里 `mynet` 是网络的名字，可以随意。`mynet` 目录里创建一个 `hosts` 子目录。

## 编写配置文件和启动脚本

在三个节点上分别编写配置文件和启动脚本。

### `node1`

`/etc/tinc/mynet/tinc.conf`：

```ini
Name = node1
Interface = tinc # ip link 或 ifconfig 中显示的接口名，下同
Mode = switch
Cipher = aes-256-cbc
Digest = sha512
```

`/etc/tinc/mynet/tinc-up`（需可执行，以使用 `ifconfig` 为例）：

```sh
#!/bin/sh
ifconfig $INTERFACE 172.30.0.1 netmask 255.255.255.0 # IP 根据需要设置，下同
```

`/etc/tinc/mynet/tinc-down`（需可执行，以使用 `ifconfig` 为例）：

```sh
#!/bin/sh
ifconfig $INTERFACE down
```

### `node2`

`/etc/tinc/mynet/tinc.conf`：

```ini
Name = node2
Interface = tinc
Mode = switch
ConnectTo = node1
Cipher = aes-256-cbc
Digest = sha512
```

`/etc/tinc/mynet/tinc-up`（需可执行，以使用 `iproute` 为例）：

```sh
#!/bin/sh
ip link set $INTERFACE up
ip addr add 172.30.0.2/24 dev $INTERFACE
ip route replace 172.30.0.0/24 via 172.30.0.1 dev $INTERFACE
```

`/etc/tinc/mynet/tinc-down`（需可执行，以使用 `ifconfig` 为例）：

```sh
#!/bin/sh
ip link set $INTERFACE down
```

### `node3`

基本和 `node2` 相同，除了 `Name = node3` 以及 IP 不同。

## 生成 RSA 密钥对

在每个节点上执行下面命令来生成节点的公私钥：

```sh
tincd -n mynet -K 4096
```

私钥默认保存在 `/etc/tinc/mynet/rsa_key.priv`，公钥在 `/etc/tinc/mynet/hosts/<node-name>`，这里 `<node-name>` 在每个节点上分别是 `node1`、`node2` 和 `node3`（Tinc 能够从 `tinc.conf` 中知道当前节点名）。

## 交换密钥

将 `node2` 和 `node3` 的 `/etc/tinc/mynet/hosts/node2` 和 `/etc/tinc/mynet/hosts/node3` 拷贝到 `node1` 上的 `/etc/tinc/mynet/hosts` 中，此时 `node1` 目录结构如下：

```
/etc/tinc
└── mynet
    ├── hosts
    │   ├── node1
    │   ├── node2
    │   └── node3
    ├── rsa_key.priv
    ├── tinc.conf
    ├── tinc-down
    └── tinc-up
```

将 `node1` 的 `/etc/tinc/mynet/hosts/node1` 拷贝到 `node2` 和 `node3`，并在该文件开头加上一行：

```ini
Address = 1.2.3.4 # node1 的公网 IP

-----BEGIN RSA PUBLIC KEY-----
...
-----END RSA PUBLIC KEY-----
```

此时 `node2` 的目录结构如下：

```
/etc/tinc
└── mynet
    ├── hosts
    │   ├── node1 # 包含 node1 的 Address
    │   ├── node2
    ├── rsa_key.priv
    ├── tinc.conf
    ├── tinc-down
    └── tinc-up
```

`node3` 和 `node2` 类似。

## 启动 Tinc

在每个节点上分别使用下面命令测试运行：

```sh
tincd -D -n mynet
```

该命令会在前台运行 Tinc，之后即可使用配置文件中配置的 IP 互相访问。

测试成功后可以杀掉刚刚运行的 `tincd` 进程，改用 `systemctl` 运行并开机自启动：

```sh
systemctl start tinc@mynet
systemctl enable tinc@mynet
```

## 参考资料

- [Example configuration (tinc manual)](https://www.tinc-vpn.org/documentation/Example-configuration.html)
- [TincVPN：组建虚拟局域网](https://lala.im/6209.html)
- [TINC - 构建 IPv6 隧道及私有网络](https://imlonghao.com/46.html)
