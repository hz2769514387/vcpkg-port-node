#!/usr/bin/env node
// Symbol audit: are any strong symbols defined by more than one of the archives a
// consumer links?
//
// Why a separate check: "it links" cannot tell the difference. The linker silently
// picks one definition when two archives define the same strong symbol, so the second
// copy - and every future ODR violation it hides - stays invisible. This script makes
// that visible by scanning the port's own archives against the vcpkg archives they
// externalize, and fails when a strong symbol is defined twice.
//
// Why JS, run by the node this project just built (rather than a python script on the
// repo root):
//   * ctest runs C and JS; the toolchain should match.
//   * It doubles as a self-check: if the freshly built node can run this script, its
//     fs / child_process / Buffer are good.
//   * No second scripting runtime in the repo.
//
// Usage:
//   node symbol_check.js --node-lib-dir <dir> [--node-lib-dir <dir2> ...]
//                        --dep-root <vcpkg packages> --triplet <t>
//                        [--node-libs a.lib,b.lib,...] [--dumpbin <path>] [--nm <path>]
//                        [--json out.json] [--fail-on-duplicates]
//
//   --node-lib-dir: repeatable. node's libraries live in <prefix>/lib and
//     <prefix>/lib/manual-link (the latter holds the libraries that would collide if
//     installed into the common dir); both must be scanned.
//
//   --node-libs: treat ONLY these files as "node's libraries". Strongly recommended.
//     <prefix>/lib is shared by the whole manifest project, so it also holds libraries
//     the consumer declared (gtest, fmt, ...). Without this list the audit compares
//     those against same-named vcpkg packages and reports "self vs self" false
//     positives - a gate that is always red is no gate. node-config.cmake exports
//     node_INSTALLED_LIBRARIES, which is exactly this list.
//
//   --dumpbin / --nm: absolute path to the tool. The ctest process is not in vcvars,
//     so dumpbin is not on PATH; CMake resolves it at configure time and passes it in.
//
//   --fail-on-duplicates: exit 1 when a cross-archive strong duplicate is found (use as
//     a gate). Without it, just report and exit 0 (use as a survey tool).
//
// Method:
//   Extract each .lib/.a's defined symbols, keep only the strong ones (External and not
//   COMDAT, not weak), and intersect across archives. A non-empty intersection means two
//   archives define the same strong symbol.
//
// Why COMDAT / weak symbols are excluded:
//   COMDAT duplicates are by design (inline / template / MSVC string literals each carry
//   a copy; the linker folds by COMDAT). Same for weak symbols. The silent folding of
//   same-named COMDAT from different versions is the real hazard - no link error, runtime
//   picks one arbitrarily, version mismatch is unstable behaviour.
//
// Platform:
//   Windows -> dumpbin /symbols (COFF symbol table; COMDAT info is in
//              "Section length ... selection N")
//   others  -> nm -g --defined-only (type letter distinguishes strong/weak:
//              W/V/w/v weak, U undefined)
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const USAGE = `usage: node symbol_check.js --node-lib-dir <dir> [--node-lib-dir <dir> ...]
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
      // Repeatable: node's libraries may be split across <prefix>/lib and
      // <prefix>/lib/manual-link (the latter holds abseil/highway/etc. after the
      // collision-move step); both must be audited.
      opts.nodeLibDirs.push(argv[++i]);
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(need, a)) {
      opts[need[a]] = argv[++i];
      continue;
    }
    throw new Error(`unknown argument: ${a}\n${USAGE}`);
  }
  if (!opts.nodeLibDirs.length || !opts.depRoot || !opts.triplet) throw new Error(USAGE);
  return opts;
}

function run(cmd, args) {
  // dumpbin outputs in the host code page (GBK on Chinese Windows); we only care about
  // ASCII symbol names, so decode as latin1 to preserve bytes and avoid multi-byte
  // misalignment.
  return execFileSync(cmd, args, {
    encoding: 'latin1', maxBuffer: 256 * 1024 * 1024, timeout: 900000,
  });
}

// ---------------------------------------------------------------------------
// Windows: dumpbin /symbols
// ---------------------------------------------------------------------------

const RE_SECT_HEAD = /^\s*[0-9A-F]+\s+[0-9A-F]+\s+(SECT\S+)\s/;
const RE_SYM_LINE = /^\s*[0-9A-F]+\s+[0-9A-F]+\s+(SECT\S+)\s+.*?\s+(External|WeakExternal|Static)\s+\|\s*(\S+)/;
// selection 1 = NODUPLICATES (strong, the linker forbids a second definition - exactly
// what we want to find); selection 2-6 = COMDAT folds (pick any/associative/same size/
// exact match/largest). Capture the digit so the pass-1 loop can distinguish.
const RE_COMDAT = /selection\s+(\d)/;
// MSVC string-literal COMDAT: ??_C@_...@...?$AA@. Allowed to repeat across archives;
// without this exclusion the report is wall-to-wall false positives.
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

  // Pass 1: find which sections are COMDAT (selection >= 2). dumpbin emits two lines
  // per section,
  //   "F3F 00000000 SECT3BE notype  Static | .rdata"
  //   "      Section length 2A0, ..., selection 2 (pick any)"
  // The second line has no SECT number, so scan in order and remember the last section.
  // selection 1 (NODUPLICATES) is NOT COMDAT - it is a strong definition the linker
  // refuses to fold, which is exactly the case this audit is looking for.
  const comdat = new Set();
  let lastSect = null;
  for (const line of lines) {
    if (line.indexOf('Section length') >= 0) {
      const m = RE_COMDAT.exec(line);
      if (m && lastSect && parseInt(m[1], 10) >= 2) comdat.add(lastSect);
      continue;
    }
    const m = RE_SECT_HEAD.exec(line);
    if (m) lastSect = m[1];
  }

  // Pass 2: collect External strong symbols.
  const strong = new Set();
  for (const line of lines) {
    const m = RE_SYM_LINE.exec(line);
    if (!m) continue;
    const [, sect, bind, name] = m;
    if (bind !== 'External') continue;
    if (comdat.has(sect)) continue;      // COMDAT: allowed to repeat
    if (name.startsWith('.')) continue;  // section name / internal symbol
    if (RE_STRING_LITERAL.test(name)) continue;
    strong.add(name);
  }
  return { syms: strong, err: null };
}

// ---------------------------------------------------------------------------
// Other platforms: nm
// ---------------------------------------------------------------------------
// nm lines look like "0000000000000000 T name", with "member.o:" headers before each
// archive member. -g shows external symbols only, --defined-only drops undefined.
// Type letters: A B D G R S T defined global (strong); W V w v weak; U undefined;
// u unique global; i ifunc.
const RE_NM = /^\s*[0-9A-Fa-f]*\s+([A-Za-z])\s+(\S+)\s*$/;
const NM_WEAK = new Set(['W', 'V', 'w', 'v', 'U', 'u', 'i']);

// On ELF/MachO, C++ standard library template instantiations and compiler support
// routines are emitted as strong (T) symbols in every translation unit that uses them,
// and the linker folds them by COMDAT equivalence (the Itanium ABI's vague linkage).
// nm has no way to see that folding, so without this filter every archive pair that
// both instantiate std::basic_string<...> reports a wall of false positives - exactly
// the case dumpbin on Windows handles via the COMDAT selection in the COFF table.
//
// Patterns (Itanium ABI mangling):
//   __ZNSt...   / __ZNKSt...   - std:: members (libc++: St3__1, libstdc++: St)
//   __ZSt...                   - std:: free functions
//   __ZTI...St / __ZTS...St / __ZTV...St - typeinfo/string/vtable for std:: types
//   ___clang_call_terminate    - clang's terminate landing pad
// We only filter std:: here; a real ODR violation between two versions of abseil or
// highway shows up as a non-std:: symbol and is still a finding.
function isStdLibInstantiation(name) {
  if (name.startsWith('__ZNSt') || name.startsWith('__ZNKSt')) return true;
  if (name.startsWith('__ZSt')) return true;
  if (name.startsWith('__ZTI') || name.startsWith('__ZTS') || name.startsWith('__ZTV')) {
    // typeinfo / typeinfo name / vtable for a std:: type: __ZTVNSt...
    return name.indexOf('NSt') >= 0;
  }
  if (name === '___clang_call_terminate') return true;
  return false;
}

function nmSymbols(lib, nm) {
  let out;
  try {
    out = run(nm, ['-g', '--defined-only', lib]);
  } catch (e) {
    // macOS nm does not accept --defined-only long form; fall back to -g and filter.
    try {
      out = run(nm, ['-g', lib]);
    } catch (e2) {
      return { syms: null, err: String(e2 && e2.message ? e2.message : e2) };
    }
  }
  const strong = new Set();
  for (const line of out.split(/\r?\n/)) {
    if (!line || line.endsWith(':')) continue;  // archive member header
    const m = RE_NM.exec(line);
    if (!m) continue;
    const [, type, name] = m;
    if (NM_WEAK.has(type)) continue;
    if (name.startsWith('.')) continue;
    if (isStdLibInstantiation(name)) continue;
    strong.add(name);
  }
  return { syms: strong, err: null };
}

// ---------------------------------------------------------------------------
// Known-duplicate allowlist
// ---------------------------------------------------------------------------
// V8 carries private copies of abseil / highway inside deps/v8/third_party, and vcpkg
// provides same-named libraries - the two copies' strong symbols are cross-archive
// duplicates on ELF/MachO (nm reports them as strong; on Windows the same duplicates
// are COMDAT and so read as weak, so the Windows gate is naturally green while Linux/macOS
// goes red - same root cause, opposite conclusion per platform). This is a documented
// known limitation.
//
// The allowlist matches by library file stem (directory and extension stripped). A dep
// entry ending in '*' is a prefix glob. Allowlisted duplicates are still reported (placed
// in known_duplicates, included in JSON) but do not trigger --fail-on-duplicates -
// any duplicate OUTSIDE the allowlist is still red.
const KNOWN_DUPLICATES = [
  {
    node: 'abseil',
    dep: ['absl_*'],
    why: 'v8 vendored abseil vs vcpkg abseil (two copies of the same third-party lib, known limitation)',
  },
  {
    node: 'highway',
    dep: ['hwy', 'hwy_*'],
    why: 'v8 vendored highway vs vcpkg highway / libhwy (same as above, known limitation)',
  },
];

function libStem(file) {
  let s = file.replace(/\.(lib|a)$/i, '').replace(/^.*[\\/]/, '');
  // POSIX libraries carry a lib prefix (libabseil.a), Windows does not (abseil.lib) -
  // strip it so both sides land on the same name. Don't strip when only "lib" remains.
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
  // With --node-libs, only accept files on the list (recommended); without it, scan the
  // whole directory and flag in the report that this produces "self vs self" positives.
  let names = null;
  if (opts.nodeLibs) {
    names = opts.nodeLibs.split(',').map((s) => s.trim()).filter(Boolean);
    console.log(`node side: taking only the ${names.length} libraries on the list (node_INSTALLED_LIBRARIES)`);
  } else {
    console.log('warning: --node-libs not given; node side will scan the whole lib dir; '
      + '<prefix>/lib is shared and will pick up the consumer\'s own libraries, producing "self vs self" false positives.');
  }
  for (const dir of opts.nodeLibDirs) {
    if (!fs.existsSync(dir)) continue;  // manual-link may not exist (no collision libs)
    for (const f of fs.readdirSync(dir).sort()) {
      if (!f.toLowerCase().endsWith(ext)) continue;
      if (names && names.indexOf(f) < 0) continue;
      if (Object.prototype.hasOwnProperty.call(nodeLibs, f)) continue;  // dedupe across dirs
      const { syms, err } = read(path.join(dir, f));
      if (syms) nodeLibs[f] = syms;
      else console.error(`  ! ${f}: ${err}`);
    }
  }
  if (names) {
    // Missing check must run after ALL dirs are scanned - a library may live only in
    // manual-link; reporting it missing after the first dir would be a false alarm.
    const missing = names.filter((n) => !Object.prototype.hasOwnProperty.call(nodeLibs, n));
    if (missing.length) {
      console.error(`  ! ${missing.length} libraries on the list not found in ${opts.nodeLibDirs.join(' / ')}: `
        + `${missing.join(', ')}`);
    }
  }

  const depLibs = {};
  // This port itself also appears in packages (overlay ports get built into
  // packages/node_<triplet>/). Without excluding it, node's libraries appear on BOTH
  // sides and it becomes "self vs self" again - measured at 10 groups, the largest being
  // v8_base_without_compiler.lib vs node_x64-.../v8_base_without_compiler.lib at 260 syms.
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
  console.log(`symbol tool: ${tool}`);
  console.log(`== node libraries: ${Object.keys(nodeLibs).length} (strong symbols total ${total(nodeLibs)}) ==`);
  for (const k of Object.keys(nodeLibs).sort((a, b) => nodeLibs[b].size - nodeLibs[a].size)) {
    console.log(`   ${k.padEnd(46)} ${String(nodeLibs[k].size).padStart(6)} strong symbols`);
  }
  console.log('');
  console.log(`== vcpkg dependency libraries: ${Object.keys(depLibs).length} (strong symbols total ${total(depLibs)}) ==`);
  for (const k of Object.keys(depLibs).sort((a, b) => depLibs[b].size - depLibs[a].size)) {
    console.log(`   ${k.padEnd(46)} ${String(depLibs[k].size).padStart(6)} strong symbols`);
  }

  if (skippedSelf) {
    console.log(`(excluded this port's own packages/${selfPkg} - otherwise node's libs appear on both sides)`);
  }

  console.log('');
  console.log('== cross-archive duplicate strong symbols ==');
  const found = [];
  for (const nl of Object.keys(nodeLibs)) {
    for (const dl of Object.keys(depLibs)) {
      const common = [];
      for (const s of nodeLibs[nl]) if (depLibs[dl].has(s)) common.push(s);
      if (common.length) found.push({ node: nl, dep: dl, syms: common.sort() });
    }
  }
  // Split by allowlist: only duplicates OUTSIDE the allowlist trigger --fail-on-duplicates.
  const unknown = [];
  const known = [];
  for (const d of found) {
    (isKnownDuplicate(d.node, d.dep).length ? known : unknown).push(d);
  }
  if (!found.length) {
    console.log('(none)');
  } else {
    found.sort((a, b) => b.syms.length - a.syms.length);
    for (const d of found) {
      console.log(`  ${d.node.padEnd(40)}  vs  ${d.dep.padEnd(40)}  ${d.syms.length} syms`);
    }
    for (const d of found.slice(0, 3)) {
      console.log(`\n--- ${d.node}  vs  ${d.dep} (first 25) ---`);
      for (const s of d.syms.slice(0, 25)) console.log('   ', s);
    }
    if (known.length) {
      console.log('\n== of which on the known-duplicate allowlist (not a gate failure) ==');
      for (const d of known) {
        console.log(`  ${d.node} vs ${d.dep}  ${d.syms.length} syms  `
          + `<= ${isKnownDuplicate(d.node, d.dep)[0]}`);
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
    console.log(`\nJSON written to ${opts.json}`);
  }

  if (opts.failOnDuplicates && unknown.length) {
    console.error(`\nFound ${unknown.length} cross-archive strong duplicate group(s) outside the allowlist`
      + ` (--fail-on-duplicates; ${known.length} group(s) on the known-duplicate allowlist)`);
    return 1;
  }
  return 0;
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}
