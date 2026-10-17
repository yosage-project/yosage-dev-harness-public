#!/usr/bin/env bash
# knowledge-index.sh — エントリの frontmatter を走査する単一の解析器。
# 既定(引数無し)は INDEX.md / INDEX.archive.md への書き出し(生成物・検証器としての用途)。
# --list / --list-archive は書き出さず、同じ走査・解析・フィルタ結果を stdout へ直接返す
# (recall の主経路。索引ファイルの存在・鮮度に依存しない直接列挙)。
#
# 書き出しと列挙が別の解析コードを持つと将来 drift する(index はここを直しても列挙側は直さない、
# という事故)。それを構造的に防ぐため、両モードは同じ Python 内の1回の走査・フィルタ結果
# (rows/active_rows/archive_rows)を分岐先で使い回すだけにする。
# ローカル索引を追跡しない任意のキャッシュとして扱う判断・反証条件は
# ルール `knowledge` の「ローカル索引は任意のキャッシュ」節が正本(ここでは再記述しない)。
#
# 使い方:
#   yosage-dev-harness-knowledge-index <knowledge-dir>                          既定: INDEX.md/INDEX.archive.md を生成(書き出し)
#   yosage-dev-harness-knowledge-index <knowledge-dir> --list [domain]          現行(active)エントリを stdout へ列挙(TSV)
#   yosage-dev-harness-knowledge-index <knowledge-dir> --list-archive [domain]  現行外(superseded/archived)を stdout へ列挙(TSV)
#   yosage-dev-harness-knowledge-index <knowledge-dir> --check                  検証だけ(frontmatter の書式警告をstderrへ出す)。ファイルは書かない
#
#   <dir>/<配置ディレクトリ>/*.md の frontmatter を走査(`global/` と `_*` は除外)。domain 列は
#   frontmatter の `domain:` を正とし、無ければ配置ディレクトリ名へフォールバックする(id と対称の
#   仕様。id も明示 `id:` を正としファイル名へフォールバックする)。frontmatter の domain と配置
#   ディレクトリ名が食い違う場合は frontmatter を黙って採用する(この生成器自身は診断を出さない。
#   理由は resolve_domain のコメント参照)。
#   振り分けは denylist（`status: superseded`/`archived` だけを archive 側へ、それ以外＝
#   `active`・空・欠落・未知の値は active 側へ。allowlist にしない＝status が欠落/typo のエントリを
#   active 側から静かに落とさない）。書き出しモードは毎回両方のファイルを書く(現行外が 0件でも
#   INDEX.archive.md を空表で出す。最後の1件が active に戻ったとき古いファイルが残らないため)。
#   `--list`/`--list-archive` の出力列は `id, domain, tags, date, scope, status, summary, path`
#   (TSV・1行1エントリ)。`path` は絶対パス(呼び出し元が id→場所を索引無しで直接 Read できるように、
#   書き出しモードの INDEX.md テーブルには無い列を列挙モードだけに足している)。domain を指定すると
#   解決済み domain（frontmatter 優先）で絞り込む(省略時は全件)。
# 前提: frontmatter は 1行 `key: value`（summary 等は1行。YAML ブロックスカラー/複数行値は非対応）。
set -uo pipefail

ki_log() { printf 'knowledge-index: %s\n' "$1" >&2; }

# knowledge ディレクトリ(<dir>)の親ディレクトリ(`.claude/`)に、setup が必ず作る設定ファイルが
# あれば「導入先」と判定する。導入先で knowledge/ が無いのは「知見0件」の正当な状態(空ディレクトリは
# git に残らず、別のマシンで clone すると再び無くなるため、ディレクトリの存在を前提にしない)。
# 設定ファイルも無いときは、cwd や引数の取り違えと区別できないので「0件」とは扱わず失敗のままにする。
ki_is_installed_target() {  # <knowledge-dir>
  local d="$1"
  while [ "${d%/}" != "$d" ]; do d="${d%/}"; done  # 末尾のスラッシュ(複数も)を落とす
  [ -n "$d" ] && [ -f "$(dirname "$d")/yosage-dev-harness.local.json" ]
}

knowledge_index() {  # <dir> [--list|--list-archive] [domain]
  local dir="${1:-}" mode="${2:-}" domain_filter="${3:-}"
  # 存在判定の前に末尾のスラッシュ(複数も)を落とす。付いたままだと、knowledge が通常ファイルや
  # 壊れたシンボリックリンクでも `-e`(ENOTDIR)・`-L`(リンク先を見る)が偽になり、「何も無い」と誤判定する。
  local probe="$dir"
  while [ "${probe%/}" != "$probe" ]; do probe="${probe%/}"; done
  if [ -n "$probe" ] && [ ! -e "$probe" ] && [ ! -L "$probe" ] && ki_is_installed_target "$probe"; then
    # 導入先と分かる(同じ .claude/ に設定ファイルがある)のに knowledge/ が本当に何も無い(通常ファイル・
    # 壊れたシンボリックリンクは「無い」ではなく異常なので救わず、下の失敗に落とす): 知見が0件の正当な状態。
    # 列挙(--list/--list-archive)と検証(--check)は読むだけなので、0件・終了コード0・出力なしで返す。
    # 書き出しモード(引数なし)は書き込み先が無いので、ここでは救わず従来どおり下の失敗に落とす。
    case "$mode" in --list|--list-archive|--check) return 0 ;; esac
  fi
  [ -n "$dir" ] && [ -d "$dir" ] || { ki_log "ディレクトリが不正: ${dir:-(空)}"; return 1; }
  command -v python3 >/dev/null 2>&1 || { ki_log "python3 が無い → INDEX 生成を skip"; return 0; }
  python3 - "$dir" "$mode" "$domain_filter" <<'PY'
import sys, os, glob, re
base = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else ''
domain_filter = sys.argv[3] if len(sys.argv) > 3 else ''

def derive_id(filename):
    # id frontmatter が無いエントリの実効 id をファイル名から導出する（正式仕様。救済ではない）。
    # 拡張子を除去(stem) → 先頭の YYYY-MM-DD- プレフィックスがあれば除去 → 残りが slug。
    # 除去結果が空文字になる場合は stem 全体を slug とする(実効 id は決して空文字にしない。
    # 空になると INDEX の第1列が空になり、参照から引けなくなるため)。
    stem = filename[:-3] if filename.endswith('.md') else filename
    stripped = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', stem)
    return stripped or stem

def resolve_domain(dirname, declared):
    # domain frontmatter が有ればそれを正とし、無ければ配置ディレクトリ名へフォールバックする
    # （derive_id と対称の仕様: id も明示 `id:` を正としファイル名へフォールバックする）。
    #
    # 食い違いの診断(stderr 警告)はここでは出さない。理由: この生成器は2つの経路から呼ばれる。
    # (1) hooks/knowledge-index.sh(project-local エントリ編集時) — この経路は構造監査
    #     (lib/knowledge-audit.sh の check7/domain-mismatch)も同時に走り、同じ条件を確実に
    #     検出して systemMessage/additionalContext に届く。生成器側でも警告すると同一原因の
    #     警告が2本出て重複する。
    # (2) lib/knowledge-sync.sh(グローバル知識ストアの同期。`.claude/knowledge/global/` の
    #     再生成) — この経路では呼び出し側が生成器の標準エラー出力を丸ごと捨てている
    #     (`>/dev/null 2>&1`)。しかも同期対象は配布元からの pull ミラーで**利用者は編集できない
    #     読み取り専用**なので、たとえ届いたとしても利用者に取れる行動が無い。行動できない対象に
    #     警告を出しても、セッションのたびにノイズが増えるだけで検出の価値が無い。
    # 行動できる対象(project-local エントリ)には (1) の監査が確実に届くため、生成器はここでは
    # 診断を出さずフォールバック解決だけを行う。
    declared = declared.strip()
    return declared or dirname

def frontmatter(path):
    try:
        lines = open(path, encoding='utf-8').read().splitlines()
    except Exception:
        return {}
    if not lines or lines[0].strip() != '---':
        return {}
    d = {}
    for ln in lines[1:]:
        if ln.strip() == '---':
            break
        if ':' not in ln:
            continue
        k, v = ln.split(':', 1)
        # 1行 key: value のみ対応（値中の : や # はそのまま保持。YAML コメント/ブロックスカラーは非対応）
        d[k.strip()] = v.strip()
    return d

# summary が YAML ブロックスカラー指示子(`>`/`|`。chomping `+`/`-`・インデント指示の数字が
# 付いてもよい)だけ、または空のときを「壊れている」とみなす。1行 `key: value` 前提のパーサは
# 折り返し本文を連結せず、指示子1文字だけを値として拾ってしまうため。
BROKEN_SUMMARY_RE = re.compile(r'^[>|][+\-0-9]*$')

def is_broken_summary(v):
    v = v.strip()
    return (not v) or bool(BROKEN_SUMMARY_RE.match(v))

# 現行外(denylist): 明示的にこの値を持つエントリだけを archive 側へ回す。
# allowlist(active だけ通す)にしない＝status 欠落/typo のエントリを active 側から消さないため。
ARCHIVE_STATUSES = {'superseded', 'archived'}

# 走査・解析・フィルタは書き出し/列挙の両モードで共通(1回だけ)。ここで作った rows を
# 分岐先(ファイル書き出し or stdout 列挙)がそれぞれ使うだけで、解析ロジックの複製は無い。
rows = []
for f in sorted(glob.glob(os.path.join(base, '*', '*.md'))):
    dir_dom = os.path.basename(os.path.dirname(f))
    name = os.path.basename(f)
    if dir_dom == 'global' or name.startswith('_'):
        continue
    d = frontmatter(f)
    eff_id = d.get('id') or derive_id(name)
    dom = resolve_domain(dir_dom, d.get('domain', ''))
    tags = d.get('tags', '').strip().lstrip('[').rstrip(']').replace(' ', '')
    summary = d.get('summary', '')
    if is_broken_summary(summary):
        # 壊れた summary(YAML ブロックスカラー指示子だけ、または空)をそのまま出さず、
        # stderr にエントリのファイル名付きで警告する。フック(hooks/knowledge-index.sh)がこの
        # stderr を拾って systemMessage/additionalContext に流すので、agent と人間の双方に届く。
        # (生成器としての検証器の役割は書き出し/列挙どちらのモードでも変わらない)
        print(f"knowledge-index: {name}: summary が YAML ブロックスカラー(> / |)/空です。"
              "1行のプレーンスカラーで書いてください(例: summary: 要約をここに1行で)",
              file=sys.stderr)
        summary = ''
    # path は列挙モード専用の列(書き出しモードのテーブルには含めない)。呼び出し元が索引を
    # 介さず id→場所を直接引けるようにするため、常に絶対パスにする(Read ツールは絶対パス前提)。
    rows.append([eff_id, dom, tags, d.get('date', ''),
                 d.get('scope', ''), d.get('status', ''), summary,
                 os.path.abspath(f)])

active_rows = [r for r in rows if r[5] not in ARCHIVE_STATUSES]
archive_rows = [r for r in rows if r[5] in ARCHIVE_STATUSES]

if mode in ('--list', '--list-archive'):
    chosen = active_rows if mode == '--list' else archive_rows
    if domain_filter:
        chosen = [r for r in chosen if r[1] == domain_filter]
    for r in chosen:
        print('\t'.join(c.replace('\t', ' ') for c in r))
    sys.exit(0)

if mode == '--check':
    # 検証だけ(ファイルを書かない)。frontmatter の書式警告(壊れた summary 等)は上の rows 生成時に
    # 既に stderr へ出ている(モード分岐の手前・両モード共通の1回の走査)。ここでは書き出しを行わず
    # 終了する(project-local の INDEX.md/INDEX.archive.md は生成物ではなくなった。ルール `knowledge`)。
    sys.exit(0)

header = [
    '| id | domain | tags | date | scope | status | summary |',
    '|----|--------|------|------|-------|--------|---------|',
]

out = [
    '# Knowledge INDEX',
    '',
    '> **生成物**: エントリ(`<配置ディレクトリ>/*.md`)の frontmatter から `yosage-dev-harness-knowledge-index` が生成'
    '（domain 列は frontmatter の `domain:` を正とし、無ければ配置ディレクトリ名へフォールバック）。'
    '**手編集しない**（エントリを足したら再生成）。',
    '> **任意のローカルキャッシュ**（このリポジトリでは git 追跡しない）。'
    '司書(`yosage-dev-harness:librarian`)・`recall-knowledge` は `yosage-dev-harness-knowledge-index --list` の直接列挙を主経路とし、'
    'ここは無くても recall は成立する（ルール `knowledge` 参照）。'
    'グローバルは sync で `global/INDEX.md` に来る（これは従来どおり索引を使う）。',
    '> 現行外(`status: superseded`/`archived`)は `INDEX.archive.md` に分離。退役分の直接列挙は'
    '`yosage-dev-harness-knowledge-index --list-archive` を使う（この索引ファイルと同様、無くても列挙できる）。',
    '',
] + header
for r in active_rows:
    out.append('| ' + ' | '.join(c.replace('|', '/') for c in r[:7]) + ' |')

archive_out = [
    '# Knowledge INDEX（現行外）',
    '',
    '> **生成物**: エントリ(`<配置ディレクトリ>/*.md`)の frontmatter から `yosage-dev-harness-knowledge-index` が生成'
    '（domain 列は frontmatter の `domain:` を正とし、無ければ配置ディレクトリ名へフォールバック）。'
    '**手編集しない**（エントリを足したら再生成）。',
    '> **現行外**（`status: superseded`/`archived`）を集約。active recall では引かない（判断履歴として残すだけ）。'
    '**任意のローカルキャッシュ**（このリポジトリでは git 追跡しない）。退役エントリの直接列挙は'
    '`yosage-dev-harness-knowledge-index --list-archive` を使う。',
    '',
] + header
for r in archive_rows:
    archive_out.append('| ' + ' | '.join(c.replace('|', '/') for c in r[:7]) + ' |')

idx = os.path.join(base, 'INDEX.md')
open(idx, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
arc = os.path.join(base, 'INDEX.archive.md')
open(arc, 'w', encoding='utf-8').write('\n'.join(archive_out) + '\n')
print(idx)
print(arc)
PY
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then knowledge_index "${1:-}" "${2:-}" "${3:-}"; fi
