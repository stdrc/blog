---
title: CMAKE_XXX_DIR 等 CMake 内置变量辨析
categories: Dev
tags: [CMake, Build System, 构建系统]
created: 2021-12-28 14:15:00
---

最近高强度写 CMake 构建脚本（甚至还在实验室新人培训上 [讲了一手](https://www.bilibili.com/video/BV14h41187FZ)），“再一次”搞清楚了 CMake 的 `CMAKE_SOURCE_DIR`、`CMAKE_CURRENT_SOURCE_DIR` 等容易混淆的内置变量，记录并分享一下。

首先给出定义：

- `CMAKE_SOURCE_DIR`：当前 CMake *source tree* 的顶层
- `CMAKE_BINARY_DIR`：当前 CMake *build tree* 的顶层
- `CMAKE_CURRENT_SOURCE_DIR`：当前正在处理的 *source 目录*
- `CMAKE_CURRENT_BINARY_DIR`：当前正在处理的 *binary 目录*
- `CMAKE_CURRENT_LIST_FILE`：当前正在处理的 CMake *list 文件*（`CMakeLists.txt` 或 `*.cmake`）
- `CMAKE_CURRENT_LIST_DIR`：当前正在处理的 CMake *list 文件*所在目录
- `PROJECT_SOURCE_DIR`：当前最近的 `project()` 命令所在 *source 目录*
- `PROJECT_BINARY_DIR`：当前最近的 `project()` 命令对应 *binary 目录*

下面通过例子来尝试解释清楚不同情况下，这些值都是什么。

现假设有一个项目名叫 `cmake-playground`，位于 `/Users/richard/Lab/cmake-playground`，有三个源码子目录 `lib`、`server`、`client` 和一个 CMake 模块目录 `cmake`，整体目录结构如下：

```
.
├── client
│  ├── CMakeLists.txt
│  └── external
│     └── somelib
│        └── CMakeLists.txt
├── cmake
│  └── MyModule.cmake
├── CMakeLists.txt
├── lib
│  ├── CMakeLists.txt
│  ├── core
│  │  └── CMakeLists.txt
│  └── utils
│     └── CMakeLists.txt
└── server
   ├── CMakeLists.txt
   └── web
      └── CMakeLists.txt
```

## 基本情形

首先关注项目根目录和 `lib` 目录：

```cmake
# CMakeLists.txt

cmake_minimum_required(VERSION 3.14)
project(Playground)

message(STATUS "=================================")
message(STATUS "${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")

add_subdirectory(lib)
add_subdirectory(server)
add_subdirectory(client)
```

```cmake
# lib/CMakeLists.txt

message(STATUS "=================================")
message(STATUS "${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")

add_subdirectory(core)
add_subdirectory(utils)
```

```cmake
# lib/core/CMakeLists.txt

message(STATUS "=================================")
message(STATUS "${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")
```

使用如下命令进行 CMake configure 步骤：

```sh
$ cmake -S . -B build # -S 参数指定源码目录，-B 参数指定 build 目录
```

输出如下：

```
-- =================================
-- /Users/richard/Lab/cmake-playground/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- =================================
-- =================================
-- /Users/richard/Lab/cmake-playground/lib/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/lib
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/lib
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- =================================
-- =================================
-- /Users/richard/Lab/cmake-playground/lib/core/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/lib/core
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/lib/core
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- =================================
```

可以发现 `CMAKE_SOURCE_DIR` 始终是项目根目录，也就是 CMake `-S` 参数指定的目录，`CMAKE_BINARY_DIR` 始终是 build 目录，也就是 `-B` 参数指定的目录。

随着 `add_subdirectory` 的深入，CMake 会设置 `CMAKE_CURRENT_SOURCE_DIR` 为当前正在处理的源码目录，同时，会在 `CMAKE_BINARY_DIR` 中创建对应层级的 build 目录，用于存放 CMake 产生的构建脚本（Makefile 等）和实际构建时产生的文件，并设置到 `CMAKE_CURRENT_BINARY_DIR`。

`PROJECT_SOURCE_DIR` 和 `PROJECT_BINARY_DIR` 这里等于 `CMAKE_SOURCE_DIR` 和 `CMAKE_BINARY_DIR`，因为每次访问时，最近的 `project()` 调用都是在项目根目录 `CMakeLists.txt`。

## 定义新的 Project

接着看 `server` 目录，这里通过 `project()` 调用定义了一个新的 project：

```cmake
# server/CMakeLists.txt

project(MyServer)

message(STATUS "=================================")
message(STATUS "${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")

add_subdirectory(web)
```

```cmake
# server/web/CMakeLists.txt

message(STATUS "=================================")
message(STATUS "${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")
```

同样通过 `cmake -S . -B build` 进行 configure，输出如下：

```
-- =================================
-- /Users/richard/Lab/cmake-playground/server/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/server
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/server
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/server
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/server
-- =================================
-- =================================
-- /Users/richard/Lab/cmake-playground/server/web/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/server/web
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/server/web
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/server
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/server
-- =================================
```

此时 `PROJECT_SOURCE_DIR` 和 `PROJECT_BINARY_DIR` 变成了 `server` 对应的源码和 build 目录。

## 添加外部项目

看起来 `CMAKE_SOURCE_DIR` 和 `CMAKE_BINARY_DIR` 永远是调用 CMake 命令时指定的源码和 build 目录，那它们有没有可能变呢？实际是有可能的。

这里 `client` 目录中使用 `ExternalProject_Add` 添加了一个外部项目：

```cmake
# client/CMakeLists.txt

message(STATUS "=================================")
message(STATUS "${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")

include(ExternalProject)
ExternalProject_Add(
    somelib
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external/somelib
    INSTALL_COMMAND echo "Skipping install step")
```

```cmake
# client/external/somelib/CMakeLists.txt

cmake_minimum_required(VERSION 3.14)
project(SomeLib)

message(STATUS "=================================")
message(STATUS "${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")
```

这次运行的 CMake 命令有所不同，因为 `ExternalProject_Add` 添加的外部项目要在外层项目 build 时才会 configure + build：

```sh
cmake -S . -B build && cmake --build build
```

输出如下（省略了不重要的内容）：

```
-- =================================
-- /Users/richard/Lab/cmake-playground/client/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/client
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/client
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- =================================
...
-- =================================
-- /Users/richard/Lab/cmake-playground/client/external/somelib/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground/client/external/somelib
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/client/somelib-prefix/src/somelib-build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/client/external/somelib
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/client/somelib-prefix/src/somelib-build
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/client/external/somelib
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/client/somelib-prefix/src/somelib-build
-- =================================
```

可以看到 CMake 为 `somelib` 项目创建了一个特别的目录 `build/client/somelib-prefix`（可以在 `ExternalProject_Add` 参数中配置），并在里面创建了 `somelib` 的 build 目录，然后设置到了 `somelib` 的 `CMAKE_SOURCE_DIR` 和 `CMAKE_BINARY_DIR`。这就像是为 `somelib` 创建了一个沙盒，让它不会干扰外层项目的构建环境。

## 在模块、宏、函数中

当上面这些变量遇到引入模块、调用宏和函数时，情况又变得更加复杂（当然这时候变量的作用域是更容易出错的点，先挖个坑，下次再写）。

我们首先编写一个 CMake 模块：

```cmake
# cmake/MyModule.cmake

message(STATUS "=================================")
message(STATUS "CMAKE_CURRENT_LIST_FILE: ${CMAKE_CURRENT_LIST_FILE}")
message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
message(STATUS "=================================")

macro(my_macro)
    message(STATUS "=================================")
    message(STATUS "In my_macro:")
    message(STATUS "CMAKE_CURRENT_LIST_FILE: ${CMAKE_CURRENT_LIST_FILE}")
    message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
    message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
    message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
    message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
    message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
    message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
    message(STATUS "=================================")
endmacro()

function(my_function)
    message(STATUS "=================================")
    message(STATUS "In my_function:")
    message(STATUS "CMAKE_CURRENT_LIST_FILE: ${CMAKE_CURRENT_LIST_FILE}")
    message(STATUS "CMAKE_SOURCE_DIR: ${CMAKE_SOURCE_DIR}")
    message(STATUS "CMAKE_BINARY_DIR: ${CMAKE_BINARY_DIR}")
    message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
    message(STATUS "CMAKE_CURRENT_BINARY_DIR: ${CMAKE_CURRENT_BINARY_DIR}")
    message(STATUS "PROJECT_SOURCE_DIR: ${PROJECT_SOURCE_DIR}")
    message(STATUS "PROJECT_BINARY_DIR: ${PROJECT_BINARY_DIR}")
    message(STATUS "=================================")
endfunction()
```

然后在根目录 `CMakeLists.txt` 引入这个模块，并在之后的代码中使用其中的宏和函数：

```cmake
# CMakeLists.txt

cmake_minimum_required(VERSION 3.14)
project(Playground)

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
include(MyModule)

# ...
```

```cmake
# lib/CMakeLists.txt

my_macro()
my_function()

# ...
```

执行 configure，输出如下：

```
-- =================================
-- CMAKE_CURRENT_LIST_FILE: /Users/richard/Lab/cmake-playground/cmake/MyModule.cmake
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- =================================
-- =================================
-- In my_macro:
-- CMAKE_CURRENT_LIST_FILE: /Users/richard/Lab/cmake-playground/lib/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/lib
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/lib
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- =================================
-- =================================
-- In my_function:
-- CMAKE_CURRENT_LIST_FILE: /Users/richard/Lab/cmake-playground/lib/CMakeLists.txt
-- CMAKE_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- CMAKE_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- CMAKE_CURRENT_SOURCE_DIR: /Users/richard/Lab/cmake-playground/lib
-- CMAKE_CURRENT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build/lib
-- PROJECT_SOURCE_DIR: /Users/richard/Lab/cmake-playground
-- PROJECT_BINARY_DIR: /Users/richard/Lab/cmake-playground/build
-- =================================
```

也就是说，当 `include(MyModule)` 时，`CMAKE_CURRENT_LIST_FILE` 和 `CMAKE_CURRENT_LIST_DIR` 指向 CMake 模块文件的位置，而其它相关变量则继承自 `include` 的调用处；当调用宏和函数时，上述所有变量都继承自调用处。

## 所以应该用哪个呢？

这里记录几个我自身的经验：

- 如果要引用同目录或下级目录的位置，可以用相对路径或使用 `CMAKE_CURRENT_SOURCE_DIR`/`CMAKE_CURRENT_LIST_DIR`（根据当前 CMake 文件是 `CMakeLists.txt` 还是 `*.cmake` 适当选择）
- `configure_file` 产生的文件存放位置和 `add_custom_target` 默认的工作目录是 `CMAKE_CURRENT_BINARY_DIR`
- 当要引用相对于项目根目录的位置时
    - 如果是在编写一个库，应该用 `PROJECT_SOURCE_DIR`，防止别人把你的项目当作子目录去 `add_subdirectory` 时出现问题
    - 如果是在编写一个应用，或者确定项目不会被 `add_subdirectory`，可以使用 `CMAKE_SOURCE_DIR`
