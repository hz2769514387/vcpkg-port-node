#!/usr/bin/env node
// Does every archive we ship use one CRT, and the one this build asks for?
//
// The executable case (check_crt.cmake) reads an import table, which only says what the final link
// resolved to. This one reads the archives the link consumed: every object in them carries a
// `/DEFAULTLIB:LIBCMT` or `/DEFAULTLIB:LIBCMTD` directive naming the static CRT it was compiled
// against, or `MSVCRT` for the dynamic one, and a *mixed* archive is the fingerprint of exactly the
// defect that produced LNK4098 on the host tools - a release archive reaching a Debug link because the
// release library directory was still on the search path.
//
// "It links" cannot see that: the linker picks one definition and warns, or does not even warn when
// the two variants do not collide by name. The bytes can.
//
// Usage:
//   node check_libnode_crt.mjs --expect static|dynamic --lib <path> [--lib <path> ...]
//
// Exit status: 0 when every archive is consistent and matches, 1 otherwise.

import { open } from 'node:fs/promises';
import { statSync } from 'node:fs';

const CHUNK = 8 * 1024 * 1024;               // archives reach 2 GB; never read one whole
const OVERLAP = 64;                          // so a marker spanning two chunks is still found

function parseArgs(argv) {
  const out = { expect: null, libs: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--expect') out.expect = argv[++i];
    else if (argv[i] === '--lib') out.libs.push(argv[++i]);
    else throw new Error(`check_libnode_crt: unknown argument ${argv[i]}`);
  }
  if (!['static', 'dynamic'].includes(out.expect)) throw new Error('--expect static|dynamic is required');
  if (out.libs.length === 0) throw new Error('--lib is required at least once');
  return out;
}

async function countMarkers(path) {
  const counts = { libcmt: 0, libcmtd: 0, msvcrt: 0, msvcrtd: 0 };
  const fh = await open(path, 'r');
  try {
    let carry = Buffer.alloc(0);
    const buf = Buffer.alloc(CHUNK);
    for (;;) {
      const { bytesRead } = await fh.read(buf, 0, CHUNK, null);
      if (bytesRead === 0) break;
      const window = Buffer.concat([carry, buf.subarray(0, bytesRead)]);
      // MSVC's cl.exe writes `/DEFAULTLIB:LIBCMT` and clang-cl writes `/DEFAULTLIB:libcmt.lib`;
      // lowercasing once is cheaper than carrying both spellings, and the `.lib` suffix is optional in
      // the match because each longer name is a prefix of a shorter-looking one only up to the suffix.
      const text = window.toString('latin1').toLowerCase();
      const countOf = (needle) => {
        let n = 0;
        for (let at = text.indexOf(needle); at !== -1; at = text.indexOf(needle, at + 1)) n++;
        return n;
      };
      // libcmtd/msvcrtd are counted first: "defaultlib:libcmt" is a prefix of "defaultlib:libcmtd".
      const debugStatic = countOf('defaultlib:libcmtd');
      const debugDynamic = countOf('defaultlib:msvcrtd');
      counts.libcmtd += debugStatic;
      counts.libcmt += countOf('defaultlib:libcmt') - debugStatic;
      counts.msvcrtd += debugDynamic;
      counts.msvcrt += countOf('defaultlib:msvcrt') - debugDynamic;
      carry = window.subarray(Math.max(0, window.length - OVERLAP));
    }
  } finally {
    await fh.close();
  }
  return counts;
}

// Three outcomes, not two: an archive can *say nothing* about the runtime library, and that is
// legitimate - `node.lib` is the import library for node.exe, host-tool archives such as `torque.lib`
// carry objects that pull in no runtime, and a resource-only archive names nothing either. Failing on
// silence would make the case红 for being unable to answer, which is the opposite of useful.
//
//   mixed    -> one archive names both CRTs: the defect this case exists for
//   mismatch -> names the other one consistently: the build and the archive disagree
//   ok       -> names the expected one
//   silent   -> names none; counted, not failed
function verdict(counts, expect) {
  const staticCrt = counts.libcmt + counts.libcmtd;
  const dynamicCrt = counts.msvcrt + counts.msvcrtd;
  if (staticCrt > 0 && dynamicCrt > 0) {
    return ['mixed', `mixes the static CRT (${staticCrt} directives) with the dynamic one ` +
                     `(${dynamicCrt}) - some object in this archive was compiled for the other ` +
                     `runtime library`];
  }
  if (staticCrt === 0 && dynamicCrt === 0) return ['silent', null];
  if (expect === 'static' && dynamicCrt > 0) {
    return ['mismatch', `uses the dynamic CRT (${dynamicCrt} msvcrt directives) where the build asks for static`];
  }
  if (expect === 'dynamic' && staticCrt > 0) {
    return ['mismatch', `uses the static CRT (${staticCrt} libcmt directives) where the build asks for dynamic`];
  }
  return ['ok', null];
}

const { expect, libs } = parseArgs(process.argv.slice(2));
let failures = 0;
let silent = 0;
for (const lib of libs) {
  statSync(lib);                                  // fails loudly on a bad path rather than silently
  const counts = await countMarkers(lib);
  const [outcome, problem] = verdict(counts, expect);
  const name = lib.replace(/^.*[\/]/, '');
  if (outcome === 'silent') {
    silent++;
    continue;
  }
  if (outcome === 'ok') continue;
  failures++;
  console.error(`check_libnode_crt: ${name} ${problem}`);
}
if (failures > 0) {
  console.error(`check_libnode_crt: ${failures} of ${libs.length} archive(s) failed`);
  process.exit(1);
}
console.log(`check_libnode_crt: ${libs.length - silent} archive(s) name the ${expect} CRT as expected; ` +
            `${silent} name none (import libraries and host-tool archives - nothing to check)`);
