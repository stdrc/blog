---
title: 理解 std::declval
categories: Dev
tags: [C++, 类型, 模板, 标准库]
created: 2020-09-12 16:29:00
---

> 这是一篇攒了很久的文章……相关参考链接一直放在收藏夹，今天终于决定写一下……

## 使用场景

在写 C++ 的时候，往往需要使用 `decltype` 获得一个类的成员函数的返回类型，像下面这样：

```cpp
struct A {
    int foo();
};

int main() {
    decltype(A().foo()) foo = 1; // OK
}
```

由于 `decltype` 是不会真正执行它括号里的表达式的，所以 `A` 类的默认构造函数不会被执行，`A()` 这个临时对象不会被创建。

但有时候，一个类可能没有默认构造函数，这时就无法使用上面的方法，例如：

```cpp
struct A {
    A() = delete;
    int foo();
};

int main() {
    decltype(A().foo()) foo = 1; // 无法通过编译
}
```

于是 [`std::declval`](https://en.cppreference.com/w/cpp/utility/declval) 就派上了用场：

```cpp
#include <utility>

struct A {
    A() = delete;
    int foo();
};

int main() {
    decltype(std::declval<A>().foo()) foo = 1; // OK
}
```

## 原理

于是自然想看它是如何实现的，通过阅读 cppreference 和搜索，发现它其实就只是一个模板函数的声明：

```cpp
template<class T>
typename std::add_rvalue_reference<T>::type declval() noexcept;
```

因为前面说的 `decltype` 不会真正执行括号里的表达式，所以 `std::declval` 函数实际上不会执行，而只是用来推导类型，于是这个函数不需要定义，只需要声明。

## 为什么返回引用？

接着我有了一个疑惑，为什么 `std::declval` 要返回 `std::add_rvalue_reference<T>::type` 而不是直接返回 `T` 呢？在上面的例子中，如果将 `declval` 实现成下面这样也是能够工作的：

```cpp
template<class T>
T declval() noexcept; // 某些场景下可以工作，但其实是有问题的
```

然后去搜了下，Stack Overflow 上有人跟我有同样的疑惑，看了答案恍然大悟，像 `int[10]` 这种数组类型是不能直接按值返回的，直接宣判了返回 `T` 方案的死刑，在更复杂的情况下只会更糟糕，因此还是需要返回一个引用。

## 为什么使用 `std::add_rvalue_reference` 而不是 `std::add_lvalue_reference`？

网上还有人问了为什么要用 `std::add_rvalue_reference` 而不是 `std::add_lvalue_reference`。这个问题是比较显然的，添加右值引用可以进行引用折叠，最终 `T` 和 `T &&` 变 `T &&`，`T &` 还是 `T &`，不会改变类型的性质，但如果添加左值引用，`T` 就会变 `T &`，性质直接变了，比如声明为 `int foo() &` 的成员函数，本来不能访问现在可以访问，显然是错误的。

## 参考资料

- [std::declval](https://en.cppreference.com/w/cpp/utility/declval)
- [How does std::declval<T>() work?](https://stackoverflow.com/questions/28532781/how-does-stddeclvalt-work)
- [Why does std::declval add a reference?](https://stackoverflow.com/questions/25707441/why-does-stddeclval-add-a-reference)
- [Is there a reason declval returns add_rvalue_reference instead of add_lvalue_reference](https://stackoverflow.com/questions/20303250/is-there-a-reason-declval-returns-add-rvalue-reference-instead-of-add-lvalue-ref/20303350#20303350)
