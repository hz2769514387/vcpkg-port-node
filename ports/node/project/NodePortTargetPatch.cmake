# 本 port **自有目标**的编译选项 patch。
#
# 这个文件是**patch**，不是"编译配置的第二份定义"。分工是：
#
#   * V8 / node 主体的编译配置 → **从 gyp 来**（`generated/*.cmake`，由 gyp2vcpkg
#     从 node 自带的 gyp 实测解析生成，含 cflags / cflags_cc / ldflags /
#     msvs_disabled_warnings / WarningLevel / RTTI / 异常…）；
#   * 全工程**硬约束**（C++ 标准、PIC、CRT 口径跟随 triplet）→ 顶层 `CMakeLists.txt`；
#   * 剩下的只有**那些 gyp 里没有对应目标**的自有目标（node_main 等）—— 它们没有
#     gyp 清单可用，才由这里补。
#
# 所以叫 patch 而不是 Options：它是"没有标准答案时的补齐"，不是"另立一套标准"。
# 每加一条都要写清为什么 gyp 拿不到（拿得到就该从 gyp 拿）。

function(node_port_patch_own_target name)
  if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    # /utf-8：node 的源码里有 UTF-8 字面量且不带 BOM，MSVC 默认按本地码页读会报
    #   C4819（gyp 侧同一件事写在 common.gypi 的 AdditionalOptions 里）。
    # /W3：**对齐 node**（common.gypi:396 的 WarningLevel 就是 3）。
    # /GR- /EHs-c-：与 node 一致（common.gypi:333 / 391），CRT 与 STL 侧再配
    #   _HAS_EXCEPTIONS=0（MSVC 关异常是这两件一起做，否则 <vector> 会蹦 C4530）。
    target_compile_options(${name} PRIVATE
      "$<$<COMPILE_LANGUAGE:C,CXX>:/utf-8;/Zc:__cplusplus;/bigobj;/W3;/permissive->"
      "$<$<COMPILE_LANGUAGE:CXX>:/GR-;/EHs-c->")
    # clang-cl 额外一条：node 的 `cflags`（common.gypi）里有 `-Wno-unused-parameter`，
    #   官方 Windows 构建用 MSVC 时它不生效；clang-cl 在 /W3 就会开出来。**只喂给 clang**
    #   （真正的 cl.exe 不认 `-W...`，会报 D9002）。
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
      target_compile_options(${name} PRIVATE
        "$<$<COMPILE_LANGUAGE:C,CXX>:-Wno-unused-parameter>")
    endif()
    target_compile_definitions(${name} PRIVATE
      _CRT_SECURE_NO_WARNINGS
      _HAS_EXCEPTIONS=0
      NOMINMAX              # node: common.gypi:570 —— 别让 <windows.h> 定义 min/max
      WIN32_LEAN_AND_MEAN
      UNICODE
      _UNICODE)
  else()
    # POSIX 这一套就是 common.gypi:576-585 的 cflags_cc（V8/node 目标由 gyp 清单给，
    # 这里是给"没有 gyp 清单"的那些目标同一口径）。
    target_compile_options(${name} PRIVATE
      "$<$<COMPILE_LANGUAGE:C,CXX>:-Wall;-Wextra;-Wno-unused-parameter>"
      "$<$<COMPILE_LANGUAGE:CXX>:-fno-rtti;-fno-exceptions;-fno-strict-aliasing>")
    target_compile_definitions(${name} PRIVATE __STDC_FORMAT_MACROS)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      # glibc 把 RTLD_DEEPBIND 这类 GNU 专有部分放在 `_GNU_SOURCE` 后面。
      # g++ 在每个 C++ 模式都定义它（所以 node 的 Linux 构建看得见），clang 不定义。
      # 这是**全构建级**的定义：同一个特性宏在一个编译单元里开、另一个里关，比两边都关更糟。
      target_compile_definitions(${name} PRIVATE _GNU_SOURCE)
    endif()
  endif()
endfunction()
