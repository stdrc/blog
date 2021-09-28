---
title: std::function 作为参数的函数重载问题
categories: Dev
tags: [C++, std::function, 函数对象, 函数重载, 类型转换]
created: 2021-09-27 22:58:00
---

今天写 C++ 遇到一个关于 `std::function` 的有趣问题，经过一些研究之后搞清楚了原因，记录如下。

## 问题

为了避免其它代码的干扰，把问题简化描述如下：

```cpp
using namespace std;

void foo(const function<bool()> &f) {
  cout << "bool\n";
}

void foo(const function<void()> &f) {
  cout << "void\n";

  // 编译报错: 有多个重载函数 "foo" 实例与参数列表匹配
  foo([&]() -> bool { return true; });
}

void foo_user() {
  // 编译报错: 同上
  foo([&]() -> bool { return true; });

  // 不报错
  foo([&]() {});
}
```

## 为什么？

在某个 C++ 群里询问之后，有一个群友提醒说可以把编译报错的那个 lambda 表达式手动构造成 `std::function<bool()>` 来解决，于是修改成下面这样：

```cpp
using namespace std;

void foo(const function<bool()> &f) {
  cout << "bool\n";
}

void foo(const function<void()> &f) {
  cout << "void\n";

  // 不报错
  foo(std::function<bool()>([&]() -> bool { return true; }));
}

void foo_user() {
  // 不报错
  foo(std::function<bool()>([&]() -> bool { return true; }));

  // 不报错
  foo([&]() {});
}
```

确实解决了无法找到合适的重载函数的问题。进而意识到，用 lambda 的时候会报错是因为 lambda 到 `std::function` 有一次类型转换，而一开始的代码报错可能是因为 `[&]() -> bool { return true; }` 既可以转换为 `std::function<bool()>` 也可以转换为 `std::function<void()>`，从而产生了二义性。

群友后来又发现 `std::function<bool()>` 可以赋值给 `std::function<void()>`，于是猜测 `std::function` 可能不关心它所表示的函数的返回类型，但这仍然无法解释为什么 `foo([&]() {})` 不报错。后来因为忙其它事情，群里也没有继续再讨论了。

空闲下来之后，继续研究了这个问题。为了方便解释，下面用 Cling 解释器来求值一些 type trait，以观察不同 `std::function` 实例之间的关系。

首先导入需要的头文件：

```c++
$ cling -std=c++17
[cling]$ #include <type_traits>
[cling]$ using namespace std;
```

然后用 `std::is_convertible_v` 来检查不同 `std::function` 之间是否能相互转换：

```cpp
[cling]$ is_convertible_v<function<bool()>, function<void()>>
(const bool) true
[cling]$ is_convertible_v<function<void()>, function<bool()>>
(const bool) false
[cling]$ is_convertible_v<function<bool(int)>, function<bool()>>
(const bool) false
[cling]$ is_convertible_v<function<bool(int)>, function<void()>>
(const bool) false
[cling]$ is_convertible_v<function<bool(int)>, function<void(int)>>
(const bool) true
[cling]$ is_convertible_v<function<void(int)>, function<bool()>>
(const bool) false
[cling]$ is_convertible_v<function<void(int)>, function<void()>>
(const bool) false
[cling]$ is_convertible_v<function<void(int)>, function<bool(int)>>
(const bool) false
```

观察上述结果可以发现，在参数类型相同的情况下，有返回类型的 `std::function` 可以转换为无返回类型的 `std::function`。

从而一开始的问题便可以解释通了：

- `[&]() -> bool { return true; }` 既可以转换为 `std::function<bool()>` 也可以转换为 `std::function<void()>`，于是产生二义性；
- `[&]() {}` 只能转换为 `std::function<void()>`，于是没有二义性；
- 手动构造出的 `std::function<bool()>` 虽然也可以转换为 `std::function<void()>`，但由于有一个不需要类型转换的重载，于是也没有二义性。

## 为什么 `std::function<bool()>` 可以转换为 `std::function<void()>`？

虽然一开始问题解决了，但是还是不明白为什么 `std::function<bool()>` 可以转换为 `std::function<void()>`，于是去找了 `std::function` 的实现（以 [LLVM 的 libcxx](https://github.com/llvm-mirror/libcxx/blob/78d6a7767ed57b50122a161b91f59f19c9bd0d19/include/functional#L2243) 为例，代码相比 GNU libstdc++ 更清晰一些），节选如下：

```cpp
template<class _Rp, class ..._ArgTypes>
class /* ... */ function<_Rp(_ArgTypes...)> /* : ... */ {
    // ...

    template <class _Fp, bool = _And<
        _IsNotSame<__uncvref_t<_Fp>, function>,
        __invokable<_Fp&, _ArgTypes...>
    >::value>
    struct __callable;

    template <class _Fp>
    struct __callable<_Fp, true> {
        // MARK 1
        static const bool value = is_same<void, _Rp>::value ||
            is_convertible<typename __invoke_of<_Fp&, _ArgTypes...>::type, _Rp>::value;
    };
    template <class _Fp>
    struct __callable<_Fp, false> {
        static const bool value = false;
    };

    template <class _Fp>
    using _EnableIfCallable = typename enable_if<__callable<_Fp>::value>::type;

    // ...

    // MARK 2
    template<class _Fp, class = _EnableIfCallable<_Fp>>
    function(_Fp);

    // ...
};
```

可以看到 `MARK 2` 处为满足 `_EnableIfCallable<_Fp>` 的 `_Fp` 实现了一个构造函数，而满足 `_EnableIfCallable<_Fp>` 意味着 `__callable<_Fp>::value` 是 `true`。根据 `MARK 1` 处的偏特化，发现当 `_Rp`（也就是 `std::function` 的返回类型）为 `void`、或调用 `_Fp` 的返回值类型可以转换为 `_Rp` 时，`__callable<_Fp>::value` 是 `true`。

也就是说，除了前面观察发现的结论——有返回类型的 `std::function` 可以转换为无返回类型的 `std::function`，标准库还允许有返回类型的 `std::function` 转换为返回类型可由前者的返回类型构造的 `std::function`。用上一节的方式验证如下：

```cpp
[cling]$ is_convertible_v<function<int(int)>, function<long(int)>>
(const bool) true
[cling]$ struct A {};
[cling]$ struct B : A {};
[cling]$ is_convertible_v<function<B(int)>, function<A(int)>>
(const bool) true
[cling]$ is_convertible_v<function<A(int)>, function<B(int)>>
(const bool) false
```

看到这其实已经豁然开朗了，从逻辑上来说，一个有返回值的函数确实可以当作没有返回值的函数来调用，返回 `T` 的函数也可以当作返回 `T` 能转换到的类型的函数来调用，只需进行一次类型转换，非常合理。

为了确定这是 C++ 标准定义的行为而不是标准库实现的私货，去翻了 C++17 标准（因为前面的讨论都是在 C++17 标准上进行的，虽然新版本并没有变化），在 23.14.3 和 23.14.13.2 确实有相关表述，这里就不贴出了。

## 参考资料

- [llvm-mirror/libcxx](https://github.com/llvm-mirror/libcxx)
- [gcc-mirror/gcc/libstdc++-v3](https://github.com/gcc-mirror/gcc/tree/master/libstdc%2B%2B-v3)
- [N4659 - C++17 final working draft](http://open-std.org/jtc1/sc22/wg21/docs/papers/2017/n4659.pdf)
