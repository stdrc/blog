---
title: PIC、PIE 和 Copy Relocation
categories: Dev
tags: [编译器, 链接器, 加载器, GCC, Clang, PIC, PIE, Relocation]
created: 2021-12-30 14:34:00
---

这两天尝试修改 musl libc，碰到了个很怪的问题，最终找到了原因并解决，记录如下。

> 文章中部分表述不完全准确，请看 MaskRay 在评论区的补充～

## 奇怪的全局变量

起因是想在 libc 里添加一个全局变量 `syscall_count` 用来记录发生的 syscall 数量（这个需求本身很怪，因为只是在测试优雅地拦截 libc syscall 的方案）。具体地，添加了一个 C 文件如下：

```c
// musl/src/syscall_count.c

int syscall_count;

int get_syscall_count()
{
    return syscall_count;
}
```

然后修改 `arch/x86_64/syscall_arch.h` 如下：

```c
// musl/arch/x86_64/syscall_arch.h

// ...

extern int syscall_count;

static __inline long __syscall0(long n)
{
    syscall_count++;
    // ...
}

// ...
```

编译 libc 得到 `libc.so` 后，编写测试程序如下：

```c
// test/main.c

#include <stdio.h>

extern int syscall_count;
extern int get_syscall_count();

int main(int argc, const char *argv[])
{
    printf("Hello World!\n");
    printf("main, syscall_count: %d\n", syscall_count);
    printf("main, get_syscall_count(): %d\n", get_syscall_count());
    return 0;
}
```

测试程序使用动态链接的方式编译链接（CMake 设置 `CMAKE_C_COMPILER` 为 musl libc 的 GCC wrapper `musl-gcc` 后的默认情况），输出的可执行文件类型为 dynamically linked shared object。

运行发现输出很不对劲：`syscall_count` 值为 5，而 `get_syscall_count()` 返回 9，中间只隔了一个 `printf` 居然多了 4 个 syscall。

察觉到奇怪后，加了些打印来 debug：

```c
// musl/src/syscall_count.c

// ...

#include <stdio.h>

int get_syscall_count()
{
    printf("get_syscall_count, &syscall_count: %p, syscall_count: %d\n", &syscall_count, syscall_count);
    return syscall_count;
}
```

```c
// test/main.c

// ...

int main(int argc, char const *argv[])
{
    printf("Hello World!\n");
    printf("main, &syscall_count: %p, syscall_count %d\n", &syscall_count, syscall_count);
    printf("main, get_syscall_count(): %d\n", get_syscall_count());
    printf("main, &syscall_count: %p, syscall_count %d\n", &syscall_count, syscall_count);
    return 0;
}
```

再同样方式构建运行输出如下：

```
Hello World!
main, &syscall_count: 0x562c67343008, syscall_count 5
get_syscall_count, &syscall_count: 0x7fdf59090fd4, syscall_count: 9
main, get_syscall_count(): 10
main, &syscall_count: 0x562c67343008, syscall_count 5
```

发现 `test/main.c` 和 `libc.so` 中访问的 `syscall_count` 甚至地址都不一样。于是进行了一些尝试，给 test 程序添加了 `-fPIC` 编译选项，行为就符合预期了，改成加 `-fPIE`，行为又不正常（后来才发现我安装的 GCC 9 打开了 `--enable-default-pie`，也就是说 PIE 就是默认行为）。

虽然加上 `-fPIC` 后“解决了”问题（实际上并不是最正确的解法，后面说），但还是不甘心，因为最近被 PIC 相关问题折腾的够呛，想认真了解一下其中的细节，于是进行了一番搜索，找到了跟我相似的问题[^same-question]，接着顺着问题下的回答和之前阅读 [MaskRay](https://maskray.me)（一位 LLVM 贡献者）的博客的印象，慢慢终于弄懂了问题产生的本质原因。

[^same-question]: https://stackoverflow.com/questions/39394971/can-i-declare-a-global-variable-in-a-shared-library

## PIC 和 PIE

首先需要理解 PIC（Position Independent Code）和 PIE（Position Independent Executable）是怎么回事，这里只讨论 x86-64 架构的情形。

当不开 PIC 或 PIE 时，编译器假设目标程序最终会被加载到一个固定的虚拟地址，于是在生成访问全局变量和函数调用的指令时，如果无法使用 PC 相对寻址，则可以直接使用绝对地址寻址；而开了 PIC 或 PIE 后，编译器不知道目标程序运行时会加载到什么地址，因此需要使用 GOT（Global Offset Table）来间接寻址，等加载器加载 ELF 时，才在 GOT 表项中填充运行时的绝对地址。[^csapp3e-chap7]

[^csapp3e-chap7]: Computer Systems: A Programmer's Perspective, 3/E (CS:APP3e), Chapter 7 Linking

而 PIC 和 PIE 的区别则在于编译出来的目标文件的用途：PIC 模式编译出的目标文件可以被用于生成位置无关可执行文件或动态库，PIE 模式编译出的目标文件只能用于生成位置无关可执行文件，不能用于生成动态库（因此编译器有了一些优化空间）。当然，这里讨论的都是“位置无关”，位置相关的可执行文件可以从任何模式（PIC、PIE、no-PIC）编译的目标文件生成。[^pic-pie]

[^pic-pie]: https://mropert.github.io/2018/02/02/pic_pie_sanitizers/

## Copy Relocation

接着就是我一开始遇到的问题的直接原因（根本原因在后面），也就是 copy relocation[^maskray-copyreloc]。

[^maskray-copyreloc]: http://maskray.me/blog/2021-01-09-x86-copy-relocations-protected-symbols

当使用 PIC 时，编译器为 `syscall_count` 变量使用了 GOT 间接寻址：

```x86asm
printf("main, &syscall_count: %p, syscall_count %d\n", &syscall_count, syscall_count);
1198:	48 8b 05 59 2e 00 00 	mov    0x2e59(%rip),%rax        # 3ff8 <syscall_count>
119f:	8b 00                	mov    (%rax),%eax
```

因此在加载 `libc.so` 时给 GOT 表项填入了 `syscall_count` 的绝对地址，行为符合预期。

而使用 PIE 时，编译器为 `syscall_count` 使用了 PC 相对寻址：

```x86asm
printf("main, &syscall_count: %p, syscall_count %d\n", &syscall_count, syscall_count);
1198:	8b 05 6a 2e 00 00    	mov    0x2e6a(%rip),%eax        # 4008 <syscall_count>
```

可是它并不知道 `syscall_count` 所在的 `libc.so` 会被加载到哪，怎么能 PC 相对寻址呢？答案就是编译器在测试程序 `test` 中为 `syscall_count` 进行了 copy relocation，创建了一份拷贝，通过 `nm test/build/test` 可以看出区别：

- PIC 模式：

```
                 ...
                 U get_syscall_count
                 U syscall_count
```

- PIE 模式：

```
                 ...
                 U get_syscall_count
0000000000004008 B syscall_count
```

可以看出 `syscall_count` 在 PIC 模式下标记为未定义符号（`U`），等待加载 `libc.so` 时进行 relocation，而 PIE 模式下直接被定义在了 BSS 段（`B`）。与此同时，`get_syscall_count` 在两种情况下都是未定义符号，也就是说会在运行时 relocate 到 `libc.so` 中的那一份，所以测试程序中直接访问 `syscall_count` 和调用 `get_syscall_count` 得到的结果不一致（这个解释在逻辑上还是有漏洞的，看下一节）。

通过 `readelf -r test/build/test` 可以更明确地看出 PIC 和 PIE 模式下编译器产生了不同的 relocation 行为[^crawshaw-copyreloc]，进而印证上面的论断：

[^crawshaw-copyreloc]: https://crawshaw.io/blog/2016-04-17

- PIC 模式：

```
Relocation section '.rela.dyn' at offset 0x4a0 contains 8 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
                                ......
000000003ff8  000800000006 R_X86_64_GLOB_DAT 0000000000000000 syscall_count + 0

Relocation section '.rela.plt' at offset 0x560 contains 4 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
                                ......
000000003fc0  000200000007 R_X86_64_JUMP_SLO 0000000000000000 get_syscall_count + 0
```

- PIE 模式：

```
Relocation section '.rela.dyn' at offset 0x4a8 contains 8 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
                                ......
000000004008  000a00000005 R_X86_64_COPY     0000000000004008 syscall_count + 0

Relocation section '.rela.plt' at offset 0x568 contains 4 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
                                ......
000000003fc8  000200000007 R_X86_64_JUMP_SLO 0000000000000000 get_syscall_count + 0
```

## Dynamic Symbol

接着需要深究的是，既然 `syscall_count` 可能会被 copy relocation，那 `libc.so` 中的 `get_syscall_count` 访问 `syscall_count` 时不应该使用 GOT 间接寻址吗，这样才能保证一致性啊。然而查看 `libc.so` 的反汇编发现它用了 PC 相对寻址：

```x86asm
syscall_count++;
162ce:	48 8d 05 ff 3c 08 00    lea    0x83cff(%rip),%rax     # 99fd4 <syscall_count>
162d5:	ff 00                   incl   (%rax)
```

也就是说 `libc.so` 的 `get_syscall_count` 用了自己 ELF 里定义的那份 `syscall_count`，这才最终导致测试程序访问 `syscall_count` 和 `get_syscall_count` 的结果不一致。

那 `libc.so` 凭什么放心地对 `syscall_count` 进行 PC 相对寻址呢，这是因为 musl libc 在链接时通过 `--dynamic-list=./dynamic.list` 参数指定了 dynamic list（dynamic symbol table），意思是说，在这个表里面的符号，libc 会认为有可能在应用程序（可执行文件）中被重复定义，届时 libc 需要使用应用程序给出的定义。这个表里面包含了 `malloc` 等常见的允许被替换的函数和变量。[^maskray-libc-symbol-renaming]

[^maskray-libc-symbol-renaming]: https://maskray.me/blog/2020-10-15-intra-call-and-libc-symbol-renaming

如果不指定 dynamic list，则默认情况下链接器会认为所有符号都可能在应用程序中重复定义，会导致 libc 的性能开销显著增加（所有全局变量和函数访问都要经过 GOT），所以 musl libc 使用了 dynamic list。

因此，没有把 `syscall_count` 放到 `dynamic.list` 是我遇到上面问题的根本原因，一旦把它加进去，无论应用程序使用 PIC 还是 PIE 都能正确工作。

## `R_X86_64_REX_GOTPCRELX`

在和 MaskRay 对 dynamic list 进行交流后，他提到 `R_X86_64_REX_GOTPCRELX` 这种 relocation 模式，学习后我明白了 `libc.so` 对 `syscall_count` 采用 PC 相对寻址的具体过程。

首先编译器把 `.c` 编译为目标文件时，为 `syscall_count` 产生了 `R_X86_64_REX_GOTPCRELX` relocation 模式，从汇编上可以看到此时指令还是像 GOT 间接寻址，需要两次访存：

```x86asm
syscall_count++;
119:	4c 8b 05 00 00 00 00    mov    0x0(%rip),%r8        # 120 <__init_libc+0x120>
12f:	41 ff 00                incl   (%r8)
```

接着在链接时，链接器发现 `syscall_count` 不在 dynamic list 中，于是对上面的指令进行优化[^maskray-gotpcrelx]，最终在 `libc.so` 中产生如下指令，采用 PC 相对寻址：

```x86asm
syscall_count++;
16187:	4c 8d 05 46 3e 08 00    lea    0x83e46(%rip),%r8    # 99fd4 <syscall_count>
16191:	41 ff 00                incl   (%r8)
```

[^maskray-gotpcrelx]: https://maskray.me/blog/2021-08-29-all-about-global-offset-table#got-indirection-to-pc-relative

## 为什么 PIE 的行为和 PIC 不同？

说了这么多，仍然没有解释为什么 PIC 和 PIE 行为不同。我的理解是这样的，PIC 编译出的目标文件可能用于动态库，所以它不能对外部定义的全局变量有自己的拷贝，而是只能通过 GOT 表访问，而 PIE 则确定是用于可执行文件，所以即使它有自己的拷贝，只要所有动态库都通过 GOT 表访问，就能保证全局只有一个该变量。这就是前面说的，PIE 模式给了编译器一定的优化空间。

另外，PIE 模式下使用 copy relocation 也不是从一开始就有的行为，而是在 GCC 5 引入的，为的是减少使用 GOT 导致的额外内存访问开销[^gcc-pie-copyreloc]。Clang 也在某个版本中引入了编译选项 `-mpie-copy-relocationss` 来开启 copy relocation[^clang-d19995][^clang-d19996]，后来 MaskRay 将其改成了 `-f[no-]direct-access-external-data`[^clang-d92633]，但后者在 GCC 的提议[^gcc-direct-access-external-data] 没有被接受。

[^gcc-pie-copyreloc]: https://gcc.gnu.org/git/?p=gcc.git&a=commit;h=77ad54d911dd7cb88caf697ac213929f6132fdcf
[^clang-d19995]: https://reviews.llvm.org/D19995
[^clang-d19996]: https://reviews.llvm.org/D19996
[^clang-d92633]: https://reviews.llvm.org/D92633
[^gcc-direct-access-external-data]: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=98112

## 和 CMake 碰撞出的火花

在 CMake 中，当设置 `CMAKE_POSITION_INDEPENDENT_CODE` 为 `ON` 之后，它对于动态库会添加 `-fPIC` 选项，而对可执行文件会添加 `-fPIE` 选项。当 CMake 觉得自己充分利用了编译器优化时，实际上更悄无声息地触发了 copy relocation。

## 仍然迷惑的点

虽然上面已经大致搞明白了整个问题的原因，但我还是有一个疑惑的点，那就是 `--dynamic-list` 的语义到底是什么，网上看到的说法基本都是：在 dynamic list 中指定的符号，动态库链接时会认为潜在地可能在运行时由外部定义，于是不会绑定到动态库内的定义。但这个语义并没有说清楚，可执行文件通过 `extern` 声明（并没有显式地重新定义）并使用动态库中的全局变量会发生什么，而 copy relocation 正是利用了这个语义上的模糊地带，在 PIE 模式下隐式地在可执行文件中重新定义了动态库全局变量。

我个人认为 PIE 下默认进行 copy relocation 的行为是有问题的，当试图访问的变量不在 dynamic list 时应该报一个警告，或者维持原来的使用 GOT 的行为。而且，事实上在给测试程序添加 `-fno-PIC` 选项时，无论 `syscall_count` 在不在 `libc.so` 的 dynamic list 上，编译器都会为 `syscall_count` 产生 `R_X86_64_PC32` relocation，进而在链接时报错，而不会进行 copy relocation，这才是符合逻辑的行为。
