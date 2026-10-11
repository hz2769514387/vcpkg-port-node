#!/usr/bin/env python3
"""生成（或校验）vcpkg 版本表里那个 <port> 的 git-tree。

## git-tree 是什么

vcpkg 的 `versions/<首字母>-/<port>.json` 里每一条版本记录都带一个 `git-tree`：

    { "version": "24.21.0", "git-tree": "73f5edbf08874aa57cb3bcbfb4e295ccebbf8b8c" }

它**不是** commit id，而是 **`ports/<port>` 这个目录的 Git tree 对象哈希** ——
即"该目录下所有文件的路径 + 内容"按 Git 的 tree 编码算出来的指纹。等价于：

    git rev-parse HEAD:ports/node

作用：registry 靠它把"某个版本号"钉死到"一份确切的 port 内容"。改了 port 里任何一个
字节（哪怕只加一行注释），git-tree 就变 —— 版本表必须同步，否则 registry / 校验认为
版本表与实际内容不符。

## 为什么要有这个脚本

手工维护这个值每次都要 `git rev-parse HEAD:ports/node`，且必须**在提交之后**跑（因为
HEAD 得先包含改动）。漏一次，CI 的 lint 就红一次（2026-10-11 就是这么红的）。

这个脚本的做法与 vcpkg 官方 `x-add-version` 同构，但**不需要先提交**：
把当前**工作区**的 ports/<port> 放进一个临时索引，`git write-tree` 得到哈希。
只要随后提交的内容就是当前工作区的内容，算出来的值就会与 `git rev-parse HEAD:ports/node`
一致。

关键点：它显式带上 `core.autocrlf=false`，与 vcpkg 官方一致 —— 这样哈希只取决于
".gitattributes 归一化之后的内容"，与跑脚本那台机器的 git 配置无关。配合仓库的
`.gitattributes`（`* text=auto eol=lf`），任何机器算出的值都相同。

## 用法

    # 写入（改完 ports/<port> 之后、提交之前跑）
    python3 tools/version_tree.py

    # 只校验，不一致就退出码 1（CI lint 与本地自检都用这个）
    python3 tools/version_tree.py --check

    # 看看会算出什么，不落盘
    python3 tools/version_tree.py --print
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile


def _git(args, *, cwd, env=None, check=True):
    """跑一条 git 命令，返回 stdout（已按文本处理，不做 EOL 转换）。"""
    proc = subprocess.run(
        ["git", *args],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and proc.returncode != 0:
        sys.stderr.write(
            "git %s 失败（rc=%d）：\n%s%s\n"
            % (" ".join(args), proc.returncode, proc.stdout, proc.stderr)
        )
        raise SystemExit(2)
    return proc.stdout.strip()


def repo_root(cwd):
    return _git(["rev-parse", "--show-toplevel"], cwd=cwd)


def compute_git_tree(root, port_rel, port_dir_rel):
    """把工作区的 port 目录放进临时索引，取出**该目录自己的** tree 哈希。

    port_rel     ：相对仓库根的 port 目录（如 ports/node）
    port_dir_rel ：传给 `git add` 的 pathspec（本脚本里与 port_rel 相同）

    注意：`git write-tree` 给出的是**整个仓库根目录**的 tree 对象，必须再
    `rev-parse <root-tree>:ports/node` 才能拿到 port 目录那一层的 tree ——
    后者才是 vcpkg 版本表里的 git-tree（等价于 `git rev-parse HEAD:ports/node`）。
    """
    with tempfile.TemporaryDirectory(prefix="vcpkg-version-tree-") as tmp:
        env = os.environ.copy()
        env["GIT_INDEX_FILE"] = os.path.join(tmp, "index")
        # 与 vcpkg 官方一致：哈希只反映"归一化后的内容"，不受本机 git 配置影响。
        env["GIT_CONFIG_COUNT"] = "2"
        env["GIT_CONFIG_KEY_0"] = "core.autocrlf"
        env["GIT_CONFIG_VALUE_0"] = "false"
        env["GIT_CONFIG_KEY_1"] = "core.safecrlf"
        env["GIT_CONFIG_VALUE_1"] = "false"

        head = _git(["rev-parse", "--verify", "--quiet", "HEAD"], cwd=root, check=False)
        if head:
            _git(["read-tree", "HEAD"], cwd=root, env=env)
        else:
            # 还没有任何提交（unborn branch）：从空索引起步。
            _git(["read-tree", "--empty"], cwd=root, env=env)

        # --force：即使该路径被 .gitignore 命中也要收进来（port 目录绝不该被忽略）。
        _git(["add", "--force", "--", port_dir_rel], cwd=root, env=env)
        root_tree = _git(["write-tree"], cwd=root, env=env)

        # 取子树：这才是 ports/<port> 那一层的 tree 哈希。
        return _git(["rev-parse", "%s:%s" % (root_tree, port_rel)], cwd=root, env=env)


def versions_path(root, versions_root, port):
    # vcpkg 约定：versions/<首字符>-/<port>.json（例如 versions/n-/node.json）。
    return os.path.join(root, versions_root, port[0] + "-", port + ".json")


def load_manifest(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def entry_version(manifest):
    """从 port 的 vcpkg.json 取 version 字段（version / version-string / version-date…）。"""
    for key in ("version", "version-string", "version-semver", "version-date"):
        if key in manifest:
            out = {"version": manifest[key]}
            if "port-version" in manifest:
                out["port-version"] = manifest["port-version"]
            return out
    raise SystemExit("vcpkg.json 里找不到 version / version-string / … 字段")


def render(entries):
    return json.dumps({"versions": entries}, indent=2, ensure_ascii=False) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="生成/校验 vcpkg 版本表里 <port> 的 git-tree（ports/<port> 的 tree 哈希）"
    )
    ap.add_argument("--port", default="node", help="port 名（默认 node）")
    ap.add_argument("--ports-root", default="ports", help="port 目录的父目录（默认 ports）")
    ap.add_argument("--versions-root", default="versions", help="versions 目录（默认 versions）")
    ap.add_argument(
        "--check",
        action="store_true",
        help="只校验：与版本表不一致时打印差异并以退出码 1 结束",
    )
    ap.add_argument("--print", dest="do_print", action="store_true", help="只打印哈希，不落盘")
    ap.add_argument("--cwd", default=os.getcwd(), help="仓库内的任意目录（默认当前目录）")
    args = ap.parse_args(argv)

    root = repo_root(args.cwd)
    # git 的 pathspec 与 tree 里的路径**一律用正斜杠**（Windows 上 os.path.join 会给反斜杠，
    # 那样 `rev-parse <tree>:ports\node` 会直接报 path not found）。
    port_rel = "/".join(p.strip("/") for p in (args.ports_root, args.port) if p.strip("/"))
    port_abs = os.path.join(root, *port_rel.split("/"))
    if not os.path.isdir(port_abs):
        raise SystemExit("找不到 port 目录：%s" % port_abs)

    manifest = load_manifest(os.path.join(port_abs, "vcpkg.json"))
    tree = compute_git_tree(root, port_rel, port_rel)
    vfile = versions_path(root, args.versions_root, args.port)

    if args.do_print:
        print(tree)
        return 0

    if args.check:
        if not os.path.isfile(vfile):
            sys.stderr.write("::error:: 缺版本表文件：%s\n" % vfile)
            return 1
        entries = load_manifest(vfile).get("versions", [])
        want = entry_version(manifest)
        matches = [
            e
            for e in entries
            if e.get("version") == want["version"]
            and e.get("port-version", 0) == want.get("port-version", 0)
        ]
        if not matches:
            sys.stderr.write(
                "::error:: %s 里没有 version=%s 的条目\n" % (vfile, want["version"])
            )
            return 1
        recorded = matches[0].get("git-tree")
        if recorded != tree:
            sys.stderr.write(
                "::error:: %s 的 git-tree 与 %s 的实际内容不一致\n"
                "  记录值：%s\n"
                "  实际值：%s\n"
                "  修法：python3 tools/version_tree.py\n"
                % (vfile, port_rel, recorded, tree)
            )
            return 1
        print("git-tree 一致：%s (%s)" % (tree, port_rel))
        return 0

    # 写入模式
    if os.path.isfile(vfile):
        entries = load_manifest(vfile).get("versions", [])
    else:
        entries = []
    want = entry_version(manifest)
    updated = False
    for e in entries:
        if e.get("version") == want["version"] and e.get(
            "port-version", 0
        ) == want.get("port-version", 0):
            if e.get("git-tree") != tree:
                e["git-tree"] = tree
                updated = True
            break
    else:
        entries.insert(0, {**want, "git-tree": tree})
        updated = True

    os.makedirs(os.path.dirname(vfile), exist_ok=True)
    with open(vfile, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(render(entries))
    print(
        "%s %s  version=%s  git-tree=%s"
        % (
            "已更新" if updated else "无需改动",
            os.path.relpath(vfile, root).replace(os.sep, "/"),
            want["version"],
            tree,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
