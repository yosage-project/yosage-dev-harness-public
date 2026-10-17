#!/usr/bin/env python3
"""test/lib/bin-checks.py — test/suites/92-bin.sh が使う共有チェッカー。
配布 payload の一部ではない(test/ 配下の開発用ツール)。production 実行(harness/ 本体)にも
negative control(一時コピー + 意図的な壊し)にも同じロジックを使い回すことで、
「本番と同じコードで検査した」ことを保証する(検査コードの二重実装によるdriftを避ける)。

サブコマンド:
  check1 <base_dir>            実行ファイル名の実在(skills/agents/rules/hooks に現れる
                                yosage-dev-harness-<name> が bin/ に実在し実行ビットを持ち、
                                bin/ が指す lib/<name>.sh が実在する)
  check2 <base_dir> [--exclude <file:line>...]
                                \\.claude/(lib|hooks)/ 参照が harness 配下に残っていない
                                (--exclude で個別判断の残留箇所を除外できる)
  check3 <base_dir>            10エージェント名が yosage-dev-harness: の直後以外で単語として
                                現れない(agents/<name>.md の frontmatter name: 行を除く)
  check3-agents-exist <base_dir>
                                yosage-dev-harness:<x> の <x> がすべて agents/<x>.md に実在し、
                                その frontmatter の name が <x> と一致する
  regex-selftest                除外規則(パスの一部は数えない)自体の検査

全モード: 検査に引っかかった件数を stdout へ列挙し、0件なら exit 0 / 1件以上なら exit 1。
"""
import os
import re
import sys

AGENT_NAMES = [
    "architect", "best-practice-reviewer", "code-reviewer", "consistency-reviewer",
    "doc-writer", "explorer", "implementer", "librarian", "researcher", "test-writer",
]

BOUNDARY_PRE = r'(^|[^A-Za-z0-9_/:.\-])'
BOUNDARY_POST = r'([^A-Za-z0-9_/.\-]|$)'


def _walk_files(base_dir, subdirs=None):
    out = []
    roots = [os.path.join(base_dir, d) for d in subdirs] if subdirs else [base_dir]
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, _dirnames, filenames in os.walk(root):
            if "/.git" in dirpath:
                continue
            for f in filenames:
                out.append(os.path.join(dirpath, f))
    return out


def _read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (UnicodeDecodeError, OSError):
        return None


def check1(base_dir):
    """実行ファイル名の実在。"""
    name_re = re.compile(r'yosage-dev-harness-[a-z0-9-]+')
    ext_re = re.compile(r'\.[a-z]+\b')
    problems = []
    found_names = set()
    for path in _walk_files(base_dir, ["skills", "agents", "rules", "hooks"]):
        text = _read(path)
        if text is None:
            continue
        for m in name_re.finditer(text):
            # 直後に拡張子(.md 等)が続く場合は実行ファイル名ではなく設定ファイル名
            # (`.claude/yosage-dev-harness-review-criteria.md` 等)なので除外する
            # (greedy match の末尾直後だけを見る。途中で切って再マッチさせない)。
            if ext_re.match(text, m.end()):
                continue
            found_names.add(m.group(0))

    bin_dir = os.path.join(base_dir, "bin")
    for name in sorted(found_names):
        bin_path = os.path.join(bin_dir, name)
        if not os.path.isfile(bin_path):
            problems.append(f"実行ファイルが実在しない: bin/{name}")
            continue
        if not os.access(bin_path, os.X_OK):
            problems.append(f"実行ビットが無い: bin/{name}")
            continue
        content = _read(bin_path) or ""
        lib_m = re.search(r'lib/([a-z0-9-]+\.sh)', content)
        if not lib_m:
            problems.append(f"bin/{name} が指す lib/<name>.sh を読み取れない")
            continue
        lib_path = os.path.join(base_dir, "lib", lib_m.group(1))
        if not os.path.isfile(lib_path):
            problems.append(f"bin/{name} が指す lib/{lib_m.group(1)} が実在しない")
    return problems


def check2(base_dir, exclusions=None):
    """パスでの呼び出しが残っていない。"""
    exclusions = exclusions or []
    pat = re.compile(r'\.claude/(lib|hooks)/')
    problems = []
    for path in _walk_files(base_dir):
        text = _read(path)
        if text is None:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if pat.search(line):
                key = f"{path}:{i}"
                if key in exclusions:
                    continue
                problems.append(f"{path}:{i}: {line.strip()[:160]}")
    return problems


def _is_agent_frontmatter_name_line(path, base_dir, stripped_line):
    rel = os.path.relpath(path, base_dir)
    if not (rel.startswith("agents" + os.sep) and rel.endswith(".md")):
        return False
    agent_basename = os.path.basename(path)[:-3]
    return bool(re.match(r'^name:\s*' + re.escape(agent_basename) + r'\s*$', stripped_line))


def check3(base_dir):
    """10エージェント名が名前空間なしで単語として現れない。"""
    problems = []
    for path in _walk_files(base_dir):
        text = _read(path)
        if text is None:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if _is_agent_frontmatter_name_line(path, base_dir, line.strip()):
                continue
            for n in AGENT_NAMES:
                pat = re.compile(BOUNDARY_PRE + re.escape(n) + BOUNDARY_POST)
                for m in pat.finditer(line):
                    prefix_window = line[max(0, m.start() - 20):m.start() + 1]
                    if 'yosage-dev-harness:' in prefix_window:
                        continue
                    problems.append(f"{path}:{i}: 名前空間なしの `{n}` -> {line.strip()[:160]}")
    return problems


def check3_agents_exist(base_dir):
    """yosage-dev-harness:<x> の <x> が agents/<x>.md に実在し name: が一致する。"""
    problems = []
    ref_re = re.compile(r'yosage-dev-harness:([a-z0-9-]+)')
    for path in _walk_files(base_dir):
        text = _read(path)
        if text is None:
            continue
        for m in ref_re.finditer(text):
            x = m.group(1)
            if x not in AGENT_NAMES:
                continue
            agent_path = os.path.join(base_dir, "agents", f"{x}.md")
            if not os.path.isfile(agent_path):
                problems.append(f"{path}: yosage-dev-harness:{x} の agents/{x}.md が実在しない")
                continue
            agent_text = _read(agent_path) or ""
            if not re.search(r'(?m)^name:\s*' + re.escape(x) + r'\s*$', agent_text):
                problems.append(f"agents/{x}.md の frontmatter name が {x} と一致しない")
    return sorted(set(problems))


# この定数は「旧製品名の文字列」を組み立てるためだけに存在する。リテラルのまま書くと、この
# チェッカー自身のソースが check4 の検査対象(harness/scripts/test 配下)に含まれたとき、
# 検出対象の文字列を検出器自身が含んでいる(自己検出=偽陽性)ことになる。連結で組み立てることで
# ソース上に検索対象の文字列そのものが現れないようにする(自己参照を起こさない一般的な回避技法)。
_OLD_PRODUCT_NAME = "yosage" + "-harness"
_NEW_PRODUCT_NAME = "yosage-dev" + "-harness"


def check4(dirs):
    """旧製品名(yosage-dev-harness の部分一致を除く)。"""
    pat = re.compile(re.escape(_OLD_PRODUCT_NAME))
    dev_pat = re.compile(re.escape(_NEW_PRODUCT_NAME))
    problems = []
    for d in dirs:
        for path in _walk_files(d):
            text = _read(path)
            if text is None:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                for m in pat.finditer(line):
                    # yosage-dev-harness の部分一致を除く: 一致箇所が dev_pat の一致に包含されるか確認
                    covered = any(dm.start() <= m.start() and m.end() <= dm.end()
                                  for dm in dev_pat.finditer(line))
                    if covered:
                        continue
                    problems.append(f"{path}:{i}: {line.strip()[:160]}")
    return problems


def regex_selftest():
    """除外規則(パスの一部は数えない)自体の検査。"""
    problems = []
    pat = re.compile(BOUNDARY_PRE + re.escape("implementer") + BOUNDARY_POST)

    def matched(s):
        for m in pat.finditer(s):
            prefix_window = s[max(0, m.start() - 20):m.start() + 1]
            if 'yosage-dev-harness:' in prefix_window:
                continue
            return True
        return False

    # パスの一部(agents/implementer.md)は agent 参照として検出されないはず
    if matched("参照: agents/implementer.md を読む。"):
        problems.append("false positive: agents/implementer.md がパスとして除外されなかった")
    # 名前空間つきの論理パス(yosage-dev-harness:agents/implementer.md)も同様
    if matched("参照: yosage-dev-harness:agents/implementer.md を読む。"):
        problems.append("false positive: yosage-dev-harness:agents/implementer.md が除外されなかった")
    # 名前空間なしの裸の参照(バッククォートで囲んだだけ)は検出されるべき
    if not matched("これは `implementer` に回す。"):
        problems.append("false negative: 裸の `implementer` が検出されなかった")
    return problems


def main():
    if len(sys.argv) < 2:
        print("usage: bin-checks.py <check1|check2|check3|check3-agents-exist|check4|regex-selftest> [args...]",
              file=sys.stderr)
        return 2
    mode = sys.argv[1]
    if mode == "check1":
        problems = check1(sys.argv[2])
    elif mode == "check2":
        args = sys.argv[2:]
        if "--exclude" in args:
            idx = args.index("--exclude")
            base_dir = args[0]
            exclusions = args[idx + 1:]
        else:
            base_dir = args[0]
            exclusions = []
        problems = check2(base_dir, exclusions)
    elif mode == "check3":
        problems = check3(sys.argv[2])
    elif mode == "check3-agents-exist":
        problems = check3_agents_exist(sys.argv[2])
    elif mode == "check4":
        problems = check4(sys.argv[2:])
    elif mode == "regex-selftest":
        problems = regex_selftest()
    else:
        print(f"unknown mode: {mode}", file=sys.stderr)
        return 2

    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
