#!/usr/bin/env python3
"""test/lib/preprocess-checks.py — test/suites/93-preprocess.sh が使う共有チェッカー。
配布 payload の一部ではない(test/ 配下の開発用ツール)。production 実行(harness/ 本体)にも
negative control(一時コピー + 意図的な壊し)にも同じロジックを使い回すことで、
「本番と同じコードで検査した」ことを保証する(検査コードの二重実装によるdriftを避ける)。

スキルの前処理(SKILL.md の !`...` 行)を持つスキルについて、
- 前処理が呼ぶのはハーネスの実行ファイル(yosage-dev-harness-<name>)1つだけ
- そのスキルの frontmatter の allowed-tools が、前処理が使う実行ファイルの
  Bash(<name> *) を過不足なく含む
- 前処理を持たないスキルには allowed-tools が無い(allow を配らない)
- 前処理を持つスキルの数が固定(黙って増減しない)
を検査する。

サブコマンド:
  check1 <base_dir>   前処理の先頭コマンドがすべて yosage-dev-harness- で始まり bin/ に実在し、
                       前処理の中に他のコマンド(パイプ・&&・||・; で繋いだもの)が無い
  check2 <base_dir>   前処理を持つスキルの allowed-tools が Bash(<name> *) を過不足なく含む
  check3 <base_dir>   前処理を持たないスキルに allowed-tools が無い
  check4 <base_dir>   前処理を持つスキルの集合が期待どおり(6つ・名前も一致)

全モード: 検査に引っかかった件数を stdout へ列挙し、0件なら exit 0 / 1件以上なら exit 1。
"""
import os
import re
import sys

EXPECTED_PREPROCESS_SKILLS = [
    "epic-implement",
    "epic-implement-subissue",
    "epic-review",
    "issue-implement",
    "promote-knowledge",
    "status",
]

PREPROCESS_LINE_RE = re.compile(r'(?m)^!`([^`]*)`$')
FRONTMATTER_RE = re.compile(r'\A---\n(.*?)\n---\n', re.S)
ALLOWED_TOOLS_FIELD_RE = re.compile(r'(?m)^allowed-tools:\s*(.*)$')
BASH_TOKEN_RE = re.compile(r'Bash\([^)]*\)')
# パイプ・&&・||・; のいずれかで繋いだ別コマンドが無いことを見るための分割演算子。
# || / && を先に判定しないと | だけで壊れて誤分割するため順序に注意。
SEGMENT_SPLIT_RE = re.compile(r'\|\||&&|\||;')


def _read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (UnicodeDecodeError, OSError):
        return None


def _skill_dirs(base_dir):
    """(skill_name, SKILL.md の絶対パス, 本文全体) のリスト。SKILL.md が無いものは飛ばす。"""
    out = []
    skills_dir = os.path.join(base_dir, "skills")
    if not os.path.isdir(skills_dir):
        return out
    for name in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, name, "SKILL.md")
        if not os.path.isfile(path):
            continue
        text = _read(path)
        if text is None:
            continue
        out.append((name, path, text))
    return out


def _preprocess_lines(text):
    """行全体が `` !`...` `` の形の行を前処理とみなす(フェンスされたコードブロックの中に
    あっても拾う)。以前はフェンスの中身を抽出前に除外していたが、フェンスの開始/終了の
    ペア取りを「直近の後続の裸の ``` 行」で対応づける簡略化が、閉じ忘れのフェンス(``` が
    1行だけ)がある場合に、それより後ろにある無関係な閉じフェンスと誤って対になり、間に
    ある本物の前処理行ごと検査対象から消してしまう(check1 が素通りする)欠陥を持っていた
    (4本以上のバッククォートを使う可変長フェンスにも非対応だった)。この検査の目的は
    前処理と allowed-tools の対応を固定して意図しない Bash 許可の拡大を防ぐことであり、
    前処理行を見落とす方向の失敗(false negative)は、フェンス内の例示行を前処理と誤認する
    方向の失敗(false positive、単に検査が赤くなるだけ)より安全上重い。そのため除外はせず、
    見落としより誤検出(赤くなる)側に倒す。スキルの本文に前処理の書式を説明する例示として
    `` !`...` `` を単独行で置くと、この検査は意図せず赤くなる——例示は行の途中に置くか
    (例: `前処理は `` !`cmd` `` の形。`)、別の書き方にすること。"""
    return PREPROCESS_LINE_RE.findall(text)


def _frontmatter_text(text):
    m = FRONTMATTER_RE.match(text)
    return m.group(1) if m else ""


def _allowed_tools_raw(frontmatter_text):
    """frontmatter の allowed-tools: フィールドの生の値。フィールドが無ければ None。"""
    m = ALLOWED_TOOLS_FIELD_RE.search(frontmatter_text)
    return m.group(1).strip() if m else None


def _exec_names_for_skill(text):
    """このスキルの前処理が呼ぶ実行ファイル名の集合(重複除去)。単一コマンドでない
    前処理行は check1 で検出するため、ここでは先頭語だけを見る(best-effort)。"""
    names = set()
    for cmd in _preprocess_lines(text):
        segments = [s.strip() for s in SEGMENT_SPLIT_RE.split(cmd)]
        segments = [s for s in segments if s]
        if not segments:
            continue
        first_word = segments[0].split()[0] if segments[0].split() else ""
        if first_word.startswith("yosage-dev-harness-"):
            names.add(first_word)
    return names


def check1(base_dir):
    """前処理の先頭コマンドが yosage-dev-harness- で始まり bin/ に実在し、
    前処理の中に他のコマンドが繋がれていない。"""
    problems = []
    bin_dir = os.path.join(base_dir, "bin")
    for name, path, text in _skill_dirs(base_dir):
        for cmd in _preprocess_lines(text):
            segments = [s.strip() for s in SEGMENT_SPLIT_RE.split(cmd)]
            segments = [s for s in segments if s]
            if len(segments) != 1:
                problems.append(
                    f"{name}: 前処理に他のコマンドが繋がっている(パイプ/&&/||/;): `{cmd}`")
                continue
            first_word = segments[0].split()[0] if segments[0].split() else ""
            if not first_word.startswith("yosage-dev-harness-"):
                problems.append(
                    f"{name}: 前処理の先頭コマンドが yosage-dev-harness- で始まらない: `{cmd}`")
                continue
            bin_path = os.path.join(bin_dir, first_word)
            if not os.path.isfile(bin_path):
                problems.append(f"{name}: 前処理が呼ぶ bin/{first_word} が実在しない")
    return problems


def check2(base_dir):
    """前処理を持つスキルの allowed-tools が Bash(<name> *) を過不足なく含む。"""
    problems = []
    for name, path, text in _skill_dirs(base_dir):
        exec_names = _exec_names_for_skill(text)
        if not exec_names:
            continue
        expected_tokens = {f"Bash({n} *)" for n in exec_names}
        raw = _allowed_tools_raw(_frontmatter_text(text))
        if raw is None:
            problems.append(f"{name}: 前処理を持つのに allowed-tools が無い(期待: {sorted(expected_tokens)})")
            continue
        found_tokens = set(BASH_TOKEN_RE.findall(raw))
        residue = BASH_TOKEN_RE.sub("", raw).strip()
        if residue:
            problems.append(f"{name}: allowed-tools に Bash(...) 以外の残留がある: `{residue}`")
        missing = expected_tokens - found_tokens
        extra = found_tokens - expected_tokens
        if missing:
            problems.append(f"{name}: allowed-tools に不足がある: {sorted(missing)}")
        if extra:
            problems.append(f"{name}: allowed-tools に余分がある: {sorted(extra)}")
    return problems


def check3(base_dir):
    """前処理を持たないスキルに allowed-tools が無い。"""
    problems = []
    for name, path, text in _skill_dirs(base_dir):
        if _preprocess_lines(text):
            continue
        raw = _allowed_tools_raw(_frontmatter_text(text))
        if raw is not None:
            problems.append(f"{name}: 前処理を持たないのに allowed-tools がある: `{raw}`")
    return problems


def check4(base_dir):
    """前処理を持つスキルの集合が期待どおり(5つ・名前も一致)。"""
    problems = []
    found = sorted(name for name, _path, text in _skill_dirs(base_dir) if _preprocess_lines(text))
    expected = sorted(EXPECTED_PREPROCESS_SKILLS)
    if found != expected:
        problems.append(f"前処理を持つスキルの集合が期待と異なる: 実際={found} 期待={expected}")
    return problems


def main():
    if len(sys.argv) < 3:
        print("usage: preprocess-checks.py <check1|check2|check3|check4> <base_dir>", file=sys.stderr)
        return 2
    mode, base_dir = sys.argv[1], sys.argv[2]
    checks = {"check1": check1, "check2": check2, "check3": check3, "check4": check4}
    if mode not in checks:
        print(f"unknown mode: {mode}", file=sys.stderr)
        return 2
    problems = checks[mode](base_dir)
    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
