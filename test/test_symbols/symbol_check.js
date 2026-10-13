#!/usr/bin/env node
// 符号审计：node port 自带的库 vs vcpkg 依赖库，是否存在**跨库重复强符号**。
//
// 为什么用 JS、由本工程自己编出来的 node 跑（而不是仓库根的 python 脚本）：
//   * 用户要求：ctest 里跑的东西都是 C 或 JS，工具也该一致；
//   * 顺带变成一次自检 —— 这份脚本能被"本仓库刚编出来的 node"正确执行，
//     本身就说明那个 node 的 fs / child_process / Buffer 是好的；
//   * 不再往仓库里引入第二个脚本语言运行时（原 python 版只在 Windows 能用）。
//
// 用法：
//   node symbol_check.js --node-lib-dir <dir> [--node-lib-dir <dir2> ...]
//                        --dep-root <vcpkg packages> --triplet <t>
//                        [--node-libs a.lib,b.lib,...] [--dumpbin <路径>] [--nm <路径>]
//                        [--json out.json] [--fail-on-duplicates]
//
//   --node-lib-dir：可重复给出。node 的库分布在 <prefix>/lib 与
//     <prefix>/lib/manual-link 两层（B1 之后冲突库装后者），都要进审计。
//
//   --node-libs：**只**把这些文件当成"node 的库"。强烈建议给。
//     <prefix>/lib 在 manifest 模式下是整个工程共用的，里面还混着使用者自己声明
//     的库（gtest / fmt / ...）。不给的话会把整个目录当成 node 的库，再拿去和
//     vcpkg packages 比，就成了"自己比自己"，满屏 gtest.lib vs gtest/gtest.lib
//     这种假阳性 —— 闸门常红就等于没有闸门。node-config.cmake 会导出
//     node_INSTALLED_LIBRARIES，正是这份清单。
//
//   --dumpbin / --nm：工具的绝对路径。ctest 进程不在 vcvars 环境里，光靠 PATH 找不到
//                      dumpbin，所以由 CMake 在配置期解析好传进来。
//   --fail-on-duplicates：发现跨库重复强符号就以退出码 1 结束（当闸门用）。
//                         不加则只报告、退出码恒为 0（当调查工具用）。
//
// 原理：
//   把每个 .lib / .a 的**定义符号**抓出来，只保留强符号（External 且非 COMDAT、
//   非弱符号），再做跨库交集。交集非空 = 两个库都定义了同一个强符号。
//
// 为什么排除 COMDAT / 弱符号：
//   COMDAT 重复是设计允许的（inline / template / MSVC 字符串字面量，每个 obj 各带一份，
//   链接器按 COMDAT 折叠）；弱符号同理。**同名 COMDAT 被静默折叠**才是真正的隐患 ——
//   链接期不报错，运行时用哪一份由链接器决定，版本不同就是不稳定行为。
//
// 平台差异：
//   Windows -> dumpbin /symbols（COFF 符号表，COMDAT 信息在 "Section length ... selection N"）
//   其它    -> nm -g --defined-only（类型字母区分强弱：W/V/w/v 是弱，U 是未定义）
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const USAGE = `用法: node symbol_check.js --node-lib-dir <dir> [--node-lib-dir <dir> ...]
                --dep-root <pkgs> --triplet <t>
                [--node-libs a,b,...] [--dumpbin <path>] [--nm <path>]
                [--json out.json] [--fail-on-duplicates]`;

function parseArgs(argv) {
  const opts = {
    nodeLibDirs: [], depRoot: null, triplet: null,
    nodeLibs: null,
    dumpbin: null, nm: null, json: null, failOnDuplicates: false,
    selfPackage: 'node',
  };
  const need = {
    '--node-lib-dir': 'nodeLibDir', '--dep-root': 'depRoot', '--triplet': 'triplet',
    '--node-libs': 'nodeLibs',
    '--dumpbin': 'dumpbin', '--nm': 'nm', '--json': 'json',
    '--self-package': 'selfPackage',
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--fail-on-duplicates') { opts.failOnDuplicates = true; continue; }
    if (a === '--node-lib-dir') {
      // 可重复：node 的库可能分布在 <prefix>/lib 与 <prefix>/lib/manual-link
      // 两层（B1 之后 abseil/highway 等冲突库装到 manual-link），都要进审计。
      opts.nodeLibDirs.push(argv[++i]);
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(need, a)) {
      opts[need[a]] = argv[++i];
      continue;
    }
    throw new Error(`未知参数: ${a}\n${USAGE}`);
  }
  if (!opts.nodeLibDirs.length || !opts.depRoot || !opts.triplet) throw new Error(USAGE);
  return opts;
}

function run(cmd, args) {
  // dumpbin 输出是本地代码页（中文 Windows 上是 GBK）；这里只关心 ASCII 符号名，
  // 用 latin1 解码保证字节不丢、不因为多字节字符错位。
  return execFileSync(cmd, args, {
    encoding: 'latin1', maxBuffer: 256 * 1024 * 1024, timeout: 900000,
  });
}

// ---------------------------------------------------------------------------
// Windows：dumpbin /symbols
// ---------------------------------------------------------------------------

const RE_SECT_HEAD = /^\s*[0-9A-F]+\s+[0-9A-F]+\s+(SECT\S+)\s/;
const RE_SYM_LINE = /^\s*[0-9A-F]+\s+[0-9A-F]+\s+(SECT\S+)\s+.*?\s+(External|WeakExternal|Static)\s+\|\s*(\S+)/;
const RE_COMDAT = /selection\s+\d/;
// MSVC 的字符串字面量 COMDAT：??_C@_...@...?$AA@。允许跨库重复，必须排除，
// 否则整份报告全是假阳性。
const RE_STRING_LITERAL = /^\?\?_C@/;

function dumpbinSymbols(lib, dumpbin) {
  let out;
  try {
    out = run(dumpbin, ['/symbols', '/nologo', lib]);
  } catch (e) {
    return { syms: null, err: String(e && e.message ? e.message : e) };
  }
  if (!out || out.indexOf('COFF SYMBOL TABLE') < 0) {
    return { syms: null, err: 'no COFF table' };
  }
  const lines = out.split(/\r?\n/);

  // 第一遍：找出哪些段是 COMDAT。dumpbin 里每个段是两行，
  //   "F3F 00000000 SECT3BE notype  Static | .rdata"
  //   "      Section length 2A0, ..., selection 2 (pick any)"
  // 第二行不带 SECT 编号，所以必须顺序扫描、记住上一行的段号。
  const comdat = new Set();
  let lastSect = null;
  for (const line of lines) {
    if (line.indexOf('Section length') >= 0) {
      if (RE_COMDAT.test(line) && lastSect) comdat.add(lastSect);
      continue;
    }
    const m = RE_SECT_HEAD.exec(line);
    if (m) lastSect = m[1];
  }

  // 第二遍：收 External 的强符号
  const strong = new Set();
  for (const line of lines) {
    const m = RE_SYM_LINE.exec(line);
    if (!m) continue;
    const [, sect, bind, name] = m;
    if (bind !== 'External') continue;
    if (comdat.has(sect)) continue;      // COMDAT：允许重复
    if (name.startsWith('.')) continue;  // 段名 / 内部符号
    if (RE_STRING_LITERAL.test(name)) continue;
    strong.add(name);
  }
  return { syms: strong, err: null };
}

// ---------------------------------------------------------------------------
// 其它平台：nm
// ---------------------------------------------------------------------------
// nm 每行形如 "0000000000000000 T name"，成员前会有 "member.o:" 标题行。
// -g 只看外部符号，--defined-only 去掉未定义。类型字母：
//   A B D G R S T  已定义的全局（强）； W V w v 弱； U 未定义； u 唯一全局； i ifunc。
const RE_NM = /^\s*[0-9A-Fa-f]*\s+([A-Za-z])\s+(\S+)\s*$/;
const NM_WEAK = new Set(['W', 'V', 'w', 'v', 'U', 'u', 'i']);

function nmSymbols(lib, nm) {
  let out;
  try {
    out = run(nm, ['-g', '--defined-only', lib]);
  } catch (e) {
    // macOS 的 nm 不支持 --defined-only 的长选项写法，退回 -g 全集再自己过滤
    try {
      out = run(nm, ['-g', lib]);
    } catch (e2) {
      return { syms: null, err: String(e2 && e2.message ? e2.message : e2) };
    }
  }
  const strong = new Set();
  for (const line of out.split(/\r?\n/)) {
    if (!line || line.endsWith(':')) continue;  // 归档成员标题行
    const m = RE_NM.exec(line);
    if (!m) continue;
    const [, type, name] = m;
    if (NM_WEAK.has(type)) continue;
    if (name.startsWith('.')) continue;
    strong.add(name);
  }
  return { syms: strong, err: null };
}

// ---------------------------------------------------------------------------
// 已知重复白名单
// ---------------------------------------------------------------------------
// v8 内嵌了 abseil / highway 的私有拷贝，vcpkg 又提供同名库 —— 两份拷贝的强符号
// 在 ELF/MachO 上就是跨库重复（nm 报成强符号；Windows 上同样的重复因为是 COMDAT
// 而被判成弱符号，所以 Windows 闸门天然是绿的，Linux/macOS 会红 —— 同一已知原因
// 在不同平台结论相反）。这是记录在案的已知限制（暂时还没做.md §5g）。
//
// 白名单按**库文件名 stem**（去目录、去扩展名）匹配，dep 侧条目以 '*' 结尾表示
// 前缀通配。命中白名单的重复照常报告（划入 known_duplicates，含 JSON），但不再
// 触发 --fail-on-duplicates —— **白名单之外的任何新重复仍然红灯**。
const KNOWN_DUPLICATES = [
  {
    node: 'abseil',
    dep: ['absl_*'],
    why: 'v8 内嵌 abseil vs vcpkg abseil（同一第三方库的两份拷贝，已知限制 §5g）',
  },
  {
    node: 'highway',
    dep: ['hwy', 'hwy_*'],
    why: 'v8 内嵌 highway vs vcpkg highway / libhwy（同上，已知限制 §5g）',
  },
];

function libStem(file) {
  let s = file.replace(/\.(lib|a)$/i, '').replace(/^.*[\\/]/, '');
  // POSIX 的库带 lib 前缀（libabseil.a），Windows 没有（abseil.lib）——剥掉前缀
  // 让两边落到同一个名字上。只剩 "lib" 本身时不剥（防御性）。
  if (/^lib./i.test(s)) s = s.slice(3);
  return s;
}

function depStemMatches(depFile, patterns) {
  const stem = libStem(depFile);
  return patterns.some((p) =>
    p.endsWith('*') ? stem.indexOf(p.slice(0, -1)) === 0 : stem === p
  );
}

function isKnownDuplicate(nodeFile, depFile) {
  const nodeStem = libStem(nodeFile);
  return KNOWN_DUPLICATES.filter(
    (e) => e.node === nodeStem && depStemMatches(depFile, e.dep)
  ).map((e) => e.why);
}

// ---------------------------------------------------------------------------

function collect(opts) {
  const isWin = process.platform === 'win32';
  const tool = isWin ? (opts.dumpbin || 'dumpbin') : (opts.nm || 'nm');
  const ext = isWin ? '.lib' : '.a';
  const read = isWin
    ? (f) => dumpbinSymbols(f, tool)
    : (f) => nmSymbols(f, tool);

  const nodeLibs = {};
  // 给了 --node-libs 就只认清单里的（推荐）；没给就扫整个目录，并在报告里点明
  // 这会产生"自己比自己"的假阳性。
  let names = null;
  if (opts.nodeLibs) {
    names = opts.nodeLibs.split(',').map((s) => s.trim()).filter(Boolean);
    console.log(`node 侧只取清单里的 ${names.length} 个库（node_INSTALLED_LIBRARIES）`);
  } else {
    console.log('警告：未给 --node-libs，node 侧将扫描整个 lib 目录；'
      + '<prefix>/lib 是共用的，会混入使用者自己的库并产生"自己比自己"的假阳性。');
  }
  for (const dir of opts.nodeLibDirs) {
    if (!fs.existsSync(dir)) continue;  // manual-link 可能不存在（无冲突库的配置）
    for (const f of fs.readdirSync(dir).sort()) {
      if (!f.toLowerCase().endsWith(ext)) continue;
      if (names && names.indexOf(f) < 0) continue;
      if (Object.prototype.hasOwnProperty.call(nodeLibs, f)) continue;  // 两层目录同名防重
      const { syms, err } = read(path.join(dir, f));
      if (syms) nodeLibs[f] = syms;
      else console.error(`  ! ${f}: ${err}`);
    }
  }
  if (names) {
    // missing 检查必须在**所有**目录扫完之后做 —— 某个库只装在 manual-link 层，
    // 只扫第一层就报缺会误报。
    const missing = names.filter((n) => !Object.prototype.hasOwnProperty.call(nodeLibs, n));
    if (missing.length) {
      console.error(`  ! 清单里有 ${missing.length} 个库在 ${opts.nodeLibDirs.join(' / ')} 下找不到: `
        + `${missing.join(', ')}`);
    }
  }

  const depLibs = {};
  // 本 port 自己也会出现在 packages 里（overlay port 一样会被 vcpkg 编进
  // packages/node_<triplet>/）。不排除它，node 的库就会**同时出现在两侧**，
  // 于是又变成"自己比自己" —— 实测报出 10 组，最大一组是
  // v8_base_without_compiler.lib vs node_x64-.../v8_base_without_compiler.lib 260 个。
  const selfPkg = `${opts.selfPackage}_${opts.triplet}`;
  let skippedSelf = false;
  if (fs.existsSync(opts.depRoot)) {
    for (const pkg of fs.readdirSync(opts.depRoot).sort()) {
      if (pkg.indexOf(opts.triplet) < 0) continue;
      if (pkg === selfPkg) { skippedSelf = true; continue; }
      const libdir = path.join(opts.depRoot, pkg, 'lib');
      if (!fs.existsSync(libdir)) continue;
      for (const f of fs.readdirSync(libdir).sort()) {
        if (!f.toLowerCase().endsWith(ext)) continue;
        const { syms } = read(path.join(libdir, f));
        if (syms) depLibs[`${pkg}/${f}`] = syms;
      }
    }
  }
  return { nodeLibs, depLibs, tool, skippedSelf, selfPkg };
}

function total(m) {
  let n = 0;
  for (const k of Object.keys(m)) n += m[k].size;
  return n;
}

function main(argv) {
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (e) {
    console.error(String(e.message || e));
    return 2;
  }

  const { nodeLibs, depLibs, tool, skippedSelf, selfPkg } = collect(opts);
  console.log(`符号工具: ${tool}`);
  console.log(`== node 自带库 ${Object.keys(nodeLibs).length} 个（强符号合计 ${total(nodeLibs)}）==`);
  for (const k of Object.keys(nodeLibs).sort((a, b) => nodeLibs[b].size - nodeLibs[a].size)) {
    console.log(`   ${k.padEnd(46)} ${String(nodeLibs[k].size).padStart(6)} 个强符号`);
  }
  console.log('');
  console.log(`== vcpkg 依赖库 ${Object.keys(depLibs).length} 个（强符号合计 ${total(depLibs)}）==`);
  for (const k of Object.keys(depLibs).sort((a, b) => depLibs[b].size - depLibs[a].size)) {
    console.log(`   ${k.padEnd(46)} ${String(depLibs[k].size).padStart(6)} 个强符号`);
  }

  if (skippedSelf) {
    console.log(`（已排除本 port 自己的 packages/${selfPkg} —— 否则两侧都有 node 的库）`);
  }

  console.log('');
  console.log('== 跨库重复强符号 ==');
  const found = [];
  for (const nl of Object.keys(nodeLibs)) {
    for (const dl of Object.keys(depLibs)) {
      const common = [];
      for (const s of nodeLibs[nl]) if (depLibs[dl].has(s)) common.push(s);
      if (common.length) found.push({ node: nl, dep: dl, syms: common.sort() });
    }
  }
  // 白名单内/外分流：只有白名单之外的重复才触发 --fail-on-duplicates。
  const unknown = [];
  const known = [];
  for (const d of found) {
    (isKnownDuplicate(d.node, d.dep).length ? known : unknown).push(d);
  }
  if (!found.length) {
    console.log('(无)');
  } else {
    found.sort((a, b) => b.syms.length - a.syms.length);
    for (const d of found) {
      console.log(`  ${d.node.padEnd(40)}  vs  ${d.dep.padEnd(40)}  ${d.syms.length} 个`);
    }
    for (const d of found.slice(0, 3)) {
      console.log(`\n--- ${d.node}  vs  ${d.dep}（前 25）---`);
      for (const s of d.syms.slice(0, 25)) console.log('   ', s);
    }
    if (known.length) {
      console.log('\n== 其中命中已知重复白名单（不作为闸门失败）==');
      for (const d of known) {
        console.log(`  ${d.node} vs ${d.dep}  ${d.syms.length} 个  `
          + `← ${isKnownDuplicate(d.node, d.dep)[0]}`);
      }
    }
  }

  if (opts.json) {
    const toArr = (m) => {
      const o = {};
      for (const k of Object.keys(m)) o[k] = Array.from(m[k]).sort();
      return o;
    };
    fs.writeFileSync(opts.json, JSON.stringify({
      tool,
      platform: process.platform,
      node_libs: toArr(nodeLibs),
      dep_libs: toArr(depLibs),
      duplicates: unknown,
      known_duplicates: known.map((d) => ({
        ...d,
        why: isKnownDuplicate(d.node, d.dep)[0],
      })),
    }, null, 1));
    console.log(`\nJSON 写入 ${opts.json}`);
  }

  if (opts.failOnDuplicates && unknown.length) {
    console.error(`\n发现 ${unknown.length} 组白名单之外的跨库重复强符号`
      + `（--fail-on-duplicates；另有 ${known.length} 组命中已知白名单）`);
    return 1;
  }
  return 0;
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}
