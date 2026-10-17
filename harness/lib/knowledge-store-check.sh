#!/usr/bin/env bash
# knowledge-store-check.sh — グローバル知識ストア(独立リポジトリ)の「形」を決定論で検査する。
#
# 使い方: yosage-dev-harness-knowledge-store-check <ストアのディレクトリ>
#   <ストアのディレクトリ> はストアのルート(`knowledge/` と `review/` を直下に持つ階層)。
#   読むだけで何も書かない(ストアの中にも作業用の一時ファイルを作らない)。
#   標準出力に1行1件、タブ区切り3列 `<ストアからの相対パス>\t<検査コード>\t<メッセージ>` で違反を列挙する
#   (違反0件なら無出力)。終了コード: 0=違反なし / 1=違反あり / 2=使い方の誤り・ディレクトリが不正。
#   検査した件数は終了時に標準エラー出力へ1行出す。
#
# 形の約束の正本は docs/knowledge.md「共有ストアを設定する」。ここは機械が判定する側の正本で、
# 人が読む説明を再記述しない。
#
# 部品の使い回し(別の解析器を持たない):
#   - 壊れた summary の判定と、エントリが索引に載るか: lib/knowledge-index.sh(--check / --list)
#   - 持ち運べない参照のうち issue 番号の残留: lib/knowledge-audit.sh の travel-issue-ref
#     (構造監査は project-local の `.claude/knowledge` を前提にするため、ストアの knowledge/ を
#     一時ディレクトリの `.claude/knowledge/global/` として見せて走らせる。この見せ方で効く検査は
#     global/ 自身の中身を見る travel-issue-ref だけ。dangling-link・legacy-payload-path・
#     travel-unsafe-path-ref・bad-supersedes などは project-local のエントリだけを対象にするので、
#     ここでは効かない。効かない検査のうち、ストアの中で解決できる supersedes と id の重複は、
#     下の Python が自前で検査する。[[id]] の解決とパス参照の検査はしない)
#   上の2つで判定できない形(ディレクトリの形・置いてよいファイル・ファイル名・frontmatter の必須項目と
#   値)だけをこのファイルの Python が持つ。
#   部品が想定外に失敗したときは、検査できなかったものとして exit 2 にする(違反0件の合格に見せない)。
set -uo pipefail

ksc_log() { printf 'knowledge-store-check: %s\n' "$1" >&2; }

knowledge_store_check() {  # <store-dir>
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    ksc_log "使い方: yosage-dev-harness-knowledge-store-check <ストアのディレクトリ>"
    return 2
  fi
  local store="$1"
  [ -d "$store" ] || { ksc_log "ディレクトリが不正: $store"; return 2; }
  command -v python3 >/dev/null 2>&1 || { ksc_log "python3 が無い → 検査できない"; return 2; }
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  store="$(cd "$store" && pwd)"

  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/ksc.XXXXXXXX")" || { ksc_log "一時ディレクトリを作れない"; return 2; }
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN

  # 部品1: 索引生成器。--check の標準エラー出力(壊れた summary)と --list の件数(索引に載るエントリ数)。
  # 部品2: 構造監査。部品は想定外に失敗(非ゼロ終了)しうる。失敗を握りつぶすと「違反0件」の合格に
  # 見えるので、非ゼロは検査不能(exit 2)として原因を標準エラー出力へ出す。
  if [ -d "$store/knowledge" ]; then
    ksc_part() {  # <名前> <出力先(標準エラー出力)> <コマンド...> ; 標準出力は呼び出し側のリダイレクトに任せる
      local name="$1" errf="$2"; shift 2
      "$@" 2> "$errf"
      local rc=$?
      if [ "$rc" != 0 ]; then
        ksc_log "$name が想定外に失敗した(終了コード $rc) → 検査できない"
        sed 's/^/  /' "$errf" >&2
        return 1
      fi
    }
    ksc_part "索引生成器(--check)" "$work/index-check.err" bash "$lib_dir/knowledge-index.sh" "$store/knowledge" --check >/dev/null || return 2
    ksc_part "索引生成器(--list)" "$work/index-list1.err" bash "$lib_dir/knowledge-index.sh" "$store/knowledge" --list > "$work/index-active.tsv" || return 2
    ksc_part "索引生成器(--list-archive)" "$work/index-list2.err" bash "$lib_dir/knowledge-index.sh" "$store/knowledge" --list-archive > "$work/index-archive.tsv" || return 2
    # ストアの knowledge/ を .claude/knowledge/global/ として見せる(コピー。元は触らない)。
    mkdir -p "$work/audit/.claude/knowledge/global" \
      && cp -R "$store/knowledge/." "$work/audit/.claude/knowledge/global/" \
      && : > "$work/audit/.claude/yosage-dev-harness.local.json" \
      || { ksc_log "構造監査用の一時コピーを作れない → 検査できない"; return 2; }
    ksc_part "構造監査" "$work/audit.err" bash "$lib_dir/knowledge-audit.sh" "$work/audit/.claude" > "$work/audit.tsv" || return 2
  fi

  python3 - "$store" "$work" <<'PY'
import sys, os, re, datetime, traceback

def _crash(et, ev, tb):
    # 想定外の例外を「違反あり(exit 1)」に見せない。検査できなかったものとして exit 2 で終わる。
    traceback.print_exception(et, ev, tb)
    print('knowledge-store-check: 検査中に想定外の例外 → 検査できない', file=sys.stderr)
    os._exit(2)
sys.excepthook = _crash

store, work = sys.argv[1], sys.argv[2]
out = []
def add(rel, code, msg):
    out.append((rel, code, msg.replace('\t', ' ').replace('\n', ' ')))

def read(p):
    try:
        return open(p, encoding='utf-8').read()
    except Exception:
        return ''

# --- ルート直下: 置いてよいものだけ ---
ROOT_FILES = {'README.md', 'LICENSE', '.gitignore', '.gitattributes'}
ROOT_DIRS = {'knowledge', 'review', '.git', '.github', '.claude'}  # .claude は手元のハーネス導入(同期は読まない)
for name in sorted(os.listdir(store)):
    p = os.path.join(store, name)
    if os.path.isdir(p) and not os.path.islink(p):
        if name not in ROOT_DIRS:
            add(name + '/', 'unexpected-root-entry',
                'ストアのルート直下に置いてよいディレクトリは knowledge/・review/(と .git・.github・.claude)だけ')
    elif name not in ROOT_FILES:
        add(name, 'unexpected-root-entry',
            'ストアのルート直下に置いてよいファイルは README.md・LICENSE・.gitignore・.gitattributes だけ')

readme = os.path.join(store, 'README.md')
if not os.path.isfile(readme) or not read(readme).strip():
    add('README.md', 'missing-readme',
        'README.md が無い(または空)。昇格 PR を向けるブランチとマージのしかたを書いておく')

# --- review/criteria.md ---
rdir = os.path.join(store, 'review')
crit = os.path.join(rdir, 'criteria.md')
if not os.path.isdir(rdir):
    add('review/', 'missing-review-dir', 'review/ が無い。review/criteria.md を置く(中身がほぼ空でもよい)')
else:
    if not os.path.isfile(crit):
        add('review/criteria.md', 'missing-criteria', 'review/criteria.md が無い(中身がほぼ空でもよいがファイルは置く)')
    elif not read(crit).strip():
        add('review/criteria.md', 'empty-criteria', 'review/criteria.md が空。役割の説明だけでも書く')
    for name in sorted(os.listdir(rdir)):
        if name != 'criteria.md' and name != '.gitkeep':
            add('review/' + name, 'unexpected-file', 'review/ に置いてよいファイルは criteria.md だけ(同期が読むのはそれだけ)')

# --- knowledge/ ---
kdir = os.path.join(store, 'knowledge')
FN_RE = re.compile(r'^(\d{4}-\d{2}-\d{2})-([a-z0-9]+(-[a-z0-9]+)*)\.md$')
DOM_RE = re.compile(r'^[a-z0-9][a-z0-9-]*$')
DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
STATUSES = {'active', 'superseded', 'archived'}
entry_files = []   # (rel, abs, domain_dir, filename)

def valid_date(s):
    if not DATE_RE.match(s):
        return False
    try:
        datetime.date.fromisoformat(s)
        return True
    except ValueError:
        return False

if not os.path.isdir(kdir):
    add('knowledge/', 'missing-knowledge-dir', 'knowledge/ が無い(同期が読むのは knowledge/<ドメイン>/*.md)')
else:
    for name in sorted(os.listdir(kdir)):
        p = os.path.join(kdir, name)
        if os.path.isdir(p) and not os.path.islink(p):
            if name == 'global':
                add('knowledge/global/', 'reserved-domain-name',
                    'global は予約名(各プロジェクトの同期先 knowledge/global/ と衝突し、索引にも載らない)。別のドメイン名にする')
                continue
            if not DOM_RE.match(name):
                add('knowledge/' + name + '/', 'bad-domain-name',
                    'ドメインのディレクトリ名は小文字の英数字とハイフンだけ(例 api・process)')
                continue
            for f in sorted(os.listdir(p)):
                fp = os.path.join(p, f)
                rel = 'knowledge/%s/%s' % (name, f)
                if os.path.isdir(fp):
                    add(rel + '/', 'unexpected-dir', 'ドメインのディレクトリの下にさらにディレクトリは置かない')
                elif f == '.gitkeep' or (f.startswith('_') and f.endswith('.md')):
                    continue   # 索引は _ 始まりを読み飛ばす。.gitkeep は空ドメインを残す慣習
                elif not f.endswith('.md'):
                    add(rel, 'unexpected-file', 'ドメインのディレクトリに置いてよいのは *.md だけ')
                else:
                    entry_files.append((rel, fp, name, f))
        elif name != '.gitkeep':
            add('knowledge/' + name, 'unexpected-file',
                'knowledge/ の直下にはドメインのディレクトリだけを置く(索引は同期時に生成されるので置かない)')

# --- エントリ: ファイル名と frontmatter ---
def parse_fm(path):
    lines = read(path).splitlines()
    if not lines or lines[0].strip() != '---':
        return None, 'frontmatter が無い(1行目が --- でない)'
    fm = {}
    for ln in lines[1:]:
        if ln.strip() == '---':
            return fm, None
        if ln[:1] in (' ', '\t') or ':' not in ln:
            continue
        k, v = ln.split(':', 1)
        fm[k.strip()] = v   # 生の値(後ろのコメントを見分けるため、ここでは strip しない)
    return None, 'frontmatter が閉じていない(閉じの --- が無い)'

bad_fm = set()
no_summary = set()
ids = {}          # 実効 id -> [rel]
supersedes_of = []  # (rel, 値)
# 値の後ろに `# コメント` があると、索引生成器と同期は行末までを値として読む(YAML の行末コメントは
# 解釈されない)。例えば `status: archived   # …` は status が archived と読まれず現行扱いになる。
# yosage-dev-harness-knowledge-template の出力は各項目に説明のコメントが付いているので、埋めた後に
# 消し忘れると当たる。summary は本文に # を含みうるので対象にしない。
COMMENT_RE = re.compile(r'(^|\s)#')
SINGLE = ['id', 'date', 'domain', 'tags', 'scope', 'status', 'supersedes', 'archived', 'source', 'checked']
def derive_id(filename):
    stem = filename[:-3]
    return re.sub(r'^\d{4}-\d{2}-\d{2}-', '', stem) or stem
REQUIRED = ['date', 'domain', 'tags', 'scope', 'status', 'summary']
for rel, fp, dom, fname in entry_files:
    m = FN_RE.match(fname)
    if not m:
        add(rel, 'bad-filename', 'ファイル名は YYYY-MM-DD-<スラッグ>.md(スラッグは小文字の英数字とハイフン)')
    fm, err = parse_fm(fp)
    if fm is None:
        add(rel, 'bad-frontmatter', err)
        bad_fm.add(fname)   # 同じ原因の summary 報告は出さない
        continue
    commented = set()
    for k in SINGLE:
        if k in fm and COMMENT_RE.search(fm[k]):
            commented.add(k)
            add(rel, 'trailing-comment',
                '%s の値の後ろに # のコメントがある。索引と同期は行末までを値として読むので、コメントは消す' % k)
    fm = {k: (v.strip() if k not in commented else '') for k, v in fm.items()}
    if 'summary' not in fm:
        no_summary.add(fname)
    # tags は空の [] でよいが項目自体は要る。summary の空は部品1(broken-summary)が報告するので、
    # ここでは項目の有無だけを見る(同じ原因を2本出さない。summary 項目が無いときはここで報告し、
    # 部品1の報告は出さない)。値にコメントがあった項目は上で報告済みなので、以降の値の検査は飛ばす。
    for k in REQUIRED:
        if k in commented:
            continue
        if k not in fm:
            add(rel, 'missing-field', 'frontmatter の必須項目 %s が無い' % k)
        elif k not in ('tags', 'summary') and not fm[k].strip():
            add(rel, 'missing-field', 'frontmatter の必須項目 %s が空' % k)
    d = fm.get('date', '').strip()
    if d and 'date' not in commented:
        if not valid_date(d):
            add(rel, 'bad-date', 'date は実在する YYYY-MM-DD')
        elif m and m.group(1) != d:
            add(rel, 'date-mismatch', 'date (%s) がファイル名の日付 (%s) と違う' % (d, m.group(1)))
    if fm.get('domain', '').strip() and fm['domain'].strip() != dom:
        add(rel, 'domain-mismatch', 'domain (%s) が置かれたディレクトリ名 (%s) と違う' % (fm['domain'].strip(), dom))
    if 'tags' in fm and 'tags' not in commented:
        t = fm['tags'].strip()
        if not (t.startswith('[') and t.endswith(']')):
            add(rel, 'bad-tags', 'tags は [a, b] の形(空なら [])')
    sc = fm.get('scope', '').strip()
    if sc and sc != 'global':
        add(rel, 'bad-scope', 'ストアのエントリの scope は global(local はストアに置かない)')
    st = fm.get('status', '').strip()
    if st and st not in STATUSES:
        add(rel, 'bad-status', 'status は active | superseded | archived')
    ar = fm.get('archived', '').strip()
    if ar and not valid_date(ar):
        add(rel, 'bad-date', 'archived は実在する YYYY-MM-DD')
    if st == 'archived' and not ar and 'archived' not in commented:
        add(rel, 'missing-field', 'status: archived のエントリには archived(退役日)が要る')
    src, chk = fm.get('source', '').strip(), fm.get('checked', '').strip()
    if src and not chk and 'checked' not in commented:
        add(rel, 'missing-field', 'source を持つエントリには checked(出典を確認した日)が要る')
    if chk and not valid_date(chk):
        add(rel, 'bad-date', 'checked は実在する YYYY-MM-DD')
    eid = fm.get('id', '').strip() or derive_id(fname)
    ids.setdefault(eid, []).append(rel)
    sup = fm.get('supersedes', '').strip()
    if sup:
        supersedes_of.append((rel, sup))

# --- ストアの中で解決できる参照: id の重複と supersedes ---
# id は [[id]] と supersedes の解決先なので、ストアの中で一意でないと参照が曖昧になる。
for eid, rels in sorted(ids.items()):
    if len(rels) > 1:
        for rel in rels:
            add(rel, 'duplicate-id', 'id (%s) がほかのエントリ (%d 件) と重複している' % (eid, len(rels) - 1))
for rel, sup in supersedes_of:
    for tok in [t.strip().strip('[]').strip('"\'').strip() for t in sup.split(',')]:
        if tok and tok not in ids:
            add(rel, 'bad-supersedes', 'supersedes の %s がストアの中のどのエントリの id にも一致しない' % tok)

# --- 部品1の結果: 壊れた summary / 索引に載らないエントリ ---
by_name = {}
for rel, fp, dom, fname in entry_files:
    by_name.setdefault(fname, []).append(rel)
for ln in read(os.path.join(work, 'index-check.err')).splitlines():
    m = re.match(r'^knowledge-index: (\S+): summary が', ln)
    if m and m.group(1) not in bad_fm and m.group(1) not in no_summary:
        for rel in by_name.get(m.group(1), ['knowledge/']):
            add(rel, 'broken-summary',
                'summary は1行のプレーンスカラーで書く(行頭に > や | を置かない・複数行にしない・空にしない)')
indexed = len([l for l in read(os.path.join(work, 'index-active.tsv')).splitlines() if l]) + \
          len([l for l in read(os.path.join(work, 'index-archive.tsv')).splitlines() if l])
if indexed != len(entry_files):
    add('knowledge/', 'not-indexed',
        '索引に載るエントリ数 (%d) がエントリのファイル数 (%d) と違う' % (indexed, len(entry_files)))

# --- 部品2の結果: 構造監査(global/ に対する検査) ---
for ln in read(os.path.join(work, 'audit.tsv')).splitlines():
    parts = ln.split('\t', 2)
    if len(parts) != 3:
        continue
    rel, code, msg = parts
    rel = re.sub(r'^knowledge/global/', 'knowledge/', rel)
    add(rel, 'audit:' + code, msg)

for rel, code, msg in out:
    print('%s\t%s\t%s' % (rel, code, msg))
print('knowledge-store-check: エントリ %d 件を検査し、違反 %d 件' % (len(entry_files), len(out)), file=sys.stderr)
sys.exit(1 if out else 0)
PY
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then knowledge_store_check "$@"; fi
