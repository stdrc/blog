---
title: 不要在 C++ 基类构造函数中创建新线程
categories: Dev
tags: [C++, 多线程, 基类, 构造函数]
created: 2021-03-06 13:48:00
---

这个问题源于之前的另一篇文章 [移植树莓派驱动框架 Circle 到自制操作系统](../../../../2021/01/22/porting-circle/) 所做的事情，移植 Circle 驱动框架的过程中有一步需要用我们的 OS 的用户态设施（其实就是 pthread API）实现 Circle 的 `CTask` 类，这个类是 Circle 中的线程抽象，移植后一开始可以工作，之后频繁出现执行到基类的虚函数的情况，debug 之后在这里总结一下，顺便也从反汇编的角度整理一下 C++ 虚函数的实现方式。

## 简化问题

当时遇到问题时的代码可以简化为如下（pthread 使用 `std::thread` 代替了，效果一样）：

```cpp
#include <cassert>
#include <chrono>
#include <iostream>
#include <thread>

using namespace std;
using namespace std::literals::chrono_literals;

struct Task {
    thread t;

    Task() {
        t = thread(task_entry, this);
        this_thread::sleep_for(500ms); // 这里 sleep 是为了稳定复现 data race
    }

    virtual ~Task() = default;

    virtual void run() {
        assert(false); // 不应该执行到这里
    }

    void join() {
        if (t.joinable()) t.join();
    }

    static void task_entry(Task *task) {
        cout << "before run" << endl;
        task->run();
        cout << "after run" << endl;
    }
};

struct TaskImpl : Task {
    void run() override {
        cout << "TaskImpl run!" << endl;
    }
};

int main() {
    Task *t1 = new TaskImpl;
    t1->join();
    return 0;
}
```

这里的基本逻辑是，在 `new TaskImpl` 创建一个 `Task` 子类时，会开一个线程来执行这个 task，具体的就是运行 `run` 方法。理想情况下，由于 C++ 所支持的运行期多态，`Task::task_entry` 拿到的 `task` 参数实际上是一个 `TaskImpl`，对它调用 `run` 应该会动态的分发到 `TaskImpl::run`，但实际上上面的代码并不能稳定工作，报错如下：

```
before run
Assertion failed: (false), function run, file thread.cpp, line 20.
[1]    22139 abort      ./test
```

因为 `thread(task_entry, this)` 创建的新线程被调度的时候，`TaskImpl` 对象可能还没创建完，于是虚函数表指针可能还没有指向预期的虚表。

## 多态的实现

去掉那行 `sleep_for`，编译之后看反汇编的结果（以 x86_64 举例），截取 `Task::task_entry(Task*)` 中调用 `run` 的部分如下：

```x86asm
Task::task_entry(Task*):
                  # ......
0000000100001d5f  movq  %rdi, -0x8(%rbp)
                  # ......
0000000100001d81  movq  -0x8(%rbp), %rcx
0000000100001d85  movq  (%rcx), %rdx
0000000100001d88  movq  %rcx, %rdi
0000000100001d8b  movq  %rax, -0x10(%rbp)
0000000100001d8f  callq *0x10(%rdx)
                  # ......
```

`1d5f` 这一行中，`Task *task` 参数在 `%rdi`，之后在 `1d81` 行被挪到了 `%rcx`，`1d85` 行取该指针指向的对象的最开头 8 个字节放到 `%rdx`，这就是虚函数表指针；然后又把 `%rcx` 放到 `%rdi`，即为 `run` 方法的隐藏参数 `this` 指针；接着 `1d8f` 行调用 `%rdx` 指向的虚函数表的第 0x10 字节处的虚函数指针。

搞清楚了虚函数如何被调用，再看下虚函数表指针是怎么设置的，截取 `Task` 和 `TaskImpl` 构造函数的一部分如下：

```x86asm
TaskImpl::TaskImpl():
                  # ......
0000000100001bda  callq Task::Task()
0000000100001bdf  movq  0x243a(%rip), %rax
0000000100001be6  addq  $0x10, %rax
0000000100001bec  movq  -0x10(%rbp), %rcx
0000000100001bf0  movq  %rax, (%rcx)
                  # ......

Task::Task():
                  # ......
0000000100001c08  movq  %rdi, -0x8(%rbp)
0000000100001c0c  movq  -0x8(%rbp), %rax
0000000100001c10  movq  0x2401(%rip), %rcx
0000000100001c17  addq  $0x10, %rcx
0000000100001c1b  movq  %rcx, (%rax)
                  # ......
0000000100001c4c  callq std::__1::thread::thread<void (&)(Task*), Task*, void>(void (&)(Task*), Task*&&)
                  # ......
```

可以看到 `TaskImpl::TaskImpl` 首先调用了 `Task::Task`，后者的最开头首先设置了 `this` 的虚函数表指针（`1c10` 至 `1c1b` 行），这时的虚函数表指针是指向 `Task` 类的虚函数表；接着 `Task::Task` 调用 `thread::thread` 创建新线程，返回；回到 `TaskImpl::TaskImpl`，再次设置了 `this` 的虚函数表指针（`1bdf` 至 `1bf0` 行），这次指向的是 `TaskImpl` 类的虚表。

于是很容易发现，创建新线程发生在 `this` 的虚表指针指向 `TaskImpl` 虚表之前，如果新线程很快被调度，会导致在里面调用 `run` 方法实际运行的是 `Task::run`。

## 教训

这次的 bug 再次强调了多线程编程的易错性，尤其在 C++ 的构造函数中，一定要尽量避免多线程，如果真的要多线程，也一定不能在新创建的线程中访问正在创建的对象 `this` 指针。
