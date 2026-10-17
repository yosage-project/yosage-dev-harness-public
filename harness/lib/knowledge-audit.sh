#!/usr/bin/env bash
# knowledge-audit.sh — knowledge ベースの構造的欠陥を決定論で検出する(判断ゼロ)。
#
# 対象は「内容の陳腐化」(判断が要る。recall 時の fix-on-recall が別途担う)ではなく、
# 「参照が壊れている/書き方の規約に反している」構造的欠陥だけ。古さでは flag しない
# (frontmatter の date は出力に添えるだけの優先順位づけヒントで、単独の flag 条件にはしない)。
#
# 使い方: yosage-dev-harness-knowledge-audit <base-dir>
#   <base-dir> は skills/agents/rules/knowledge を含む階層(catalog-gen.sh と同じ契約。consumer
#   では <target>/.claude、このリポジトリ自身の自己導入先も同型)。走査対象は常に
#   `<base-dir>/knowledge` 固定(project-local ストアの置き場を変える機能は撤去済み。
#   ルール `knowledge`)。第2引数を渡された場合は使い方を表示して exit 2
#   (黙って無視しない)。
#   標準出力に1行1件、タブ区切り3列 `<relpath>\t<check-code>\t<メッセージ>` で列挙する
#   (検出0件なら無出力)。relpath の基点は `<base-dir>`。行の順序・件数だけが契約で、
#   桁位置は契約に含めない。標準出力の3列 TSV 契約は呼び出し元(書き込み時フック・on-demand CLI)
#   が機械的に解析しているため変更しない。
#
# 検査対象は project-local エントリ(<base-dir>/knowledge/<domain>/*.md。global/ と _* は除外)。
# global/(グローバル知識ストアの pull ミラー。opt-in で無いこともある)は「[[...]] / supersedes
# の解決先の一部」としてのみ使い、それ自身の構造は監査しない(pull 物でこのリポジトリからは
# 直せないため。travel 面チェック(issue番号の残留検査)だけ例外で global/ 自身の中身を見る)。
#
# 「走査したが報告0件」と「走査対象そのものが0件(=引数を間違えて何も見ていない)」は、標準出力
# だけでは区別できない(どちらも無出力・終了コード0)。この区別のために2つを追加する:
#   (1) 走査した project-local エントリ件数を、終了時に必ず標準エラー出力へ1行出す(既存呼び出し元は
#       標準出力を TSV として解析しており、標準エラー出力は捨てるか無視しているため無害。実際に
#       hooks/knowledge-index.sh は `2>/dev/null` で明示的に読み捨てている)。件数が0なら、それ自体が
#       「本当にエントリが無い(正当な新規導入先)」と「引数を間違えた」の両方でありうる合図になる
#       (件数のみでは両者を区別できないが、少なくとも「何も見ていない」ことが可視化される。区別は
#       (2) が担う)。
#   (2) 走査対象になる knowledge ディレクトリ(`<base-dir>/knowledge`)自身が実在しない場合、
#       次のように判定する。
#       - `<base-dir>` に設定ファイル(`yosage-dev-harness.local.json`。setup が必ず作る)がある:
#         導入先と分かる。知見が0件でディレクトリがまだ無い(空ディレクトリは git に残らず、別の
#         マシンで clone すると再び無くなる)正当な状態として、0件走査の1行を標準エラー出力へ出し、
#         終了コード0で終わる。
#       - 設定ファイルも無い: 引数の階層違い・cwd の取り違えの強い合図として扱い、走査せず
#         非ゼロで終了する(exit 1)。置き場の解決の失敗を黙って0件にしないための安全網。
#       ディレクトリの有無と設定ファイルの有無だけを見るので、ドメインサブディレクトリの有無や
#       配下のファイル数は問わない。
set -uo pipefail

ka_log() { printf 'knowledge-audit: %s\n' "$1" >&2; }

knowledge_audit() {  # <base-dir>
  local base="${1:-}"
  if [ "$#" -gt 1 ]; then
    ka_log "使い方: yosage-dev-harness-knowledge-audit <base-dir>(第2引数は廃止されました)"
    return 2
  fi
  [ -n "$base" ] && [ -d "$base" ] || { ka_log "ディレクトリが不正: ${base:-(空)}"; return 1; }
  local kcheck="$base/knowledge"
  if [ ! -d "$kcheck" ]; then
    # 0件にするのは knowledge が本当に何も無いとき(! -e かつ ! -L)だけ。通常ファイル・壊れた
    # シンボリックリンクは異常なので、設定ファイルがあっても下の失敗に落とす。
    if [ ! -e "$kcheck" ] && [ ! -L "$kcheck" ] && [ -f "$base/yosage-dev-harness.local.json" ]; then
      ka_log "project-local エントリを 0 件走査し、構造的欠陥/通知を 0 件報告しました(knowledge/ が無い導入先)"
      return 0
    fi
    ka_log "$kcheck が無い(<base-dir> には knowledge/ を含む階層 — consumer では <target>/.claude — を渡してください)"; return 1
  fi
  command -v python3 >/dev/null 2>&1 || { ka_log "python3 が無い → 監査を skip"; return 0; }
  # プラグインのルート: 監査スクリプト自身の位置(`$(dirname BASH_SOURCE)/..`)から自己解決する。
  # 呼び出し元(consumer の `.claude` を渡す base-dir)には依存しない。実際のプラグイン導入では
  # このスクリプトが `<plugin-root>/lib/knowledge-audit.sh` に置かれる(このリポジトリ自身の
  # dogfood/自己監査でも、呼ばれるスクリプトの実体は常に `harness/lib/knowledge-audit.sh` なので
  # `<plugin-root>` は `harness/` に一致する)。
  local plugin_root
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  python3 - "$base" "$plugin_root" <<'PY'
import sys, os, glob, re, subprocess

base = os.path.abspath(sys.argv[1])
plugin_root = os.path.abspath(sys.argv[2])
kdir = os.path.join(base, 'knowledge')
gdir = os.path.join(kdir, 'global')
# `global_present` の実体は「ミラーが実際に同期されているか」であり、「置き場ディレクトリが
# 存在するか」ではない。同期が中断した場合・同期前に置き場だけ作られた場合・何かが中身を
# 消した場合、ディレクトリ自体は存在するが中身が空になる。この状態で `os.path.isdir(gdir)` だけを
# 見ると、resolve_link/resolve_knowledge_id がミラー側 id 集合(空集合)との不一致を dangling と
# 断定してしまい、「不在」なら出ない偽陽性が「空」でだけ出る(不在は正しく skip されるのに、空だけ
# 誤検知になるという非対称)。ディレクトリの有無ではなくエントリの有無で判定することで、
# 「空」を「不在」と同じ経路(判断ゼロ=解決できないが構造的欠陥でもない、として skip)に揃える。
global_dir_exists = os.path.isdir(gdir)
# path 参照(check3)の解決基点。<base> は常に実物の `.claude`(catalog-gen.sh と同じ契約。
# skills/agents/rules の親)を渡す不変を保つので、その1つ上が常にリポジトリ(または導入先
# プロジェクト)のルートになる。
repo_root = os.path.dirname(base.rstrip(os.sep))
# 出力(add() が書く relpath)の基点は <base-dir>(walk 対象が `<base-dir>/knowledge` なので、
# relpath は "knowledge/..." という従来形式のまま)。
report_base = base

# check3 の解決候補ルート一覧。本文中のパス言及は「repo ルート相対」で書く規約
# (grounding-check-resolves-paths-repo-root-relative の判断を踏襲)だが、knowledge エントリの
# 地の文では配布 payload(plugin_root)・導入先(.claude/=base)のどちらから見た相対パスかを省略して
# 書く実例が多い(例: 実体が `harness/hooks/notify.sh` にあるのに `hooks/notify.sh` と書く)。解決の
# 試行を repo ルート相対だけで終わらせず、plugin_root とその既知サブディレクトリ・base(.claude/)
# ルートも候補に加える。
#
# 既知サブディレクトリの一覧は SSOT を別ファイルに持たない(配布物の状態管理ファイルは撤去済み)。
# プラグインの構成は固定(skills/agents/hooks/lib/github/knowledge/config/rules)なので、
# ここでハードコードする(変わる頻度が低く、変わったらこの1箇所を直せばよい)。
PAYLOAD_SUBDIRS = ['skills', 'agents', 'hooks', 'lib', 'github', 'knowledge', 'config', 'rules', 'review']

# --- 論理パス(`yosage-dev-harness:<harness/ からの相対パス>`)の判定・解決 ---
# bash 版(lib/knowledge-logical-path.sh の ydh_lp_is_logical/ydh_lp_resolve)と同じ規則を
# python 側でも持つ(本体がここでは python 実装のため、呼び出し元言語ごとに1つずつ実装を持つ。
# 規則自体はどちらも「接頭辞 yosage-dev-harness: + / を含む相対パス、`..` を含めば不可」で
# 単純なので、2実装間の drift リスクは小さいと判断した)。
LP_PREFIX = 'yosage-dev-harness:'

def lp_is_logical(token):
    if not token.startswith(LP_PREFIX):
        return False
    rest = token[len(LP_PREFIX):]
    return '/' in rest

def lp_resolve(token):
    # 使用中の版のプラグイン(plugin_root)の中の絶対パスを返す。実在しない/`..`を含む場合は None。
    rel = token[len(LP_PREFIX):]
    if '..' in rel:
        return None
    target = os.path.join(plugin_root, rel)
    return target if os.path.isfile(target) else None

# --- 導入先のパス(プラグイン形では存在しない旧表記)の検出 ---
# rules 配下の旧サブディレクトリ名(このリポジトリ自身の内部パスと同じ文字列になるため、
# 静的検査(91-inject.sh の「旧レイアウト参照の残留検査」)に自己検出されないよう文字列を
# 連結で組み立てる。同種の回避は test/lib/bin-checks.py の _OLD_PRODUCT_NAME に前例がある)。
_LEGACY_RULES_SUBDIR = 'rules' + '/harness/'
LEGACY_PAYLOAD_RE = re.compile(
    r'\.claude/(?:skills|agents|lib|hooks)/[A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)*'
    r'|\.claude/' + _LEGACY_RULES_SUBDIR + r'[A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)*'
)

def legacy_payload_target(m):
    # LEGACY_PAYLOAD_RE がマッチした旧パスの、プラグイン内での実体を計算する
    # (knowledge-convert-paths.sh の対応表と同じマッピング。`.claude/rules` 配下の旧 `harness/<x>`
    # は `rules/<x>` へ読み替える特別扱いを含む。汎用の dotclaude_to_plugin_candidate は
    # この読み替えを持たない — `rules` サブディレクトリを rest そのままで結合するため、
    # `.claude/rules` 配下の旧 harness/<x> 形では常に存在しない候補になる — ので、ここでは使わない)。
    prefix = '.claude/'
    if not m.startswith(prefix):
        return None
    rest = m[len(prefix):]
    if rest.startswith(_LEGACY_RULES_SUBDIR):
        rel = 'rules/' + rest[len(_LEGACY_RULES_SUBDIR):]
    else:
        rel = rest
    return os.path.join(plugin_root, rel)

_gitignore_cache = {}

def _git_cwd_for(path):
    # `git check-ignore` はパスが cwd の git 作業木の外だと fatal error(returncode 128)になる。
    # plugin_root は repo_root(導入先/consumer のリポジトリ)とは別の git 作業木にありうる
    # (プラグイン形では常態: 導入先のリポジトリと、プラグイン自体が置かれた場所は別リポジトリ)。
    # 候補パスがどちらの木に属すかで cwd を選び分ける(plugin_root 配下なら plugin_root、
    # それ以外は repo_root)。
    ap = os.path.abspath(path)
    if ap == plugin_root or ap.startswith(plugin_root + os.sep):
        return plugin_root
    return repo_root

def is_gitignored(path):
    if path in _gitignore_cache:
        return _gitignore_cache[path]
    try:
        r = subprocess.run(['git', 'check-ignore', '-q', path], cwd=_git_cwd_for(path),
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        result = (r.returncode == 0)
    except Exception:
        result = False
    _gitignore_cache[path] = result
    return result

def batch_check_ignored(paths, cwd):
    # `git check-ignore` を1プロセスで多数のパスに対してまとめて判定する(check3 のコスト削減の要)。
    # `-q` は単一パス専用のため複数パスには使えない(`git check-ignore --help` の OPTIONS 節:
    # "-q, --quiet ... This is only valid with a single pathname")。代わりに `--stdin -z` で
    # NUL区切りのパス一覧を渡し、無視対象と判定されたパスだけが同じく NUL区切りで返る(OUTPUT 節:
    # マッチしないパスは何も出力されない)。件数に関わらず**この呼び出し1回**で済む
    # (引数列ではなく標準入力でパスを渡すため、件数が多くても ARG_MAX の制約を受けない)。
    # <cwd> を呼び出し元(_prime_gitignore_cache)が渡す: paths は同じ git 作業木に属するものだけを
    # まとめる契約(cwd の木の外のパスを混ぜると `_git_cwd_for` と食い違い fatal error になる)。
    #
    # 戻り値は「成功(集合)」と「失敗(None)」を区別する(一次レビューで指摘・修正)。
    # 一括呼び出しは N 件(監査全体の候補)をまとめて判定するため、**この1回が失敗すると
    # 影響が候補全件に及ぶ**——個別呼び出し(is_gitignored の1件ずつの判定)が失敗しても影響が
    # その1件に閉じるのとは非対称。したがって失敗時に空集合(set())を返してはいけない: 呼び出し元
    # (_prime_gitignore_cache)が空集合を「該当ゼロ件(=全件が無視されていない)」と解釈して
    # _gitignore_cache へ書き込むと、キャッシュが埋まってしまい、本来キャッシュ未ヒットから
    # 個別呼び出しへフォールバックすべき経路が発火しなくなる(→ 正当に gitignore された参照が
    # 軒並み構造的欠陥として誤検知される)。
    # - **成功・該当ゼロ件**(returncode==1・実際に何もマッチしなかった): 下の通常の return 文で
    #   本物の空集合を返す(これは正しい「無視されていない」判定であり、失敗ではない)。
    # - **失敗**(想定外の returncode・タイムアウトを含む例外)は None を返す。タイムアウト
    #   (`subprocess.TimeoutExpired`)は `Exception` のサブクラスなので `except Exception` に含まれ、
    #   他の失敗(git 不在等)と同じ扱いになる(専用の分岐は不要)。
    if not paths:
        return set()
    try:
        payload = ''.join(p + '\0' for p in paths)
        r = subprocess.run(['git', 'check-ignore', '--stdin', '-z'], cwd=cwd,
                            input=payload, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            timeout=30, text=True)
        if r.returncode not in (0, 1):
            return None
        return {p for p in r.stdout.split('\0') if p}
    except Exception:
        return None

# `<base>`(常に `.claude` 導入先ディレクトリ)自身が丸ごと gitignore 対象かを判定する。
# `base` 自体への git check-ignore は(このリポジトリの `/.claude/*` のような)ディレクトリ限定の
# ワイルドカードパターンだとディレクトリそのものにはマッチしない(git の仕様。中身にしかマッチしない)ため、
# `base` 直下の実在しない代表パス(プローブ)で判定する。個別の否定例外(`!/.claude/knowledge/` 等)に
# 誤って引っかからないよう、既存のどの構造名とも衝突しない汎用名を使う。
def _base_wholesale_ignored():
    probe = os.path.join(base, '.knowledge-audit-basepoint-probe')
    return is_gitignored(probe)

# 丸ごと無視されている構成(このリポジトリ自身の dogfood install 一式や、consumer が独自に
# `.claude/` を丸ごと gitignore する運用)では、`.claude/<subdir>/...` 形のどんな候補パスも
# 参照の中身と無関係に「無視されている」と判定されてしまう(→ 真に壊れている参照まで
# skip され検査が無効化される)。そうでない通常の導入先では、配布物として実際に伝播する
# 個別 `.gitignore`(review/.gitignore の criteria.md・knowledge/.gitignore の global/・
# .gitignore の *.local.* 等)を `.claude/` 基点でも正しく判定できる必要がある(そうしないと、
# 正当に gitignore された参照が skip されず構造的欠陥として誤検知される)。
# 両者は base 自身が丸ごと無視対象かどうかで綺麗に分岐するため、その判定結果で `.claude/` 基点を
# gitignore 判定の候補に含めるかどうかを切り替える。harness/(配布 payload の実体)基点は
# この丸ごと無視の影響を受けないため、これまで通り無条件に含める。
BASE_WHOLESALE_IGNORED = _base_wholesale_ignored()

# CANDIDATE_ROOTS(実在解決の候補ルート): 「監査スクリプト自身のプラグインのルートの直下を
# 候補にする」解決(prefix 省略で plugin_root 相対に解決する経路)は含めない(一次レビュー指摘:
# 「CLI の撤去の段で入れた…解決は、論理パスの解決に置き換える」という要求どおり。
# 論理パス(`yosage-dev-harness:<相対パス>`)・`.claude/` 前置き(dotclaude_to_plugin_candidate。
# legacy-payload-path で報告する対象として残す)のどちらでもない、素の prefix 省略パス
# (`hooks/real-hook.sh` 等)は、以後は何の報告も無く解決されることは無い(=broken-path-ref
# として検出される。この Sub-issue の目的である「配布物のパスを論理パスへ一本化する」ことの
# 迂回路を塞ぐ)。導入先(consumer)のリポジトリの中のパスとしての解決(repo_root・base とその
# 既知サブディレクトリ)は影響を受けず残す。
CANDIDATE_ROOTS = [repo_root, base]
# IGNORE_CHECK_ROOTS(gitignore 判定専用の候補ルート)は CANDIDATE_ROOTS とは別物であり、
# plugin_root を含めたまま維持する(実在解決を経由しない: resolve_existing が失敗した参照に
# 対して「gitignore された/opt-in の領域か」を判定するためだけに使う。plugin_root 配下の
# sync 生成物(review/criteria.md 等)を prefix 省略で書いた既存の実例が、実在解決の経路を
# 失っても引き続き「gitignore された領域として skip」に正しく分類されるようにするため)。
IGNORE_CHECK_ROOTS = [plugin_root]
if not BASE_WHOLESALE_IGNORED:
    IGNORE_CHECK_ROOTS.append(base)
for _sub in PAYLOAD_SUBDIRS:
    IGNORE_CHECK_ROOTS.append(os.path.join(plugin_root, _sub))
    CANDIDATE_ROOTS.append(os.path.join(base, _sub))
    if not BASE_WHOLESALE_IGNORED:
        IGNORE_CHECK_ROOTS.append(os.path.join(base, _sub))

def dotclaude_to_plugin_candidate(ref_path):
    # `.claude/<subdir>/...` 形の明示参照(install 先から見た書き方。例:
    # `.claude/agents/librarian.md`)を、対応する配布 payload 実体 `<plugin_root>/<subdir>/...` へ
    # 変換した候補を1つ返す(対応しなければ None)。CANDIDATE_ROOTS の走査だけでは救えない: そちらは
    # 「prefix 省略」(`hooks/real-hook.sh` のような repo ルート/plugin ルート相対の書き方)を
    # 補うものであり、ref_path 自身に明示された `.claude/` prefix を plugin_root へ**置き換える**
    # 変換は行わない。プラグイン形では導入先に `.claude/<subdir>`(knowledge を除く)自体が存在
    # しないため、この変換が常用の解決経路になる。`.claude/` の直後が既知サブディレクトリ
    # (PAYLOAD_SUBDIRS)に含まれる場合のみ変換する(無関係な `.claude/xyz` を plugin_root/xyz に
    # 化けさせて誤って解決してしまわないため)。
    prefix = '.claude/'
    if not ref_path.startswith(prefix):
        return None
    rest = ref_path[len(prefix):]
    for sub in PAYLOAD_SUBDIRS:
        if rest == sub or rest.startswith(sub + '/'):
            return os.path.join(plugin_root, rest)
    return None

def candidate_targets(ref_path):
    if os.path.isabs(ref_path):
        return [ref_path]
    targets = [os.path.join(r, ref_path) for r in CANDIDATE_ROOTS]
    alt = dotclaude_to_plugin_candidate(ref_path)
    if alt:
        targets.append(alt)
    return targets

def resolve_existing(ref_path):
    for t in candidate_targets(ref_path):
        if os.path.isfile(t):
            return t
    return None

def ignore_check_candidates(ref_path):
    # any_candidate_gitignored が判定に使う候補パス一覧(gitignore 判定専用。実在解決の
    # candidate_targets とは別物 — CANDIDATE_ROOTS ではなく IGNORE_CHECK_ROOTS を使う)。
    if os.path.isabs(ref_path):
        return [ref_path]
    return [os.path.join(r, ref_path) for r in IGNORE_CHECK_ROOTS]

def any_candidate_gitignored(ref_path):
    # 「gitignore された/opt-in で不在たりうる」参照(global/ ミラー・*.local.*・sync 生成物の
    # review/criteria.md 等)は、実在するかどうかを判断する材料が無い(判断ゼロの原則に反する)。
    # check4/5/8 が global/ 不在時に dangling を断定せず skip するのと同じ扱いを check3 にも揃える:
    # 候補パスのどれかが git check-ignore で無視対象と判定されたら「解決できないが構造的欠陥でもない」
    # として skip する(git が無い/このリポジトリが git 管理下に無い場合は安全側で「無視されていない」
    # 扱いにし、これまで通り broken 判定へフォールバックする)。
    return any(is_gitignored(c) for c in ignore_check_candidates(ref_path))

ELISION_SEGMENT_RE = re.compile(r'^\.{2,}$')

def has_elision_segment(ref_path):
    # `.../skills/foo/SKILL.md` のような先頭 `...` 省略記法(コーパスに複数実例がある確立した書き方)は
    # 何を省略したか本文からは決定できない。解決を試みず(=実在/不在の主張をせず)スキップする。
    return any(ELISION_SEGMENT_RE.match(seg) for seg in ref_path.split('/'))

HEADING_RE = re.compile(r'^##\s+(.*\S)\s*$')
EVIDENCE_HEADING_RE = re.compile(r'^根拠(\s*/\s*実例)?$')

def evidence_section_flags(lines):
    # 各行が「## 根拠 / 実例」(または旧来の「## 根拠」)節に属するかを返す。
    # 節の境界は直近に出た `##` 見出しで決まる(エントリ雛形の節構成に基づく判定。新しい規則の発明ではない)。
    flags = []
    in_evidence = False
    for ln in lines:
        m = HEADING_RE.match(ln)
        if m:
            in_evidence = bool(EVIDENCE_HEADING_RE.match(m.group(1)))
        flags.append(in_evidence)
    return flags

findings = []  # (relpath, check_code, message)

def add(path, code, msg, date=None):
    rel = os.path.relpath(path, report_base)
    if date:
        msg = f"{msg} [date: {date}]"
    findings.append((rel, code, msg))

def frontmatter(path):
    # 1行 `key: value` のみ対応(knowledge-index.sh / catalog-gen.sh と同じ制約。
    # 値中の `:` や `#` はそのまま保持。YAML コメント/ブロックスカラーは非対応)。
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
        d[k.strip()] = v.strip()
    return d

def read_lines(path):
    try:
        return open(path, encoding='utf-8').read().splitlines()
    except Exception:
        return []

def derive_id(filename):
    # knowledge-index.sh の derive_id と同じ規則(id 省略時の実効 id 導出。省略は救済ではなく正式仕様)。
    stem = filename[:-3] if filename.endswith('.md') else filename
    stripped = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', stem)
    return stripped or stem

def collect_entries(domain_root, exclude_global):
    # <domain_root>/<domain>/*.md を走査。exclude_global=True なら domain=='global' を除外
    # (project-local の走査に使う。global mirror 自体の走査は exclude_global=False で呼ぶ)。
    out = []
    for f in sorted(glob.glob(os.path.join(domain_root, '*', '*.md'))):
        dom = os.path.basename(os.path.dirname(f))
        name = os.path.basename(f)
        if name.startswith('_'):
            continue
        if exclude_global and dom == 'global':
            continue
        fm = frontmatter(f)
        eff_id = (fm.get('id') or '').strip() or derive_id(name)
        out.append({
            'path': f, 'domain': dom, 'name': name,
            'fm': fm, 'id': eff_id, 'lines': read_lines(f),
            'date': fm.get('date', '').strip(),
        })
    return out

local_entries = collect_entries(kdir, exclude_global=True)
global_entries = collect_entries(gdir, exclude_global=False) if global_dir_exists else []
# ディレクトリが実在しても中身が0件なら「未同期」と区別できない(上記コメント参照)ので、
# 判定は実際に読み取れたエントリの有無で行う(ディレクトリの有無そのものではない)。
global_present = bool(global_entries)

local_ids = {e['id'] for e in local_entries}
global_ids = {e['id'] for e in global_entries}

def frontmatter_ns(base_dir, glob_pat, key_fallback_from_dirname):
    names = set()
    for f in sorted(glob.glob(os.path.join(base_dir, glob_pat))):
        fm = frontmatter(f)
        name = (fm.get('name') or '').strip()
        if not name:
            name = os.path.basename(os.path.dirname(f)) if key_fallback_from_dirname \
                else os.path.splitext(os.path.basename(f))[0]
        names.add(name)
    return names

# プラグイン形では skill/agent/rule は導入先(.claude/)に存在せず、常に plugin_root(監査
# スクリプト自身の位置から自己解決したプラグインのルート)の下にある。
skill_names = frontmatter_ns(plugin_root, os.path.join('skills', '*', 'SKILL.md'), True)
agent_names = frontmatter_ns(plugin_root, os.path.join('agents', '*.md'), False)
# rule は frontmatter を持たない。名前空間はファイル名そのもの。
rule_names = {os.path.splitext(os.path.basename(f))[0]
              for f in glob.glob(os.path.join(plugin_root, 'rules', '*.md'))}

def resolve_link(token):
    # [[...]] の解決(4名前空間: knowledge id(local+global) / skill / agent / rule)。
    # global/ が無い環境では「local にも skill/agent/rule にも無い」トークンは
    # ストア側にしか無い可能性を排除できないため dangling とせず skipped にする。
    if token in local_ids or token in skill_names or token in agent_names or token in rule_names:
        return 'resolved'
    if global_present:
        return 'resolved' if token in global_ids else 'dangling'
    return 'skipped'

def resolve_knowledge_id(token):
    # supersedes: の解決(knowledge id 名前空間のみ。skill/agent/rule は supersedes の対象外)。
    if token in local_ids:
        return 'resolved'
    if global_present:
        return 'resolved' if token in global_ids else 'dangling'
    return 'skipped'

NUM_RE = re.compile(r'#(\d+)')
# ↑ `/` は含めない: 連続する issue 参照を列挙・範囲で書く形(`<repo>#N/#M`)は、2つめ以降が
# 「#の直前が/」で qualified 誤判定され見逃される偽陰性があった。URL のパス・フラグメント
# (`path/to/file.md#L23` 等)の誤検知は、`/` を qualified 文字集合から抜くこと自体では起きない
# (URL 由来の `#N` は別途 URL スパンとして除外する。下記 check1)。
QUALIFIED_PREV = re.compile(r'[A-Za-z0-9_.-]')
LINK_RE = re.compile(r'\[\[([A-Za-z][A-Za-z0-9_-]*)\]\]')
# ↑ id/name(kebab-slug)以外の文字で始まる `[[...]]` は wiki-link ではない実例がある:
#   正規表現の POSIX 文字クラス `[[:space:]]` や、構文説明としての `[[...]]`/`[[]]` リテラル自体。
# 先頭を英字に絞ることでこれらを取りこぼす(誤検知しない)。
BACKTICK_RE = re.compile(r'`([^`]+)`')
# ↓ check3 が「パスらしき文字列」として拾う末尾拡張子の allowlist。
# 母集団はこのリポジトリ自身ではなく「配布先」(この監査はこのリポジトリの外、任意の言語スタックの
# consumer プロジェクトへ install されて動く。knowledge エントリはその consumer 側のコードを参照する)。
# consumer が実際に使う言語スタックは列挙しきれないので厳密な実測はできない
# (この点は当初このリポジトリ自身の payload/テスト/設定/ドキュメントだけを走査して導いており、
# 母集団の取り違えだった)。代わりに、ソフトウェア開発で広く使われる主要カテゴリ
# (ドキュメント・設定/データ・シェル・システムズ言語・スクリプト言語・Web/フロントエンド・
# モバイル・データ/クエリ・インフラ)を横断的にカバーする一般的な拡張子の集合を採る。
# 各カテゴリの拡張子は、check3 のもう一方の偽陽性クラス(パスと同型の非パス識別子。実例:
# GCP IAM ロール ID `roles/run.invoker` `roles/iam.serviceAccountUser` の末尾 invoker/admin/
# serviceAccountUser/writer/reader/viewer/owner/creator/updater/deleter/manager 等)と
# 衝突しないことを確認済み(いずれも本 allowlist の語と一致しない)。
# それでも網羅はできない(偽陰性が残る): 上記カテゴリに無い、より珍しい/レガシーな言語・
# 拡張子を持たないファイル名規約(Dockerfile・Makefile 等。本パターンは末尾 `.<拡張子>` を
# 要求するため元々対象外)・画像/フォント等のバイナリ資産は allowlist に入れていない。
# 新しい拡張子の実例が観測されたら追加すればよい(密なdenylistの延長ではなく、カテゴリに
# 基づく allowlist の漸進的な拡張)。
#
# ロールアウトの懸念(狭い allowlist の期間に沈黙していた検出が、広げた瞬間に一斉に出て
# 導入先の対応量を超えるのでは、という懸念)について、この監査の実際の導入先2件(ローカル
# エントリ計210件)を対象に、(1) 拡張前後で broken-path-ref の検出件数を比較し差が無いこと、
# (2) その理由が「拡張子を絞らず抽出した約480件のパスらしき候補のうち、拡張後にだけ含まれる
# 拡張子(69種のうち拡張前7種を除いた残り)を使う候補が実質1件(架空の例示)しか無かった」こと、
# の両方を確認した。**この結果は「拡張しても一般に burst が起きない」ことの証明ではない**——
# 確立できたのは「拡張子への言及がこの2導入先ではもともと少なかった」ことだけであり、拡張後の
# 拡張子(TypeScript の `.tsx`/`.vue` 等)への言及が多い導入先については、この測定は何も示して
# いない。それでも「取り込み前の件数見積り・検出の一括化」といった追加の緩和機構は今は作らず、
# 実際に大量検出を報告する導入先が観測された時点で再検討する(証明されていない対策を先に
# 作らない)。ただし、その「観測」を拾う自動的な経路は無い(この監査の書き込み時フックは編集
# された1エントリしか見ず、オンデマンド実行は誰かが能動的に走らせて出力を読んだときだけ発火
# する)ため、閾値を超えても気づかれないまま残る可能性がある。
KNOWN_PATH_EXTENSIONS = (
    # ドキュメント
    'md', 'mdx', 'rst', 'adoc', 'txt',
    # 設定/データ
    'json', 'yaml', 'yml', 'toml', 'ini', 'xml', 'csv', 'env', 'properties',
    'cfg', 'conf', 'lock', 'example', 'gitignore',
    # シェル
    'sh', 'bash', 'zsh', 'ps1', 'bat', 'cmd',
    # システムズ/コンパイル言語
    'c', 'h', 'cpp', 'hpp', 'cc', 'cxx', 'go', 'rs', 'java', 'kt', 'kts',
    'swift', 'cs', 'm', 'mm',
    # スクリプト言語
    'py', 'rb', 'php', 'pl', 'pm', 'lua', 'r',
    # Web/フロントエンド
    'js', 'jsx', 'mjs', 'cjs', 'ts', 'tsx', 'vue', 'svelte',
    'html', 'htm', 'css', 'scss', 'sass', 'less',
    # モバイル
    'dart',
    # データ/クエリ
    'sql', 'graphql', 'gql', 'proto',
    # インフラ/ビルド
    'tf', 'tfvars', 'gradle',
)
_EXT_ALT = '|'.join(re.escape(ext) for ext in KNOWN_PATH_EXTENSIONS)
# ↓ セグメント文字クラスに `()` を追加: ファイルベースルーティングを持つフレームワーク
# (Next.js のルートグループ `(group)` 等)ではディレクトリ名に括弧を使うのが標準的な記法で、
# 括弧を含まない旧文字クラスだとこの実在パスを拾えない。影響のしかたは2つの正規表現で異なる:
#   - `PATHLINE_RE`(下記。行頭アンカー無し・`re.findall` で行全体を走査)は、括弧のところで
#     トークンが途切れたあと、括弧より後ろにさらに `/` を挟むセグメントがあれば
#     (`.../(group)/sub/real.sh:2` のような形)、その部分だけを独立した新しいパスとして
#     拾い直してしまい、実在するファイルを broken 扱いする(誤検知/偽陽性)。
#   - `BARE_PATH_RE`(直下。`^...$` の完全一致・バッククォートで単離済みのトークンに対して
#     `.match()`)は、トークン中のどこか一箇所でも括弧があれば完全一致自体が成立しないため、
#     誤検知はしない代わりに実在チェックそのものが素通りする(可視性の欠落。実在しないパスに
#     括弧が含まれていても検出できなくなる)。
# あわせて拡張子側を上記 allowlist に限定し、`セグメント/セグメント.<英数字>` という構造だけで
# パスと同型になる非パス識別子(GCP IAM ロール ID `roles/run.invoker` 等)を拾わないようにする。
# ↓ 拡張子の照合は大文字小文字を無視する(`re.IGNORECASE`)。実ファイルシステムの拡張子は
# 大文字(`README.MD` 等)でも実在しうるが、旧実装(`[A-Za-z0-9]+`)は大文字小文字を区別せず
# 拾えていたため、allowlist を素朴に小文字の語だけで作ると大文字拡張子への壊れた参照が
# 静かに検出されなくなる(allowlist 導入自体が生む新しい regression。一次レビューで検出)。
# 大文字小文字を無視しても、拡張子は「トークンの末尾セグメント全体」に対する完全一致
# (部分一致ではない)であり、この監査のもう一方の偽陽性クラス(パスと同型の非パス識別子。
# GCP IAM ロール ID の末尾 `invoker`/`admin`/`serviceAccountUser`/`writer` 等。大文字始まりの
# `Admin`/`Writer` 等を含めて確認済み)はいずれも KNOWN_PATH_EXTENSIONS のどの語とも
# 大文字小文字を無視しても一致しないため、衝突は起きない。
BARE_PATH_RE = re.compile(
    r'^[A-Za-z0-9_.\-()]+(?:/[A-Za-z0-9_.\-()]+)+\.(?:' + _EXT_ALT + r')$',
    re.IGNORECASE,
)
URL_RE = re.compile(r'[A-Za-z][A-Za-z0-9+.\-]*://\S*')
HOSTPORT_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._\-]*:[0-9]+/\S*')
PATHLINE_RE = re.compile(
    r'/?[A-Za-z0-9._\-()]+/[A-Za-z0-9._/\-()]*\.(?:' + _EXT_ALT + r'):[0-9]+',
    re.IGNORECASE,
)
# ↑ 上4つは check3(破損パス参照検査)専用。「URL/hostport 文字列を消してからパスを抽出する」
# 用途であり、末尾が `\S*`(空白でしか止まらない)でも実害が無い(消しすぎても後続のパス抽出には
# 影響しない)。この前提を持つ `URL_RE` を check1(下記 url_spans)へそのまま転用しない
# (一次レビュー指摘: URL の直後に空白なしで地の文が続く実運用の書き方(日本語は特に多い)だと、
# `\S*` がその地の文まで丸ごと URL 範囲として飲み込み、直後の地の文の `#N` を見逃す新しい偽陰性を
# 作り込む。「URL を消せればよい」(消しすぎ許容)と「URL の範囲を正確に取る」(消しすぎ不可)は
# 別要件であり、要件が違う primitive は共有せず専用に定義する)。
URL_FRAGMENT_SPAN_RE = re.compile(
    r"[A-Za-z][A-Za-z0-9+.\-]*://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]*"
)
# ↑ check1 専用: URL に現れうる文字(RFC 3986 の unreserved + gen-delims + sub-delims + `%`)だけの
# 文字クラスで区切る。日本語の文字・`、`・`。` 等はこの文字クラスに含まれないため、URL の直後に
# 空白が無くてもそこで自然にマッチが止まる。`#` は URL の正当な構成文字(フラグメント)なので
# 文字クラスに含める(`.../path#N` のような形は URL 全体がマッチし、内部の `#N` を正しく除外できる)。

# --- check1/check2 共通: 「参照」と「例示」の区別(コードスパンの内か外か) ---
# `#N` には「参照」(その issue を実際に指す。地の文に書く規約)と「例示」(その書き方自体を説明する
# リテラル。正規表現のテストケース・hex カラーコード・再現用の入力等で番号は load-bearing でない)が
# 混在する。実コーパスの全数計測(裸の #N: コード内26件/地の文0件、実際の参照: 地の文98/98)により、
# ヒューリスティックではなく構文(コードスパンの内か外か)で厳密に区別できることが確認されている。
# 書き方の規約(参照は地の文・コードスパンはリテラル)はルール `knowledge` 参照。
FENCE_RE = re.compile(r'^\s*(`{3,}|~{3,})')

def fenced_code_flags(lines):
    # 各行が「フェンスされたコードブロックの内側」かを返す(フェンス区切り行自身も内側として扱う。
    # evidence_section_flags と同型の「直近の状態を行ごとに引き継ぐ」パターンを流用)。
    flags = []
    in_fence = False
    fence_ch = ''
    fence_len = 0
    for ln in lines:
        m = FENCE_RE.match(ln)
        cur = in_fence
        if m:
            marker = m.group(1)
            if not in_fence:
                in_fence, fence_ch, fence_len = True, marker[0], len(marker)
                cur = True
            elif marker[0] == fence_ch and len(marker) >= fence_len:
                in_fence = False
                cur = True
            else:
                cur = True
        flags.append(cur)
    return flags

def inline_code_spans(line):
    # CommonMark 準拠のインラインコードスパン判定: 開始のバッククォート「連続列」(run)と、
    # それと同じ長さの連続列で閉じる(ダブルバッククォート等で囲むとスパン内にリテラルの
    # バッククォートを埋め込める、という正式な記法。例: ``code with ` inside``)。
    # 素朴な「単一バッククォートのペア」(check3 が path 抽出に使う BACKTICK_RE の前提)ではなく、
    # run の長さを数えて等長の run同士でペアリングする。BACKTICK_RE とは独立に持つ
    # (共用すると path 抽出側の挙動を変えてしまうため。破損パス参照検査は既存のまま)。
    #
    # 左から順に走査し、各 backtick run を「開始候補」として、そこから先で最初に現れる
    # 同じ長さの run を閉じ側として探す(異なる長さの run はスパン内容の一部として読み飛ばす)。
    # 見つかればそのスパンを確定し、走査位置を閉じ run の直後へ進める(スパン内側は二度と
    # 走査しない=一度スパンの内容として消費された run が、スパン外の別 run と再ペアリングされる
    # ことは無い)。見つからなければ、その開始候補は非デリミタ(リテラル)として扱い、走査位置を
    # その run の直後へ進める(このrun自身は次のスパン候補にはならない。CommonMark の参照実装
    # (commonmark.js/commonmark.py)と同じ「1パス・左から・貪欲」の意味論)。
    # 旧実装(行全体の run を先頭から同じ長さ同士で総当りペアリング)は、既に別スパンの内容として
    # 消費されたはずの run を「未使用」のまま残し、行の離れた場所にある無関係な run と誤って
    # ペアリングしてしまうバグがあった(delimiter の横取り。一次レビューで発見・修正)。
    n = len(line)
    spans = []
    i = 0
    while i < n:
        if line[i] != '`':
            i += 1
            continue
        j = i
        while j < n and line[j] == '`':
            j += 1
        run_len = j - i
        k = j
        close = None
        while k < n:
            if line[k] == '`':
                k2 = k
                while k2 < n and line[k2] == '`':
                    k2 += 1
                if (k2 - k) == run_len:
                    close = (k, k2)
                    break
                k = k2
            else:
                k += 1
        if close:
            spans.append((i, close[1]))
            i = close[1]
        else:
            i = j
    return spans

def in_inline_code(line, pos):
    # `pos` がインラインコードスパン(区切りのバッククォート run 自体を含む)の内側かを判定する。
    for s, e in inline_code_spans(line):
        if s <= pos < e:
            return True
    return False

def is_code_span(line, pos, line_fenced):
    return line_fenced or in_inline_code(line, pos)

def url_spans(line):
    # `#N` が URL のパス・フラグメント(`.../issues/#N` のような形)の一部かどうかを判定するための
    # マッチ範囲一覧。`/` を QUALIFIED_PREV から外した副作用(URL 由来の `#N` を誤って裸判定して
    # しまう)を防ぐ専用の除外。check3 用の `URL_RE` ではなく、この用途専用の `URL_FRAGMENT_SPAN_RE`
    # を使う(上のコメント参照。要件が違う primitive を共有しない)。
    return [(m.start(), m.end()) for m in URL_FRAGMENT_SPAN_RE.finditer(line)]

def in_any_span(pos, spans):
    return any(s <= pos < e for s, e in spans)

# --- check1: ローカルエントリの裸 #N(repo 明示漏れ。コードスパン内の例示は対象外) ---
for e in local_entries:
    fenced = fenced_code_flags(e['lines'])
    for lineno, line in enumerate(e['lines'], start=1):
        naked = []
        urls = url_spans(line)
        for m in NUM_RE.finditer(line):
            if is_code_span(line, m.start(), fenced[lineno - 1]):
                continue
            if in_any_span(m.start(), urls):
                continue
            prev = line[m.start() - 1] if m.start() > 0 else ''
            if not (prev and QUALIFIED_PREV.match(prev)):
                naked.append('#' + m.group(1))
        if naked:
            # 配布 payload(このファイル自身)は他プロジェクトへも travel するため、例示に home repo 名を
            # 焼かない。consumer 自身の repo 名に置き換えられる汎用プレースホルダにする。
            add(e['path'], 'bare-issue-ref',
                f"行{lineno}: 裸の {', '.join(naked)} 参照(repo未明記)。例: <repo>#{naked[0][1:]} のように、あなたの repo 名を明記してください",
                e['date'])

# --- check2: travel面(グローバル知識ストア側 / scope:global)に issue番号が載っている(コードスパン内の例示は対象外) ---
for e in global_entries:
    fenced = fenced_code_flags(e['lines'])
    for lineno, line in enumerate(e['lines'], start=1):
        nums = [m.group(1) for m in NUM_RE.finditer(line)
                if not is_code_span(line, m.start(), fenced[lineno - 1])]
        if nums:
            add(e['path'], 'travel-issue-ref',
                f"行{lineno}: travel 面(グローバル知識ストア側)に issue 番号 {', '.join('#' + n for n in nums)} が残っています。番号自体を除去してください",
                e['date'])
for e in local_entries:
    if (e['fm'].get('scope', '').strip()) != 'global':
        continue
    fenced = fenced_code_flags(e['lines'])
    for lineno, line in enumerate(e['lines'], start=1):
        nums = [m.group(1) for m in NUM_RE.finditer(line)
                if not is_code_span(line, m.start(), fenced[lineno - 1])]
        if nums:
            add(e['path'], 'travel-issue-ref',
                f"行{lineno}: scope: global(昇格 staging = travel 面)に issue 番号 {', '.join('#' + n for n in nums)} が残っています。番号自体を除去してください",
                e['date'])

# --- check3: 破損したパス参照(path / path:line が実在しない) ---
# 判断ゼロの原則により、決定論で「実在すべきか」を判定できないクラスは対象から外す(黙って狭めず、
# 何を外したかをここに明記する):
#   - gitignore された/opt-in で不在たりうる領域(global/・*.local.*・sync 生成物の review/criteria.md 等)
#     → is_gitignored で判定できたら skip(check4/5/8 の global/ 不在時 skip と同じ扱い)。
#   - `...` 省略記法(コーパスに複数実例がある確立した書き方。何を省略したか本文からは決定できない)
#     → has_elision_segment で判定できたら skip。
#   - `path:line` 形式は「## 根拠 / 実例」節の外(例: `## 判断 / ルール`・`## なぜ` の地の文)では
#     検査しない。エントリ雛形上、正式な引用(内部/外部の実例)は根拠節に置く規約であり、それ以外の
#     節での `path:line` 的な文字列は「解決規則を例示する説明」等の自己言及的な記述でありうる
#     (実例: grounding-check-resolves-paths-repo-root-relative が判断/ルール節で架空の `foo.sh` を
#     例示している)。これは決定論では実在主張と区別できないため、検査対象を根拠節に絞る
#     (新しい規則の発明ではなくエントリ雛形の節構成をそのまま使う)。bare backtick path(行番号無し)は
#     根拠節に限定せず全文を対象にする(行番号を伴わない実例は `## なぜ` 節にも現れるため)。
def check_paths(e):
    evidence = evidence_section_flags(e['lines'])
    for lineno, line in enumerate(e['lines'], start=1):
        cleaned = HOSTPORT_RE.sub('', URL_RE.sub('', line))
        if evidence[lineno - 1]:
            for ref in sorted(set(PATHLINE_RE.findall(cleaned))):
                path, lineno_ref = ref.rsplit(':', 1)
                if LEGACY_PAYLOAD_RE.fullmatch(path):
                    # 導入先の旧パス(`.claude/(skills|agents|lib|hooks)/…`・rules配下の旧harness/…)は
                    # check_legacy_payload_paths() が単独で報告する(実在確認込みで一本化。
                    # ここで broken-path-ref も出すと二重報告になる — 一次レビュー指摘)。
                    continue
                if has_elision_segment(path):
                    add(e['path'], 'broken-path-ref-skipped',
                        f"行{lineno}: `{ref}` は省略記法(...)のため解決を試みずスキップした", e['date'])
                    continue
                target = resolve_existing(path)
                if target is None:
                    if any_candidate_gitignored(path):
                        add(e['path'], 'broken-path-ref-skipped',
                            f"行{lineno}: `{ref}` は gitignore された/opt-in の領域のため実在を判定できずスキップした",
                            e['date'])
                    else:
                        add(e['path'], 'broken-path-ref',
                            f"行{lineno}: `{ref}` — ファイルが存在しない", e['date'])
                    continue
                try:
                    total = sum(1 for _ in open(target, encoding='utf-8', errors='replace'))
                except Exception:
                    total = 0
                try:
                    if int(lineno_ref) > total:
                        add(e['path'], 'broken-path-ref',
                            f"行{lineno}: `{ref}` — 実体は {total} 行までしかない", e['date'])
                except ValueError:
                    pass
        for tok in BACKTICK_RE.findall(line):
            if lp_is_logical(tok):
                # 論理パス(`yosage-dev-harness:<相対パス>`)は使用中の版のプラグインの中で解決する
                # (ドット2つを含む・実在しない → broken-path-ref。gitignore 判定の対象外
                # (プラグイン payload は導入先の gitignore と無関係))。
                if lp_resolve(tok) is None:
                    add(e['path'], 'broken-path-ref',
                        f"行{lineno}: `{tok}` — 実在しない論理パス", e['date'])
                continue
            if LEGACY_PAYLOAD_RE.fullmatch(tok):
                # 導入先の旧パスは check_legacy_payload_paths() が単独で報告する(上と同じ理由)。
                continue
            if ':' in tok or not BARE_PATH_RE.match(tok):
                continue
            if has_elision_segment(tok):
                add(e['path'], 'broken-path-ref-skipped',
                    f"行{lineno}: `{tok}` は省略記法(...)のため解決を試みずスキップした", e['date'])
                continue
            if resolve_existing(tok) is None:
                if any_candidate_gitignored(tok):
                    add(e['path'], 'broken-path-ref-skipped',
                        f"行{lineno}: `{tok}` は gitignore された/opt-in の領域のため実在を判定できずスキップした",
                        e['date'])
                else:
                    add(e['path'], 'broken-path-ref',
                        f"行{lineno}: `{tok}` — ファイルが存在しない", e['date'])

def _prime_gitignore_cache():
    # check_paths() が解決できない参照ごとに any_candidate_gitignored() → is_gitignored() を呼ぶと、
    # 参照1件につき候補ルートの数だけ外部プロセス(git check-ignore)を起動する(実測: 9〜18回/件)。
    # 支配的コストはプロセス起動そのものではなく、プロセス終了を待つポーリングの待機時間だったため、
    # 監査全体でユニークな候補パスを先に集め、batch_check_ignored() で**1回**にまとめて判定し、
    # 結果を _gitignore_cache に事前投入する。以降 check_paths() 内の is_gitignored() は
    # すべてキャッシュ命中になり、追加の外部プロセス起動は発生しない。
    #
    # ここは check_paths() の「解決に失敗する条件」を最小限に再現した事前スキャンであり、
    # check_paths() 本体とは独立したコード(意図的な重複)。ただし drift しても安全側:
    # この事前スキャンが check_paths() の実際の抽出条件と食い違って対象を取りこぼしても、
    # is_gitignored() はキャッシュ未ヒット時に単発の `git check-ignore -q` へフォールバックする
    # ため、判定結果(正しさ)は変わらない。劣化するのは速度だけ(取りこぼした分だけ元の
    # 呼び出し回数に戻る)。
    #
    # ↑これは「事前スキャンでの抽出漏れ(取りこぼし)」に対する安全性であり、**一括呼び出し
    # (batch_check_ignored)自体が失敗するケースとは別物**(一次レビューで指摘・区別を明記)。
    # 前者は候補を集める側の網羅性の話、後者は集めた候補をまとめて問い合わせる呼び出しそのものの
    # 成否の話であり、対処も別: 後者は batch_check_ignored() が失敗を None で返し、下でキャッシュへ
    # 書き込まないことで同じフォールバック経路(is_gitignored のキャッシュ未ヒット)へ合流させる。
    unresolved_paths = set()
    for e in local_entries:
        evidence = evidence_section_flags(e['lines'])
        for lineno, line in enumerate(e['lines'], start=1):
            cleaned = HOSTPORT_RE.sub('', URL_RE.sub('', line))
            if evidence[lineno - 1]:
                for ref in sorted(set(PATHLINE_RE.findall(cleaned))):
                    path, _lineno_ref = ref.rsplit(':', 1)
                    if LEGACY_PAYLOAD_RE.fullmatch(path):
                        continue
                    if has_elision_segment(path):
                        continue
                    if resolve_existing(path) is None:
                        unresolved_paths.add(path)
            for tok in BACKTICK_RE.findall(line):
                if LEGACY_PAYLOAD_RE.fullmatch(tok):
                    continue
                if ':' in tok or not BARE_PATH_RE.match(tok):
                    continue
                if has_elision_segment(tok):
                    continue
                if resolve_existing(tok) is None:
                    unresolved_paths.add(tok)
    if not unresolved_paths:
        return
    all_candidates = []
    seen = set()
    for path in unresolved_paths:
        for c in ignore_check_candidates(path):
            if c not in seen:
                seen.add(c)
                all_candidates.append(c)
    if not all_candidates:
        return
    # cwd(git 作業木)ごとにグループ化してから1回ずつバッチ呼び出しする(plugin_root は repo_root と
    # 別の git 作業木にありうるため、混ぜて1回で呼ぶと木の外のパスで fatal error になる。
    # `_git_cwd_for` と同じ分岐をここでも使う)。グループ数は高々2(repo_root 系・plugin_root 系)
    # なので、依然としてバッチ化の目的(未解決参照の件数に比例して呼び出しが増えない)は保たれる。
    by_cwd = {}
    for c in all_candidates:
        by_cwd.setdefault(_git_cwd_for(c), []).append(c)
    for cwd, group in by_cwd.items():
        ignored = batch_check_ignored(group, cwd)
        if ignored is None:
            # このグループの一括呼び出しが失敗した(一次レビューで指摘)。ここでキャッシュへ何も
            # 書き込まなければ、後続の is_gitignored() はこのグループの候補がキャッシュ未ヒットの
            # ままとなり、1件ずつの個別呼び出し(`git check-ignore -q`)へ正しくフォールバックする
            # (このグループに限り修正前の速度まで戻る。正しさ(偽陽性を出さないこと)を優先し、
            # 性能の劣化を受け入れる)。他グループのキャッシュ書き込みには影響しない。
            continue
        for c in group:
            _gitignore_cache[c] = (c in ignored)

_prime_gitignore_cache()

for e in local_entries:
    check_paths(e)

# --- check-legacy-payload-path: 導入先のパス(プラグイン形では存在しない旧表記)が残っている ---
# broken-path-ref とは別の check-code にする(変換スクリプトの対象を機械的に数えられるように)。
# check3 とは独立に全 local エントリ(scope 不問)を対象にする(導入先パスは scope に関わらず
# 論理パスへ書き換えるべき対象のため)。
def check_legacy_payload_paths(e):
    for lineno, line in enumerate(e['lines'], start=1):
        for m in sorted(set(LEGACY_PAYLOAD_RE.findall(line))):
            target = legacy_payload_target(m)
            if target is not None and os.path.isfile(target):
                # 変換先(プラグイン payload の実体)が実在する: 変換スクリプトで書き換えられる。
                add(e['path'], 'legacy-payload-path',
                    f"行{lineno}: `{m}` は導入先のパス(プラグイン形では存在しない)。論理パス"
                    "(yosage-dev-harness:<相対パス>)に書き換えてください"
                    "(変換スクリプト: yosage-dev-harness-knowledge-convert-paths)", e['date'])
            else:
                # 変換先が実在しない(=撤去・改名済みのファイルを指している)。変換スクリプトは
                # この種の参照を書き換えず「要手直し」に回すため、案内を変える。check_paths() 側は
                # このトークンを skip しているため(上記)、ここが唯一の報告元になる(1件にまとめる)。
                add(e['path'], 'legacy-payload-path',
                    f"行{lineno}: `{m}` は導入先のパス(プラグイン形では存在しない)。かつ変換先の"
                    "ファイルが撤去・改名されているため、変換スクリプトでは書き換えられません。"
                    "手で直してください。", e['date'])

for e in local_entries:
    check_legacy_payload_paths(e)

# --- check4: dangling [[...]] ---
for e in local_entries:
    for lineno, line in enumerate(e['lines'], start=1):
        for tok in LINK_RE.findall(line):
            tok = tok.strip()
            if not tok:
                continue
            r = resolve_link(tok)
            if r == 'dangling':
                add(e['path'], 'dangling-link',
                    f"行{lineno}: [[{tok}]] の解決先が見つからない", e['date'])
            elif r == 'skipped':
                add(e['path'], 'dangling-link-skipped',
                    f"行{lineno}: [[{tok}]] はローカル/skill/agent/ruleに無いが、"
                    "グローバルミラー(global/)が未 sync のためストア側参照の可能性を排除できず判定をスキップした",
                    e['date'])

# --- check5: supersedes: の指す先が実在しない ---
for e in local_entries:
    target = (e['fm'].get('supersedes') or '').strip()
    if not target:
        continue
    r = resolve_knowledge_id(target)
    if r == 'dangling':
        add(e['path'], 'bad-supersedes',
            f"supersedes: {target} の解決先が見つからない", e['date'])
    elif r == 'skipped':
        add(e['path'], 'bad-supersedes-skipped',
            f"supersedes: {target} はローカルに無いが、グローバルミラー(global/)が未 sync のため"
            "ストア側参照の可能性を排除できず判定をスキップした",
            e['date'])

# --- check6: status: superseded なのに誰の supersedes からも指されていない(back-link 書き忘れ) ---
superseded_by = set()
for e in local_entries + global_entries:
    t = (e['fm'].get('supersedes') or '').strip()
    if t:
        superseded_by.add(t)
for e in local_entries:
    if (e['fm'].get('status', '').strip()) == 'superseded' and e['id'] not in superseded_by:
        add(e['path'], 'missing-backlink',
            f"status: superseded だが、id `{e['id']}` を supersedes: で指すエントリが見つからない"
            "(書き忘れ。意図的な退役で後継が無いなら status: archived を検討)",
            e['date'])

# --- check7: frontmatter 不備(必須フィールド欠落・domain とディレクトリ名の不一致) ---
# id は対象に含めない: id 省略はファイル名からの導出が正式仕様(救済ではない)であり欠陥ではない。
REQUIRED_FIELDS = ['date', 'domain', 'tags', 'scope', 'status', 'summary']
for e in local_entries:
    missing = [k for k in REQUIRED_FIELDS if not (e['fm'].get(k) or '').strip()]
    if missing:
        add(e['path'], 'frontmatter-missing-field',
            f"必須フィールドが空/欠落: {', '.join(missing)}", e['date'])
    dom = (e['fm'].get('domain') or '').strip()
    if dom and dom != e['domain']:
        add(e['path'], 'domain-mismatch',
            f"frontmatter の domain: {dom} が配置ディレクトリ({e['domain']})と不一致", e['date'])

# --- check8: scope:global のエントリが scope:local のエントリを参照している(昇格=move で解決不能になる) ---
local_scope = {e['id']: (e['fm'].get('scope', '').strip() or 'local') for e in local_entries}
for e in local_entries:
    if (e['fm'].get('scope', '').strip()) != 'global':
        continue
    targets = set()
    t = (e['fm'].get('supersedes') or '').strip()
    if t:
        targets.add(t)
    for line in e['lines']:
        for tok in LINK_RE.findall(line):
            targets.add(tok.strip())
    for tgt in targets:
        if tgt in local_scope and local_scope[tgt] != 'global':
            add(e['path'], 'global-refs-local',
                f"scope: global のエントリが scope: local のエントリ `{tgt}` を参照している"
                "(昇格=move で参照先がローカルから消え解決不能になる)",
                e['date'])

# --- check9: scope: global のエントリのパス参照が「導入先で解決できない位置」を指している ---
# 対象は scope: global の local エントリのみ(討議収束: 配布 payload 全体を走査対象にするのは
# 偽陽性リスクが高いため見送り。scope: global は昇格 staging = travel 面に出る候補であり、
# ここで検査する意味が最も強い)。check3(実在判定)とは別の軸を見る: check3 が「実在するか」を
# 判定するのに対し、check9 は「実在はするが、配布される位置(harness/ payload、または導入先の
# 実体である .claude/ 配下)には無い(=このリポジトリのソースにしか無い)」を判定する。
# 実在自体の判定は resolve_existing にそのまま委ね、check3 が「実在しない」と判定したもの
# (target が None)は check9 の対象にしない(broken-path-ref と travel-unsafe-path-ref の
# 二重報告を避ける。存在しないものは travel-safe かどうか以前の問題であり check3 側の責務)。
def is_travel_safe_path(target_path):
    ap = os.path.abspath(target_path)
    for root in (plugin_root, base):
        if not (ap == root or ap.startswith(root + os.sep)):
            continue
        # `knowledge/` 配下は特殊: project-local エントリ本体(`knowledge/<domain>/**`)・
        # グローバルミラー(`knowledge/global/**`)は「consumer 所有・payload に同名を載せない」
        # 領域であり、実際に配布されるのは `knowledge/` 直下のテンプレート
        # (`_entry-template.md` 等)だけ。`knowledge/<domain>/*.md`(project-local エントリ本体)
        # や `knowledge/global/**`(グローバルストアの pull ミラー)はどちらも導入先ごとに
        # 異なる内容を持つ非配布領域であり、単純に「.claude/ または harness/ 配下」という
        # 判定だけでは travel-safe と誤判定してしまう(一次レビューで指摘: このリポジトリ自身の
        # `.claude/knowledge/<domain>/*.md` を裸パスで参照する scope:global エントリが実際に
        # 見逃されていた)。`knowledge/` の直下(1階層)だけを travel-safe とし、
        # それより深い(サブディレクトリを持つ)参照は除外する。
        kroot = os.path.join(root, 'knowledge')
        if ap == kroot or ap.startswith(kroot + os.sep):
            rel = os.path.relpath(ap, kroot)
            if os.sep in rel:
                continue
        return True
    return False

def any_existing_travel_safe(ref_path):
    # 判定は「最初に見つかった候補」(resolve_existing の戻り値)ではなく、**候補全体のうち
    # travel-safe なものが1つでもあるか**で行う。candidate_targets() の探索順は repo_root が
    # 先頭に来るため、resolve_existing の戻り値だけで判定すると、リポジトリ直下と harness/ の
    # 両方に同名ファイルが存在する曖昧な参照(例: 素の `.gitignore` — リポジトリ自身の
    # トップレベル .gitignore と、配布物 `harness/.gitignore` の両方が実在する)で、
    # travel-safe な候補(harness/.gitignore)も実在するのに repo_root 側が先に見つかって
    # 誤検知しうる。全候補を見ることでこの曖昧さを避ける。
    return any(os.path.isfile(t) and is_travel_safe_path(t) for t in candidate_targets(ref_path))

# check3 の `BARE_PATH_RE` は拡張子 allowlist への完全一致を要求する(「パスと同型の非パス識別子」
# を誤検知しないための設計)。この要求は check3 では必須(実在しない参照を「壊れている」と積極的に
# 主張するため、非パス識別子の誤検知を避ける必要が強い)だが、check9 は逆に**実在確認
# (resolve_existing)を先に通した候補にしか発火しない**ため、非パス識別子が偶然実在ファイルと
# 一致することは実質的に起こらない。この非対称を利用して、check9 の bare backtick 候補は拡張子
# 制約を外した緩いパターンを使う——拡張子を持たない配布対象外の実行ファイル(CLI 本体等)は、
# 拡張子必須の `BARE_PATH_RE` では最初から候補としてすら拾えず、check9 の目的
# (配布対象外パスへの参照を検知する)を果たせなくなるため。
BARE_PATH_ANY_RE = re.compile(r'^[A-Za-z0-9_.\-()]+(?:/[A-Za-z0-9_.\-()]+)+$')

def is_vcs_internal_path(ref_path):
    # `.git/` 配下は git 自身が作る汎用メタデータであり、全ての git リポジトリに同一の形で
    # 存在する(travel-safety の判定軸=「このリポジトリの配布物かどうか」の外にある)。実測
    # (観測構成)の説明で汎用の git 挙動を指すためだけに `.git/info/exclude` のようなパスを
    # 書く実例があり、たまたまこのリポジトリの `.git/` 配下に同名の実ファイルが存在するために
    # travel-unsafe と誤検知していた(BARE_PATH_ANY_RE が拡張子を問わず拾うようになった副作用)。
    return ref_path.split('/', 1)[0] == '.git'

def check_travel_safety(e):
    evidence = evidence_section_flags(e['lines'])
    for lineno, line in enumerate(e['lines'], start=1):
        cleaned = HOSTPORT_RE.sub('', URL_RE.sub('', line))
        if evidence[lineno - 1]:
            for ref in sorted(set(PATHLINE_RE.findall(cleaned))):
                path, _lineno_ref = ref.rsplit(':', 1)
                if has_elision_segment(path) or is_vcs_internal_path(path):
                    continue
                if resolve_existing(path) is None:
                    continue
                if not any_existing_travel_safe(path):
                    add(e['path'], 'travel-unsafe-path-ref',
                        f"行{lineno}: `{ref}` は実在するが、配布される位置(harness/ または導入先の "
                        ".claude/ 配下)には無い(このリポジトリのソースにしか無く、導入先では解決できない)",
                        e['date'])
        for tok in BACKTICK_RE.findall(line):
            if lp_is_logical(tok):
                # 論理パスは持ち運べる参照として扱う(解決できれば travel-safe。解決できないものは
                # check3 の broken-path-ref に任せ、二重に報告しない)。
                continue
            if ':' in tok or not BARE_PATH_ANY_RE.match(tok):
                continue
            if has_elision_segment(tok) or is_vcs_internal_path(tok):
                continue
            if resolve_existing(tok) is None:
                continue
            if not any_existing_travel_safe(tok):
                add(e['path'], 'travel-unsafe-path-ref',
                    f"行{lineno}: `{tok}` は実在するが、配布される位置(harness/ または導入先の "
                    ".claude/ 配下)には無い(このリポジトリのソースにしか無く、導入先では解決できない)",
                    e['date'])

for e in local_entries:
    if (e['fm'].get('scope', '').strip()) != 'global':
        continue
    check_travel_safety(e)

for rel, code, msg in findings:
    print(f"{rel}\t{code}\t{msg}")

# 標準エラー出力へ走査件数のサマリを必ず出す(標準出力の TSV 契約は変えない。ヘッダコメント参照)。
# 「0 件走査」と「N 件走査して報告0件」を件数の違いで判別できるようにする(前者は引数ミス/
# 新規導入先のどちらかでありうる。後者は監査が実際に走った上でのクリーン)。
print(f"knowledge-audit: project-local エントリを {len(local_entries)} 件走査し、"
      f"構造的欠陥/通知を {len(findings)} 件報告しました", file=sys.stderr)
PY
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then knowledge_audit "$@"; fi
