---
title: ARM GIC 虚拟化学习笔记
categories: Note
tags: [ARM, GIC, 虚拟化, Linux, KVM, OS]
created: 2020-09-26 20:28:00
---

> 这是一篇学习过程中的笔记，因为时间原因不再组织成流畅的语言，而是直接分享了～

## References

- Linux 4.2.1（最新的 5.8 相比 4.2 更抽象，不便于理解逻辑）
    - `arch/arm64/kvm/`
    - `virt/kvm/arm/`
- https://mp.weixin.qq.com/s/GI4nV7URCU5Oem6hmVee2Q
- https://www.linux-kvm.org/images/7/79/03x09-Aspen-Andre_Przywara-ARM_Interrupt_Virtualization.pdf
- ARM GIC Architecture Specification, v2 & v3

## GICv2

### Non-virtualization

![](/static/images/2020-09-26/gicv2.png)

- 中断进入 distributor，然后分发到 CPU interface
- 某个 CPU 触发中断后，读 GICC_IAR 拿到中断信息，处理完后写 GICC_EOIR 和 GICC_DIR（如果 GICC_CTLR.EOImodeNS 是 0，则 EOI 的同时也会 DI）
- GICD、GICC 寄存器都是 MMIO 的，device tree 中会给出物理地址

### Virtualization

![](/static/images/2020-09-26/gicv2-virt.png)

- HCR_EL2.IMO 设置为 1 后，所有 IRQ 都会 trap 到 HYP
- HYP 判断该 IRQ 是否需要插入到 vCPU
- 插入 vIRQ 之后，在切换到 VM 之前需要 EOI 物理 IRQ，即 priority drop，降低运行优先级，使之后 VM 运行时能够再次触发该中断
- 回到 VM 后，GIC 在 EL1 触发 vIRQ，这时候 EOI 和 DI 会把 vIRQ 和物理 IRQ 都 deactivate，因此不需要再 trap 到 HYP，不过如果是 SGI 的话并不会 deactivate，需要 HYP 自己处理（通过 maintenance 中断？）

### HYP interface (GICH)

- GICH base 物理地址在 device tree 中给出
- 控制寄存器：GICH_HCR、GICH_VMCR 等
- List 寄存器：GICH_LRn
- KVM 中，这些寄存器保存在 `struct vgic_cpu` 的 `vgic_v2` 字段，`struct vgic_cpu` 本身放在 `struct kvm_vcpu_arch`，每个 vCPU 一份
- vCPU switch 的时候，需要切换这些寄存器（KVM 在 `vgic-v2-switch.S` 中定义相关切换函数）
- VM 无法访问 GICH 寄存器，因为根本没有映射

### List register (LR)

![](/static/images/2020-09-26/lr.png)

### vCPU interface (GICV, GICC in VM's view)

- GICV 也是物理 GIC 上存在的，base 物理地址同样在 device tree 中给出
- KVM 在系统全局的一个结构体（`struct vgic_params vgic_v2_params`）保存了这个物理地址
- 创建 VM 时 HYP 把一个特定的 GPA（KVM 中通过 `ioctl` 设置该地址）映射到 GICV base 物理地址，然后把这个 GPA 作为 GICC base 在 device tree 中传给 VM
- VM 以为自己在访问 GICC，实际上它在访问 GICV
- 目前理解这些 GICV 寄存器在 vCPU switch 的时候是不需要保存的（KVM 里没有保存 GICV 相关的代码），因为它其实在硬件里访问的是 GICH 配置的那些寄存器，比如 LR

### Virtual distributor (GICD in VM's view)

- 实际是内核里的一个结构体（`struct vgic_dist`）
- 在 device tree 中给 VM 一个 GICD base，但实际上没有映射
- VM 访问 GICD 时，trap & emulate，直接返回或设置 `struct vgic_dist` 里的字段（在 `vgic-v2-emul.c` 文件中）
- 每个 VM 一个，而不是每个 vCPU 一个，所以 `struct vgic_dist` 放在 `struct kvm_arch` 里

### VM's view

![](/static/images/2020-09-26/gicv2-vm-view.png)

- 从 device tree 获得 GICD、GICC base 物理地址（实际是 HYP 伪造的地址）
- 配置 GICD 寄存器（实际上 trap 到 HYP，模拟地读写了内核某 struct 里的数据）
- 执行直到发生中断（中断先到 HYP，HYP 在 LR 中配置了一个物理 IRQ 到 vIRQ 的映射，并且设置为 pending，回到 VM 之后 GIC 在 VM 的 EL1 触发中断）
- 读 GICC_IAR（经过 stage 2 页表翻译，实际上读了 GICV_IAR，GIC 根据 LR 返回 vIRQ 的信息，vIRQ 状态从 pending 转为 active）
- 写 GICC_EOIR、GICC_DIR（经过 stage 2 页表翻译，实际上写了 GICV_EOIR、GICV_DIR，GIC EOI 并 deactivate 对应的 vIRQ，并 deactivate vIRQ 对应的物理 IRQ）

## GICv3

新特性：

- CPU interface（GICC、GICH、GICV）通过 system register 访问（`ICC_*_ELn`、`ICH_*_EL2`、`ICV_*_ELn`，ICC 和 ICV 在指令中的编码相同，硬件根据当前 EL 和 HCR_EL2 来路由），不再用 MMIO
- 使用 affinity routing，支持最多 2^32 个 CPU 核心
- 引入 redistributor，每个 CPU 一个，和各 CPU interface 连接，使 PPI 不再需要进入 distributor
- 引入一种新的中断类型 LPI 和一个新的组件 ITS（还没太看懂是干啥用的）

### Non-virtualization

![](/static/images/2020-09-26/gicv3.png)

### Virtualization

![](/static/images/2020-09-26/gicv3-cpu-interface.png)

![](/static/images/2020-09-26/gicv3-virt-example.png)
