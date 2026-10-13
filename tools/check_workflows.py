# Gate for .github/workflows/*.yml.
#
# Why this exists (it cost a whole push on 2026-10-14): the CI was split into
# lint/debug/release + one shared `platform.yml` (on: workflow_call).  A stray
# duplicate `continue-on-error` key made GitHub reject BOTH files at load time --
# every run failed in 0 seconds with "Invalid workflow file", no job ever started.
# Most YAML parsers (including PyYAML) silently keep the LAST duplicate key, so a
# plain `yaml.safe_load()` check would have passed.  This gate therefore:
#   1) fails on **duplicate mapping keys anywhere** in the file (custom loader);
#   2) cross-checks reusable-workflow inputs (declared vs referenced) and
#      caller `with:` keys / matrix fields / `uses:` targets.
#
# Usage:
#   python3 tools/check_workflows.py --self-test    # prove the gate can bite
#   python3 tools/check_workflows.py                # check the repo
import argparse
import os
import pathlib
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - environment problem, not a repo problem
    sys.stderr.write('需要 pyyaml：python3 -m pip install pyyaml\n')
    raise SystemExit(2)

WF_DIR = pathlib.Path(__file__).resolve().parent.parent / '.github' / 'workflows'


class DuplicateKeyDetector(yaml.SafeLoader):
    """SafeLoader that raises on duplicate mapping keys (GitHub treats them as fatal)."""


def _construct_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.YAMLError(
                'duplicate key %r at line %s, column %s (GitHub 会判成非法 workflow；'
                '多数 YAML 解析器只保留最后一份，所以不能靠普通解析发现)'
                % (key, node.start_mark.line + 1, node.start_mark.column + 1))
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


DuplicateKeyDetector.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


def load(path):
    return yaml.load(path.read_text(encoding='utf-8'), Loader=DuplicateKeyDetector)


def triggers(doc):
    # YAML 1.1 parses the `on:` key as boolean True.
    return doc.get('on', doc.get(True))


def referenced_inputs(text):
    import re
    return {m.group(1) for m in re.finditer(r'inputs\.([A-Za-z0-9_-]+)', text)}


def check_file(path, problems, all_docs):
    text = path.read_text(encoding='utf-8')
    try:
        doc = load(path)
    except yaml.YAMLError as exc:
        problems.append('%s: YAML 解析失败：%s' % (path.name, exc))
        return
    all_docs[path.name] = doc
    if not doc or 'jobs' not in doc:
        problems.append('%s: 没有 jobs' % path.name)
        return
    trg = triggers(doc)
    if trg is None:
        problems.append('%s: 没有 on: 触发条件' % path.name)
        return

    is_reusable = isinstance(trg, dict) and 'workflow_call' in trg
    if is_reusable:
        declared = set((trg.get('workflow_call') or {}).get('inputs') or {})
        used = referenced_inputs(text)
        missing = sorted(used - declared)
        if missing:
            problems.append('%s: 作业体引用了未声明的 inputs: %s' % (path.name, missing))
        unused = sorted(declared - used)
        if unused:
            problems.append('%s: 声明了但没人用的 inputs: %s（删掉或让它有意义）' % (path.name, unused))

    for job_id, job in doc['jobs'].items():
        if not isinstance(job, dict):
            continue
        if 'uses' in job and 'steps' in job:
            problems.append('%s: 作业 %s 同时有 uses: 与 steps:（只能二选一）' % (path.name, job_id))
        if 'uses' in job:
            ref = job['uses']
            if ref.startswith('./'):
                target = (WF_DIR.parent.parent / ref[2:].split('@')[0]).resolve()
                if not target.exists():
                    problems.append('%s: 作业 %s 引用的 %s 不存在' % (path.name, job_id, ref))
                else:
                    try:
                        tdoc = load(target)
                    except yaml.YAMLError as exc:
                        problems.append('%s: 作业 %s 依赖的 %s 解析失败：%s'
                                        % (path.name, job_id, ref, exc))
                        continue
                    ttrg = triggers(tdoc)
                    if not (isinstance(ttrg, dict) and 'workflow_call' in ttrg):
                        problems.append('%s: %s 不是 workflow_call 作业体' % (path.name, ref))
                    else:
                        declared = set((ttrg.get('workflow_call') or {}).get('inputs') or {})
                        given = set(job.get('with') or {})
                        unknown = sorted(given - declared)
                        if unknown:
                            problems.append('%s: 作业 %s 的 with: 有未声明的键 %s' % (path.name, job_id, unknown))
                        legs = ((job.get('strategy') or {}).get('matrix') or {}).get('include') or []
                        if legs:
                            keys = {k for leg in legs for k in leg}
                            for key in sorted(given):
                                value = str(job['with'][key])
                                if 'matrix.' in value:
                                    field = value.split('matrix.', 1)[1].rstrip(' }').split()[0]
                                    if field not in keys:
                                        problems.append('%s: 矩阵缺少字段 %s' % (path.name, field))


def check_all():
    problems = []
    docs = {}
    files = sorted(WF_DIR.glob('*.yml'))
    if not files:
        return ['workflows 目录里没有 yml']
    for f in files:
        check_file(f, problems, docs)
    # 每个 workflow 都应该有个好认的名字（GH 在文件加载失败时会显示文件路径而非 name）
    for name, doc in docs.items():
        if not doc.get('name'):
            problems.append('%s: 缺 name:' % name)
    return problems


def self_test():
    import tempfile
    global WF_DIR
    saved = WF_DIR
    ok = True
    try:
        tmp = pathlib.Path(tempfile.mkdtemp(prefix='wfselftest-'))
        WF_DIR = tmp
        good = tmp / 'good.yml'
        good.write_text('name: g\non:\n  workflow_call:\n    inputs:\n'
                        '      a: { required: true, type: string }\n'
                        'jobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ${{ inputs.a }}\n',
                        encoding='utf-8')
        problems = check_all()
        if problems:
            print('自测失败（好文件应当无问题）：', problems)
            ok = False
        bad = tmp / 'bad.yml'
        bad.write_text('name: b\non:\n  push:\njobs:\n  j:\n    runs-on: ubuntu-latest\n'
                       '    continue-on-error: true\n    continue-on-error: false\n', encoding='utf-8')
        problems = check_all()
        if not any('duplicate key' in p for p in problems):
            print('自测失败（重复键必须被抓到）：', problems)
            ok = False
        else:
            print('自测：重复键被抓到 ✓')
        bad.unlink()
        bad2 = tmp / 'bad2.yml'
        bad2.write_text('name: b2\non:\n  push:\njobs:\n  j:\n    uses: ./.github/workflows/nope.yml\n',
                        encoding='utf-8')
        problems = check_all()
        if not any('不存在' in p for p in problems):
            print('自测失败（不存在的被调 workflow 必须被抓到）：', problems)
            ok = False
        else:
            print('自测：缺失的被调 workflow 被抓到 ✓')
    finally:
        WF_DIR = saved
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--self-test', action='store_true')
    args = ap.parse_args()
    if args.self_test:
        ok = self_test()
        print('自测通过' if ok else '自测未通过')
        raise SystemExit(0 if ok else 1)
    problems = check_all()
    if problems:
        for p in problems:
            print('::error::' + p)
        raise SystemExit(1)
    print('workflows 检查通过（%d 个文件）' % len(list(WF_DIR.glob('*.yml'))))


if __name__ == '__main__':
    main()
