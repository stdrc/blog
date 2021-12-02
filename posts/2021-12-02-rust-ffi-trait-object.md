---
title: Rust FFI 调用时传递 trait object 作为参数的问题
categories: Dev
tags: [Rust, FFI, C, C++, Trait Object, 虚函数表]
created: 2021-12-02 20:38:00
---

最近实验室一个同学在使用 Rust 和 C 互调用时，发现当把 trait object 指针传入一个接受 `void *` 的 C 函数后，C 再次使用这个指针作为参数调用 Rust 的函数，会发生 segmentation fault，交流和搜索之后找到了原因和解决方案，记录如下。

## Foreign Language Interface（FFI）

众所周知，Rust 和 C 可以相互调用对方导出的函数，调用接口称为 FFI。

举一个极简的例子，来演示 Rust 和 C 的互调用：

```c
// src/boring.c

#include <stdio.h>

extern void call_rust_with_foo(void *foo);

void call_c_with_foo(void *foo) {
    printf("Hello from C!\n");
    call_rust_with_foo(foo);
}
```

```rust
// src/main.rs

use std::os::raw::c_void;

pub struct Foo {}

impl Foo {
    fn foo(&self) {
        println!("foo!");
    }
}

#[link(name = "boring", kind = "static")]
extern "C" {
    fn call_c_with_foo(foo: *const c_void);
}

#[no_mangle]
pub extern "C" fn call_rust_with_foo(foo: *const Foo) {
    println!("Hello from Rust!");
    let foo = unsafe { &*(foo) };
    foo.foo();
}

fn main() {
    let foo_impl = Foo {};
    let foo = &foo_impl;
    unsafe {
        call_c_with_foo(foo as *const Foo as *const c_void);
    }
}
```

```rust
// build.rs

use cc;

fn main() {
    cc::Build::new().file("src/boring.c").compile("libboring.a");
}
```

编译运行会输出：

```
Hello from C!
Hello from Rust!
foo!
```

## 出错场景

在上面的例子中，如果因为一些需求，要把 `Foo` 改成 trait，`struct FooImpl` 实现 `trait Foo`，此时试图在 FFI 函数参数中传递 `*const dyn Foo`，就会出现 segmentation fault。

修改后 `src/main.rs` 文件如下：

```rust
// src/main.rs

use std::os::raw::c_void;

pub trait Foo {
    fn foo(&self);
}

pub struct FooImpl {}

impl Foo for FooImpl {
    fn foo(&self) {
        println!("foo!");
    }
}

#[link(name = "boring", kind = "static")]
extern "C" {
    fn call_c_with_foo(foo: *const c_void);
}

#[no_mangle]
pub extern "C" fn call_rust_with_foo(foo: *const dyn Foo) {
    println!("Hello from Rust!");
    let foo = unsafe { &*(foo) };
    foo.foo();
}

fn main() {
    let foo_impl = FooImpl {};
    let foo = &foo_impl as &dyn Foo;
    unsafe {
        call_c_with_foo(foo as *const dyn Foo as *const c_void);
    }
}
```

运行输出：

```
Hello from C!
Hello from Rust!
[1]    68850 segmentation fault  ./target/debug/trait-object-ffi
```

## 胖指针和瘦指针

经过一些搜索后明白出错的原因与胖瘦指针有关。Rust 中的 trait object 是胖指针（fat pointer），在 64 位机器上，占据 16 字节，是瘦指针（thin pointer）的两倍，实际也就是由两个瘦指针构成。

通过 [`std::mem::size_of`](https://doc.rust-lang.org/std/mem/fn.size_of.html) 可以验证这一点：

```rust
fn main() {
    println!("{}", std::mem::size_of::<&FooImpl>()); // 输出 8
    println!("{}", std::mem::size_of::<&dyn Foo>()); // 输出 16
}
```

为什么会有这个区别呢，是因为当把 `&foo_impl` 转成 trait object 时，它丢失了原来的具体类型信息，这时候要调用 `FooImpl::foo` 函数，需要走虚函数表查询函数地址，这个过程叫做 [动态分派](https://zh.wikipedia.org/wiki/%E5%8A%A8%E6%80%81%E5%88%86%E6%B4%BE)（dynamic dispatch）。因此，`&dyn Foo` 的第一个 8 字节指向 `FooImpl` 对象，第二个 8 字节指向 `FooImpl` 的虚函数表。

有趣的是，C++ 中实现 dynamic dispatch 时，是把虚函数表指针放在对象的开头（[这篇文章](2021-03-06-dont-create-thread-in-cpp-base-class-constructor.md) 中有过相关讨论），所以 C++ 中不需要胖指针，代价是调用虚函数时需要多一次 dereference。

回到问题，由于 `&dyn Foo` 乃至 `*const dyn Foo` 是胖指针，那么转成 `*const c_void` 传给 `call_c_with_foo` 的时候就已经丢失了第二个 8 字节的虚函数表指针，由 C 代码再传回 `call_rust_with_foo`，虚函数表指针就是一个野指针了。

## 解决方案 1：两层指针

要解决问题，最简单的方案是把胖指针放在一个变量（或者 `Box`）里，再取这个变量的地址传给 C，也就是通过两层指针来传递。

这种方案不需要修改上面的 C 代码，只需修改 `src/main.rs`：

```rust
// src/main.rs
// ...

#[no_mangle]
pub extern "C" fn call_rust_with_foo(foo: *const *const dyn Foo) {
    println!("Hello from Rust!");
    let foo = unsafe { &**(foo) };
    foo.foo();
}

fn main() {
    let foo_impl = FooImpl {};
    let foo = &foo_impl as &dyn Foo;
    let foo_raw = foo as *const dyn Foo;
    unsafe {
        call_c_with_foo(&foo_raw as *const *const dyn Foo as *const c_void);
    }
}
```

## 解决方案 2：通过 struct 传胖指针

另一种解决方案是直接把胖指针转成某个 struct，然后按 struct 传给 C。

### 第一种写法

Rust 标准库中曾经有过一个 unstable 的 struct 叫 [`std::raw::TraitObject`](http://web.mit.edu/rust-lang_v1.25/arch/amd64_ubuntu1404/share/doc/rust/html/std/raw/struct.TraitObject.html) 可以用来实现这个解法，虽然它已经被 deprecated 了（[rust-lang/rust#84207](https://github.com/rust-lang/rust/pull/84207)、[rust-lang/rust#86833](https://github.com/rust-lang/rust/pull/86833)），我们仍然可以手动定义，类似下面这样：

```rust
#[repr(C)]
pub struct TraitObject {
    data: *const c_void,
    vtable: *const c_void,
}
```

于是对代码修改如下：

```c
// src/boring.c

#include <stdio.h>

struct TraitObject {
    void *data;
    void *vtable;
};

extern void call_rust_with_foo(struct TraitObject foo);

void call_c_with_foo(struct TraitObject foo) {
    printf("Hello from C!\n");
    call_rust_with_foo(foo);
}
```

```rust
// src/main.rs
// ...

#[repr(C)]
pub struct TraitObject {
    data: *const c_void,
    vtable: *const c_void,
}

#[link(name = "boring", kind = "static")]
extern "C" {
    fn call_c_with_foo(foo: TraitObject);
}

#[no_mangle]
pub extern "C" fn call_rust_with_foo(foo: TraitObject) {
    println!("Hello from Rust!");
    let foo: &dyn Foo = unsafe { std::mem::transmute(foo) };
    foo.foo();
}

fn main() {
    let foo_impl = FooImpl {};
    let foo = &foo_impl as &dyn Foo;
    unsafe {
        call_c_with_foo(std::mem::transmute(foo));
    }
}
```

### 第二种写法

在 `std::raw::TraitObject` deprecated 之后，标准库引入了新的接口（[rust-lang/rfcs#2580](https://github.com/rust-lang/rfcs/pull/2580)）来实现类似的功能。于是上面的 Rust 代码也可以写成这样：

```rust
// src/main.rs
// ...

#[repr(C)]
pub struct TraitObject<T: ?Sized + Pointee<Metadata = DynMetadata<T>>> {
    data: *const (),
    vtable: DynMetadata<T>,
}

#[link(name = "boring", kind = "static")]
extern "C" {
    fn call_c_with_foo(foo: TraitObject<dyn Foo>);
}

#[no_mangle]
pub extern "C" fn call_rust_with_foo(foo: TraitObject<dyn Foo>) {
    println!("Hello from Rust!");
    let foo: &dyn Foo = unsafe { &*std::ptr::from_raw_parts(foo.data, foo.vtable) };
    foo.foo();
}

fn main() {
    let foo_impl = FooImpl {};
    let foo = &foo_impl as &dyn Foo;
    let foo_raw = foo as *const dyn Foo;
    let (data, vtable) = foo_raw.to_raw_parts();
    unsafe {
        call_c_with_foo(TraitObject { data, vtable });
    }
}
```

虽然这种写法编译器又会报 `DynMetadata<T>` 不是“FFI-safe”的警告，但由于 `DynMetadata<T>` 里面实际就是一个 `VTable` 的指针（是瘦指针），上面的代码是可以正确工作的。

## 参考资料

- <https://stackoverflow.com/questions/33929079/rust-ffi-passing-trait-object-as-context-to-call-callbacks-on>
- <https://adventures.michaelfbryan.com/posts/ffi-safe-polymorphism-in-rust/>
- <https://rust-lang.github.io/rfcs/2580-ptr-meta.html>
