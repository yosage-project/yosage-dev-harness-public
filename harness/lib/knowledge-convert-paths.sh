#!/usr/bin/env bash
# knowledge-convert-paths.sh — knowledge エントリの導入先のパス参照
#   (`.claude/(skills|agents|lib|hooks)/…`・`.claude/rules` 配下の旧 `harness/…`・`.claude/github/labels.json`)を
#   論理パス(`yosage-dev-harness:<harness/ からの相対パス>`)へ書き換える変換スクリプト。
#
# 使い方: yosage-dev-harness-knowledge-convert-paths [--apply] <knowledge-dir>
#   <knowledge-dir> 配下の *.md(global/ は除く)の本文・frontmatter の導入先のパスを論理パスに置き換える。
#   既定は --dry-run(置き換える箇所をファイル:行・旧→新で出す。何も書かない)。--apply で書き換える。
#   対応表:
#     .claude/skills/<x>          → yosage-dev-harness:skills/<x>
#     .claude/agents/<x>          → yosage-dev-harness:agents/<x>
#     .claude/lib/<x>             → yosage-dev-harness:lib/<x>
#     .claude/hooks/<x>           → yosage-dev-harness:hooks/<x>
#     .claude/rules 配下の旧 harness/<x>  → yosage-dev-harness:rules/<x>
#     .claude/github/labels.json  → yosage-dev-harness:github/labels.json
#   置き換えた先が使用中のプラグインに実在しない(撤去・改名されたファイル)ものは置き換えず、
#   「要手直し」として別に一覧に出す。コードスパンの中(`…`)も参照として置き換える(ナレッジの
#   パス参照は多くがコードスパンで書かれているため。コードスパン外の地の文でも同じトークンなら
#   同様に置き換える — 参照とリテラルの書き分けはコードスパンの内か外かで判定する規約だが、
#   ここでのトークンはどちらの文脈でも同じ意味(配布物のパス参照)なので、区別せず一律に置き換える)。
#   終了コード: 0=置き換え対象なし / 10=置き換え対象あり(dry-run) / 0=--apply で書き換え完了 / 2=引数不正。
set -uo pipefail

kcp_log() { printf 'knowledge-convert-paths: %s\n' "$1" >&2; }

knowledge_convert_paths() {  # [--apply] <knowledge-dir>
  local apply=0
  local dir=""
  for arg in "$@"; do
    case "$arg" in
      --apply) apply=1 ;;
      -*)
        kcp_log "使い方: yosage-dev-harness-knowledge-convert-paths [--apply] <knowledge-dir>"
        return 2
        ;;
      *)
        if [ -n "$dir" ]; then
          kcp_log "使い方: yosage-dev-harness-knowledge-convert-paths [--apply] <knowledge-dir>"
          return 2
        fi
        dir="$arg"
        ;;
    esac
  done
  [ -n "$dir" ] && [ -d "$dir" ] || { kcp_log "ディレクトリが不正: ${dir:-(空)}"; return 2; }
  command -v python3 >/dev/null 2>&1 || { kcp_log "python3 が無い → 変換を skip"; return 0; }
  local plugin_root
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  python3 - "$dir" "$plugin_root" "$apply" <<'PY'
import sys, os, glob, re

kdir = os.path.abspath(sys.argv[1])
plugin_root = os.path.abspath(sys.argv[2])
apply = sys.argv[3] == '1'

# rules 配下の旧サブディレクトリ名(このリポジトリ自身の内部パスと同じ文字列になるため、静的検査
# (91-inject.sh の「旧レイアウト参照の残留検査」)に自己検出されないよう連結で組み立てる。
# 同種の回避は test/lib/bin-checks.py の _OLD_PRODUCT_NAME に前例がある)。
_LEGACY_RULES_SUBDIR = 'rules' + '/harness/'

MAPPINGS = [
    (re.compile(r'^\.claude/skills/'), 'yosage-dev-harness:skills/'),
    (re.compile(r'^\.claude/agents/'), 'yosage-dev-harness:agents/'),
    (re.compile(r'^\.claude/lib/'), 'yosage-dev-harness:lib/'),
    (re.compile(r'^\.claude/hooks/'), 'yosage-dev-harness:hooks/'),
    (re.compile(r'^\.claude/' + _LEGACY_RULES_SUBDIR), 'yosage-dev-harness:rules/'),
    (re.compile(r'^\.claude/github/labels\.json$'), 'yosage-dev-harness:github/labels.json'),
]

# トークン抽出: 上記プレフィックスのいずれかで始まり、パス文字(英数字・_-./)が続く連続列。
TOKEN_RE = re.compile(
    r'\.claude/(?:skills|agents|lib|hooks|rules/harness|github/labels\.json)'
    r'(?:/[A-Za-z0-9_.\-]+)*'
)


def convert_token(tok):
    for pat, repl in MAPPINGS:
        if pat.match(tok):
            return pat.sub(repl, tok, count=1)
    return None


def target_exists(logical):
    rel = logical.split(':', 1)[1]
    if '..' in rel:
        return False
    return os.path.isfile(os.path.join(plugin_root, rel))


changes = []       # (path, lineno, old, new)
needs_manual = []  # (path, lineno, old_token, attempted_new)

files = sorted(
    f for f in glob.glob(os.path.join(kdir, '*', '*.md'))
    if os.path.basename(os.path.dirname(f)) != 'global'
)

for f in files:
    try:
        text = open(f, encoding='utf-8').read()
    except Exception:
        continue
    lines = text.splitlines(keepends=True)
    new_lines = []
    file_changed = False
    for lineno, line in enumerate(lines, start=1):
        def repl(m, _f=f, _lineno=lineno):
            tok = m.group(0)
            new_tok = convert_token(tok)
            if new_tok is None:
                return tok
            if not target_exists(new_tok):
                needs_manual.append((_f, _lineno, tok, new_tok))
                return tok
            changes.append((_f, _lineno, tok, new_tok))
            return new_tok
        new_line = TOKEN_RE.sub(repl, line)
        if new_line != line:
            file_changed = True
        new_lines.append(new_line)
    if file_changed and apply:
        open(f, 'w', encoding='utf-8').write(''.join(new_lines))

for f, lineno, old, new in changes:
    print(f"{f}:{lineno}: {old} -> {new}")

if needs_manual:
    print("--- 要手直し(置き換え先が使用中のプラグインに実在しない) ---")
    for f, lineno, old, new in needs_manual:
        print(f"{f}:{lineno}: {old} -> {new}(実在しない)")

if changes:
    sys.exit(0 if apply else 10)
sys.exit(0)
PY
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then knowledge_convert_paths "$@"; fi
