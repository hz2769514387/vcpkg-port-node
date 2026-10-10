#!/usr/bin/env python3
# gyp2vcpkg —— 把 **node 的 gyp 工程**翻成 CMake 片段的独立小工具。
#
# 它只提供"能力"，**不认识调用方是谁**：不写死任何项目专有的变量名、不写死调用方的
# 目录、不往调用方的工程里塞 CMake 逻辑。产物只有一种 —— 一堆只 `set()` 变量的
# .cmake 片段；怎么把这些变量变成目标（`add_library` / `add_custom_command`）是
# 调用方自己的事。调用方用一份**自己的**配置文件（--config）告诉它：解析哪棵树、
# 要哪些目标/动作、生成的片段里该用什么变量名。
#
# 三步管线（为什么要分三步，见调研 `gyp 规则与现成解析器` / `FeCompilerOptions 去向…`）：
#   1. resolve ：用 **node 自带的 gyp**（gyp-next 0.22.2）解析 .gyp → gyp_resolved.json
#                 —— 不自写解析器：条件求值、dependent settings、命令展开、late 变量
#                 全由 gyp 自己做完，拿到的是最终、完整、正确的结果。
#   2. collect ：收成编译配置数据集（路径归一，只留建 CMake 要用的字段）。
#   3. generate：把数据集翻成 CMake 片段（只做"gyp 的写法 → CMake 的写法"）。
#
# 用法：
#   python <本目录>/gyp2vcpkg.py all      --config <调用方的配置.json> \
#                                         --env <label>=<变量环境.json> [--env ...]
#   python <本目录>/gyp2vcpkg.py resolve  --config ... --env ...   # 只跑到第 1 步
#   python <本目录>/gyp2vcpkg.py collect  --config ... --env ...   # 只跑到第 2 步
#   python <本目录>/gyp2vcpkg.py generate --config ... --env ...   # 只跑到第 3 步
#   python <本目录>/gyp2vcpkg.py diff     --config ... --env ...   # 与已入库的片段粗比对
#   python <本目录>/gyp2vcpkg.py check    --config ... --env ...   # 产物新不新鲜（退出码 0/1；给 bootstrap 用）
#
# 变量环境（`--env`，可重复）：`<label>=<路径>` 把某平台的 `process.config` 文件指给解析器。
# 配置里**不再写死 env 路径** —— 那份数据由调用方（bootstrap 前置步）产出并传进来，
# 路径按"当前工作目录"记（调用方总是在自己的工程根上跑）。
#
# 其它选项：--node-root <path>（覆盖配置里的 node_root）
#           --out <dir>（覆盖输出目录）  --work <dir>（覆盖中间产物目录）
#
# 配置文件的每个字段见同目录 `example.json`。

import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# 指纹要对账的产品文件（改了它们而产物没重新生成 = 过期）
PRODUCT_FILES = ["resolve.py", "collect.py", "generate.py", "_dump_generator.py"]


def product_path(name):
    return os.path.join(HERE, name)


def sha16(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:16]


def _expand_all(node, here):
    """配置里的 `{{here}}` 展开成配置文件所在目录（绝对路径）。"""
    if isinstance(node, dict):
        return {k: _expand_all(v, here) for k, v in node.items()}
    if isinstance(node, list):
        return [_expand_all(v, here) for v in node]
    if isinstance(node, str) and "{{here}}" in node:
        return node.replace("{{here}}", here)
    return node


def _as_dir(v):
    return v if isinstance(v, str) else None


def load_config(opts):
    path = opts.get("config")
    path = os.path.abspath(path if isinstance(path, str) else os.path.join(HERE, "example.json"))
    here = os.path.dirname(path).replace("\\", "/")
    with open(path, encoding="utf-8") as f:
        cfg = _expand_all(json.load(f), here)

    nr = _as_dir(opts.get("node-root")) or cfg["node_root"]
    cfg["_node_root"] = os.path.abspath(nr if os.path.isabs(nr) else os.path.join(here, nr))
    cfg["_config_path"] = path
    cfg["_out_dir"] = os.path.abspath(_as_dir(opts.get("out")) or cfg["out_dir"])
    cfg["_work_dir"] = os.path.abspath(_as_dir(opts.get("work")) or cfg["work_dir"])

    # `--env <label>=<路径>`（可重复）：把各平台的变量环境指进来。配置里**不再写死** env
    # 路径 —— 那份数据由调用方（bootstrap 前置步）产出，路径按"当前工作目录"记，
    # 也照这个样子写进文件头指纹（调用方照着对账）。
    #
    # **平台是"按 --env 激活"的**：只有给了 `--env <label>=…` 的平台才会参与本次生成。
    # 这样同一份配置（含 win/linux/mac）既能在一台只有 win/linux 环境的机器上生成
    # 两平台片段，也能在三平台环境齐备时生成三平台片段 —— 产物里的变量后缀随激活集变化。
    for spec in (opts.get("env") or []):
        if "=" not in spec:
            raise SystemExit("--env 要写成 <label>=<路径>，给的是：%s" % spec)
        label, env_path = spec.split("=", 1)
        hit = [p for p in cfg.get("platforms", []) if p.get("label") == label]
        if not hit:
            raise SystemExit("--env 的 label 不在配置的 platforms 里：%s" % label)
        hit[0]["env"] = env_path
    active = [p for p in cfg.get("platforms", []) if p.get("env")]
    if not active:
        raise SystemExit("没有任何平台拿到变量环境（用 --env <label>=<路径> 指一个）")
    cfg["platforms"] = active
    return cfg


def head_lines(cfg):
    """生成文件头（含指纹行：改了工具/配置/变量环境却没重生成，就能被发现）。"""
    # 相对于**当前工作目录**（调用方总是在自己的工程根上跑），裁判照着就能找到文件。
    base = os.getcwd()
    entries = [(os.path.relpath(product_path(f), base).replace("\\", "/"), product_path(f))
               for f in PRODUCT_FILES]
    entries.append((os.path.relpath(cfg["_config_path"], base).replace("\\", "/"),
                    cfg["_config_path"]))
    # 指纹行格式：`<路径> <sha256 前 16 位>`，一行一个 —— 调用方的裁判照这个格式对账。
    lines = ["#   指纹    ：%s %s" % (entries[0][0], sha16(entries[0][1]))]
    for rel, full in entries[1:]:
        lines.append("#             %s %s" % (rel, sha16(full)))
    for p in cfg["platforms"]:
        lines.append("#             %s %s" % (p["env"], sha16(p["env"])))
    return [
        "# 由 gyp2vcpkg 生成 —— 不要手改，改了会被判为过期。",
        "#   生成命令：python %s all --config %s"
        % (os.path.relpath(product_path("gyp2vcpkg.py"), os.getcwd()).replace("\\", "/"),
           os.path.relpath(cfg["_config_path"], os.getcwd()).replace("\\", "/")),
    ] + lines


def cmd_resolve(cfg, opts):
    sys.path.insert(0, HERE)
    from resolve import resolve
    for p in cfg["platforms"]:
        d = os.path.join(cfg["_work_dir"], p["label"])
        os.makedirs(d, exist_ok=True)
        # label 头一段就是 gyp 认的平台名（win / linux / mac），喂给 GetFlavor。
        f = resolve(cfg["_node_root"],
                    os.path.join(cfg["_node_root"], cfg["entry_gyp"]),
                    p["env"], d,
                    define_overrides=cfg.get("define_overrides"),
                    flavor=p["label"].split("-")[0])
        print("resolve %-5s → %s" % (p["label"], f))


def cmd_collect(cfg, opts):
    sys.path.insert(0, HERE)
    from collect import collect, write
    for p in cfg["platforms"]:
        resolved = os.path.join(cfg["_work_dir"], p["label"], "gyp_resolved.json")
        if not os.path.exists(resolved):
            print("缺 %s —— 先跑 resolve" % resolved)
            sys.exit(2)
        ds = collect(resolved, cfg["_node_root"], cfg, p)
        f = write(ds, cfg["_work_dir"], p["label"])
        print("collect %-5s → %s（%d 目标 / %d 动作）"
              % (p["label"], f, len(ds["targets"]), len(ds["actions"])))


def cmd_generate(cfg, opts):
    sys.path.insert(0, HERE)
    from generate import generate
    datasets = []
    for p in cfg["platforms"]:
        f = os.path.join(cfg["_work_dir"], "compile_config_%s.json" % p["label"])
        if not os.path.exists(f):
            print("缺 %s —— 先跑 collect" % f)
            sys.exit(2)
        with open(f, encoding="utf-8") as fh:
            datasets.append(json.load(fh))
    written = generate(datasets, cfg, cfg["_out_dir"], head_lines(cfg))
    print("generate → %s（%d 份）" % (cfg["_out_dir"], len(written)))


def cmd_diff(cfg, opts):
    """把刚生成的内容与已入库的片段粗比对（给人看，不是判据）。"""
    sys.path.insert(0, HERE)
    from generate import emit_target_file, emit_action_file
    datasets = []
    for p in cfg["platforms"]:
        with open(os.path.join(cfg["_work_dir"], "compile_config_%s.json" % p["label"]),
                  encoding="utf-8") as fh:
            datasets.append(json.load(fh))
    by = {d["platform"]: d for d in datasets}
    labels = [p["label"] for p in cfg["platforms"]]
    datas = [by[l] for l in labels]
    changed = []
    for name in cfg["targets"]:
        new = emit_target_file(name, datas, labels, head_lines(cfg), "", cfg)
        old_p = os.path.join(cfg["_out_dir"], "%s.cmake" % name)
        old = open(old_p, encoding="utf-8").read() if os.path.exists(old_p) else ""
        if _body(new) != _body(old):
            changed.append(name)
    for spec in cfg["actions"]:
        key = spec.get("name", spec["action"])
        new = emit_action_file(key, datas, labels, head_lines(cfg), "", cfg)
        if new is None:
            continue
        old_p = os.path.join(cfg["_out_dir"], "%s_action.cmake" % key)
        old = open(old_p, encoding="utf-8").read() if os.path.exists(old_p) else ""
        if _body(new) != _body(old):
            changed.append(key + "_action")
    print("有差异的片段：%d / %d" % (len(changed), len(cfg["targets"]) + len(cfg["actions"])))
    for c in changed:
        print("  " + c)


def _body(text):
    return "\n".join(l for l in text.split("\n") if not l.startswith("#"))


def _expected_outputs(cfg):
    files = ["%s.cmake" % n for n in cfg["targets"]]
    files += ["%s_action.cmake" % spec.get("name", spec["action"]) for spec in cfg["actions"]]
    return files


def cmd_check(cfg, opts):
    """产物**新不新鲜** —— 给调用方的 bootstrap 用（新鲜就跳过生成，保证重复运行无副作用）。

    判据两条，都要过：
      1. 该有的片段都在，且文件头是 gyp2vcpkg 写的（不是手改/残留）；
      2. 文件头那些指纹行（产品文件 / 调用方配置 / 变量环境）**逐个对得上当前磁盘上的值**。

    指纹行里的路径是**相对调用方工作目录**写的（生成时就是这么记的），所以这里也照这个
    口径读 —— 换句话说：**得在调用方仓库根跑**（bootstrap 就是这么跑的）。
    """
    out = cfg["_out_dir"]
    problems = []
    files = _expected_outputs(cfg)
    if not files:
        problems.append("配置里没点名任何 targets / actions —— 生成不出东西，检查配置")
    for f in files:
        p = os.path.join(out, f)
        if not os.path.exists(p):
            problems.append("缺 %s" % os.path.join(out, f))
            continue
        text = open(p, encoding="utf-8").read()
        if not text.startswith("# 由 gyp2vcpkg 生成"):
            problems.append("%s：不是 gyp2vcpkg 生成的（文件头不对，手改过？）" % p)
            continue
        n = 0
        for line in text.split("\n"):
            m = re.match(r"^\s*#\s+(\S+\.(?:py|json))\s+([0-9a-f]{16})\s*$", line)
            if not m:
                continue
            n += 1
            rel, want = m.group(1), m.group(2)
            if not os.path.exists(rel):
                problems.append("%s：指纹行里的 %s 不存在（换了目录 / 变量环境没搬过来？）" % (p, rel))
                continue
            now = sha16(rel)
            if now != want:
                problems.append("%s：%s 变了（%s → %s）" % (p, rel, want, now))
        if n < 3:
            problems.append("%s：只认出 %d 行指纹（文件头不完整？）" % (p, n))
        # **平台覆盖**：本次可用的每个平台，其变量环境都要出现在片段里 —— 缺了就说明
        # 产物是"更少平台"时生成的（最典型：刚补上 macOS 的变量环境，但入库的片段还是
        # 两平台的）。不判过期的话，patch 后的平台会拿到**空**的 `_SOURCES_<平台>`。
        for _p in cfg["platforms"]:
            if _p["env"] not in text:
                problems.append("%s：没覆盖平台 %s 的变量环境（%s）—— 产物过期"
                                % (p, _p["label"], _p["env"]))

    if problems:
        print("产物不新鲜（%d 处）：" % len(problems))
        for x in problems:
            print("  " + x)
        return 1
    print("产物是新鲜的：%d 份片段，指纹都对得上" % len(files))
    return 0


def parse_opts(args):
    o, i = {}, 0
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            key = a[2:]
            if i + 1 < len(args) and not args[i + 1].startswith("--"):
                val = args[i + 1]
                i += 2
            else:
                val = True
                i += 1
            # --env 可重复（每个平台一次），收成列表；其余选项是标量。
            if key == "env":
                o.setdefault("env", []).append(val)
            else:
                o[key] = val
        else:
            i += 1
    return o


def main():
    # Windows 的控制台/管道默认编码是 cp1252，打印 `→`（以及中文）会抛
    # UnicodeEncodeError —— CI 的 Windows job 上真这么崩过一次，直接把配置搞失败。
    # 把 stdout/stderr 定成 UTF-8，别再依赖控制台代码页。
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    cmd = args[0]
    opts = parse_opts(args[1:])
    cfg = load_config(opts)

    if cmd == "all":
        cmd_resolve(cfg, opts)
        cmd_collect(cfg, opts)
        cmd_generate(cfg, opts)
    elif cmd == "resolve":
        cmd_resolve(cfg, opts)
    elif cmd == "collect":
        cmd_collect(cfg, opts)
    elif cmd == "generate":
        cmd_generate(cfg, opts)
    elif cmd == "diff":
        cmd_diff(cfg, opts)
    elif cmd == "check":
        sys.exit(cmd_check(cfg, opts))
    else:
        print("未知命令：%s（支持 all / resolve / collect / generate / diff / check）" % cmd)
        sys.exit(2)


if __name__ == "__main__":
    main()
