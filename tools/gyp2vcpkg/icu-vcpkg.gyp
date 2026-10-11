# icu 在 gyp 侧的占位 —— fe 的配置（`cmake/gyp2vcpkg/config.json`）用
# `define_overrides.icu_gyp_path` 指向它。
#
# 为什么不直接指 node 自带的 `tools/icu/icu-generic.gyp`：
#   1. 它 `includes: ['../../icu_config.gypi']`，那是 node 的 configure 才生成的，
#      仓库里没有 —— 解析直接失败；
#   2. 即便能加载，它导出的那批宏（UCONFIG_NO_SERVICE=1 / U_ENABLE_DYLOAD=0 /
#      U_STATIC_IMPLEMENTATION=1 …）是 **small-icu 裁剪版**的口径，而 fe 的 icu
#      走 vcpkg（full ICU）—— 把 small-icu 的宏喂给 full ICU 的产物，等于
#      **编出与库不一致的事实**。
#
# 所以这里只把**依赖边接住**：v8.gyp / node.gypi 用 `<(icu_gyp_path):icui18n` 这种
# 形式引用 icu（`v8_maybe_icu` 还要 export_dependent_settings），缺了它们 gyp 解析
# 就报 "not found"。三个目标都做成 `none` 且不带任何设置，于是依赖方从 icu 侧拿不到
# 宏与 include —— 与 fe 现在的实际链接方式一致（`cmake/v8/CMakeLists.txt` 里
# `target_link_libraries(v8_maybe_icu INTERFACE ICU::data ICU::i18n ICU::uc)`）。
#
# 形状照 node 自带的 `tools/icu/icu-system.gyp`（`--with-intl=system-icu` 那一支就是
# 这么干的："configure 已经设好 libs 和 cflags，这些目标里没什么可做的"），只多了
# `icudata` —— v8.gyp 在 `OS=="win"` 分支里要它。
#
# 注意：路径必须是**绝对路径**（配置里用 `{{here}}` 展开）—— gyp 把依赖里的相对路径
# 解释成"相对引用它的那个 .gyp 文件"，而 node.gyp（在根）与 v8.gyp（在
# tools/v8_gypfiles/）的基准不一样，同一个相对值不可能两边都对。

{
  'targets': [
    {
      'target_name': 'icuuc',
      'type': 'none',
      'toolsets': ['host', 'target'],
    },
    {
      'target_name': 'icui18n',
      'type': 'none',
      'toolsets': ['host', 'target'],
    },
    {
      'target_name': 'icudata',
      'type': 'none',
      'toolsets': ['host', 'target'],
    },
  ],
}
