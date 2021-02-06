---
title: 用 Rust 写操作系统的踩坑记录
categories: Dev
tags: [Rust, OS, System]
created: 2021-01-31 13:50:00
updated: 2021-02-06 20:09:00
---

> 持续更新中……

最近在尝试用 Rust 写一个简单的 OS，过程中遇到了不少问题，在这里记录下，以便自己以后查阅，也给其他写 OS 的朋友们提供参考。

## 编译 `core` crate 发生 segmentation fault

使用自定义 target 的时候需要指定 `-Z build-std=core,alloc --target=targets/foo.json`，这会为指定的 target 编译 `core` 和 `alloc` crate，但是遇到如下报错：

```
$ make
    Updating crates.io index
   Compiling compiler_builtins v0.1.36 (/Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/src/rust/vendor/compiler_builtins)
   Compiling core v0.0.0 (/Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/src/rust/library/core)
   Compiling kernel v0.1.0 (/Users/richard/Projects/rcos/kernel)
   Compiling rustc-std-workspace-core v1.99.0 (/Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/src/rust/library/rustc-std-workspace-core)
error: could not compile `core`

Caused by:
  process didn't exit successfully: `rustc --crate-name core --edition=2018 /Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/lib.rs --error-format=json --json=diagnostic-rendered-ansi,artifacts --crate-type lib --emit=dep-info,metadata,link -C panic=abort -C embed-bitcode=no -C debuginfo=2 -C metadata=d1c28a1a3b0e7456 -C extra-filename=-d1c28a1a3b0e7456 --out-dir /Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps --target /Users/richard/Projects/rcos/kernel/targets/aarch64.json -Z force-unstable-if-unmarked -L dependency=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps -L dependency=/Users/richard/Projects/rcos/kernel/target/debug/deps --cap-lints allow` (signal: 11, SIGSEGV: invalid memory reference)
warning: build failed, waiting for other jobs to finish...
error: build failed
make: *** [target/aarch64/debug/kernel] Error 101
```

报错信息具体就是 `rustc` 在编译 `core` 的时候发生了 segmentation fault，直接运行报错的那句命令也是一样的效果，后来发现使用 release 编译就不会报错，于是发现问题跟 `-C opt-level=` 编译选项有关，`opt-level` 等于 0 就会报错，大于等于 1 就没问题，可能是 `rustc` 的 bug。具体解决方法是在 `Cargo.toml` 中针对 `core` 包修改 `opt-level`，如下：

```toml
[profile.dev.package.core]
opt-level = 1
```

## 内核链接错误，报 `undefined symbol: memcpy`

报错信息如下：

```
$ make
...
error: linking with `rust-lld` failed: exit code: 1
  |
  = note: "rust-lld" "-flavor" "gnu" "-Ttarget/aarch64/linker.ld" "--eh-frame-hdr" "-L" "/Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/aarch64/lib" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/kernel-ff049f1d4f391e89.1fogdgfwiaz79eo9.rcgu.o" ... "-o" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/kernel-ff049f1d4f391e89" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/kernel-ff049f1d4f391e89.27nsv6g895dy2t94.rcgu.o" "--gc-sections" "-O1" "-L" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps" "-L" "/Users/richard/Projects/rcos/kernel/target/debug/deps" "-L" "/Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/aarch64/lib" "-Bstatic" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libbuddy_system_allocator-6c2e94bd40abd09c.rlib" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libspin-452aa8ee04b5ffb7.rlib" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libspin-453077918cb4bcee.rlib" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/liballoc-359e1687c65b650d.rlib" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/librustc_std_workspace_core-9cbf353238b20cd5.rlib" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libcore-81456d7491ea4ea4.rlib" "/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libcompiler_builtins-482ad68e57d9fb9c.rlib" "-Bdynamic"
  = note: rust-lld: error: undefined symbol: memcpy
          >>> referenced by mod.rs:182 (/Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/fmt/mod.rs:182)
          >>>               /Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/kernel-ff049f1d4f391e89.2ec5pxgnruw0e9q7.rcgu.o:(_$LT$$RF$mut$u20$W$u20$as$u20$core..fmt..Write$GT$::write_fmt::h14b1afbd1a65c84b (.llvm.3212942262376902672))
          >>> referenced by mod.rs:447 (/Users/richard/.rustup/toolchains/nightly-2020-11-25-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/fmt/mod.rs:447)
          >>>               core-81456d7491ea4ea4.core.2iv2qs8o-cgu.9.rcgu.o:(_$LT$core..fmt..Arguments$u20$as$u20$core..fmt..Display$GT$::fmt::haadaeb7738e71625) in archive /Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libcore-81456d7491ea4ea4.rlib
          

error: aborting due to previous error; 35 warnings emitted

error: could not compile `kernel`

Caused by:
  process didn't exit successfully: `rustc --crate-name kernel --edition=2018 src/main.rs --error-format=json --json=diagnostic-rendered-ansi --crate-type bin --emit=dep-info,link -C opt-level=2 -C embed-bitcode=no -C debuginfo=2 -C debug-assertions=on -C metadata=ff049f1d4f391e89 -C extra-filename=-ff049f1d4f391e89 --out-dir /Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps --target /Users/richard/Projects/rcos/kernel/targets/aarch64.json -C incremental=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/incremental -L dependency=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps -L dependency=/Users/richard/Projects/rcos/kernel/target/debug/deps --extern 'noprelude:alloc=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/liballoc-359e1687c65b650d.rlib' --extern buddy_system_allocator=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libbuddy_system_allocator-6c2e94bd40abd09c.rlib --extern 'noprelude:compiler_builtins=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libcompiler_builtins-482ad68e57d9fb9c.rlib' --extern 'noprelude:core=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libcore-81456d7491ea4ea4.rlib' --extern spin=/Users/richard/Projects/rcos/kernel/target/aarch64/debug/deps/libspin-453077918cb4bcee.rlib -Z unstable-options --cfg 'arch="aarch64"' --cfg 'machine="virt"'` (exit code: 1)
make: *** [target/aarch64/debug/kernel] Error 101
```

意思是 `core::fmt` 包里面引用了 `memcpy`，然而 `no_std` 的情况下没有 `memcpy` 这符号。

后来在 [Writing an OS in Rust (First Edition)](https://os.phil-opp.com/set-up-rust/#fixing-linker-errors) 找到解决方案，方法就是链接一个 [`rlibc`](https://crates.io/crates/rlibc)，这提供了 `memcpy`、`memmove` 等函数的实现。

但事情并没有这么简单，虽然上面的方案可以用，但 rlibc 已经是弃用状态了，作者推荐使用 [`compiler_builtin`](https://github.com/rust-lang/compiler-builtins) 替代，这个 crate 的 README 里让添加 dependency，但其实这玩意在使用 `-Z build-std=core,alloc` 编译的情况下会自动编译，不需要手动添加 dependency，但是自动编译的情况下不会加上 `mem` feature，而我们正是要它的 `mem` feature 才能解决链接问题，找了一圈发现这个问题已经在几个 issue 里讨论过了，最后有一个 PR 解决了这问题，现在只需要再加上 `-Z build-std-features=compiler-builtins-mem` 参数就可以把 `mem` feature 传给 `compiler_builtins` crate。

相关链接：

- https://os.phil-opp.com/set-up-rust/#fixing-linker-errors
- https://github.com/alexcrichton/rlibc
- https://github.com/rust-lang/compiler-builtins
- https://github.com/rust-lang/compiler-builtins/issues/334
- https://github.com/rust-lang/wg-cargo-std-aware/issues/53 这是关键，可能有后续更新
- https://github.com/rust-lang/rust/pull/77284

## 在 `build.rs` 中自动选择 linker script

由于不同 arch 和 machine 可能需要不同的 linker script，因此 `linker.ld` 可能放在 `src/arch/<arch>/` 也可能在 `src/arch/<arch>/machine/<machine>/`，于是想在 `build.rs` 中根据传入的环境变量来自动选择对应的 `linker.ld`。

但 cargo 只支持在 `build.rs` 中输出 `rustc-cdylib-link-arg`，是针对编译动态库的，于是一开始选择在自定义 target 的 JSON 或在 `.cargo/config.toml` 中写死 linker script 路径为 `target` 目录中的某个地方，然后在 `build.rs` 中把对应的 `linker.ld` 拷到那个地方。

后来翻了半天 issue 找到了同类问题，然后发现有一个 PR 已经提供了 unstable 支持，允许在 `build.rs` 中生成 `rustc-link-arg`（虽然 PR 中修改了 `unstable.md` 文档，但奇怪的是 master 分支文档却没有），可以用在任何目标类型，于是这件事情就简化成了在 `build.rs` 中找到需要的 `linker.ld`，然后输出 `cargo:rustc-link-arg=-T<linker_ld_path>`，完美解决问题。

相关链接：

- https://github.com/rust-lang/cargo/issues/7984
- https://github.com/rust-lang/cargo/pull/7811
- https://github.com/rust-lang/cargo/pull/8441 最终合并的 PR

## 生成位置无关代码

在还没有启动 MMU 的时候，PC 寄存器首先会是物理地址，但内核最终需要使用 `0xffff` 开头的高地址，通常在 linker script 中可进行配置，使代码中使用的绝对寻址拿到的都是高地址，然后启用编译器的相关选项使生成的代码在访问静态变量、调用函数时都采用位置无关的方式。这样就可以在内核的 boot 阶段首先使用低地址，同时该阶段的代码可以随意访问内核其它部分的函数或静态变量，然后在配置好页表、启用 MMU 之后，使用绝对寻址跳转到高地址。

要让 Rust 生成位置无关代码，在自定义 target 中添加 `"position-independent-executables": true` 即可。

相关链接：

- https://github.com/rcore-os/rCore/blob/9c2459/kernel/targets/aarch64.json

## 增量编译导致运行时难以追踪的 bug

写到页表映射的时候，发生了很奇怪的问题，明明上一秒分配了物理页，然后把地址写到了上级页表项里，过了几行之后上级页表又空了，一开始以为是我的代码或是第三方库有问题，de 了两天 bug，GDB 调了好久，过程中 bug 还会变，居然分配物理页的函数会两次分配相同的物理页，可明明这个已经测试过了。

最后终于发现是 rustc 增量编译的问题，可能生成的代码有些细节已经语义不对了，`cargo clean` 之后全量重新编译就没问题了。所以如果遇到奇怪的 bug，别忘了先试试 clean。
