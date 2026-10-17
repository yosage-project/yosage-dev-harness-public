# test/lib/common.sh — 自己テスト共通の道具(カウンタ・アサーション関数・JSON組立・fixture用ヘルパー)。
# test/run.sh から source される。ROOT はこのファイルより先に呼び出し元(test/run.sh)が定義する。
H="$ROOT/harness"
# 識別子指紋スキャン(下記 IDFP)を自己一致させずにテストデータへ '#' を組み込むための組み立て用変数。
# ソース上に「記号直後に数字」の形を残さないためだけの用途で、値そのものに意味は無い。
HSH='#'
pass=0; fail=0
# 上記判定の本体(開始時/終了時スナップショットの集合差分)。末尾の実判定とテスト容易性のため
# 純粋関数として切り出す(temp は $ROOT の外=mktemp。追加依存なしの comm -13 で差分を取る)。
_dirt_diff() {
  local before="$1" after="$2" d
  # mktemp 失敗を無視すると sort/comm がエラーだけ吐いて空文字列を返し、末尾の
  # 後始末漏れ検知が「新規汚染なし」へ沈黙的に倒れる(fail-open)。安全機構なので
  # 失敗は空ではなく非空のエラー標識を返して呼び出し側の判定を赤くする(fail-loud)。
  d="$(mktemp -d)" || { echo "_dirt_diff: mktemp failed"; return 1; }
  printf '%s\n' "$before" | sort > "$d/before"
  printf '%s\n' "$after"  | sort > "$d/after"
  comm -13 "$d/before" "$d/after"
  rm -rf "$d"
}
ok() { pass=$((pass+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
# 失敗詳細の保全: ng の呼び出しごとに、失敗したアサーション名(期待/実際値を含む文字列。
# 呼び出し元が既に組み立てて渡している)を _failures[] へ積んでおく。理由: 出力を末尾だけ確認
# する運用や、非決定的な赤を再実行して通した場合、どのアサーションが落ちたのかが記録に残らない
# という観測があった(実行結果を末尾で確認する運用のまま、詳細は末尾に再掲する形で解決する)。
_failures=()
# 失敗ログの保存先: $ROOT のパスから導出した固定名を repo の外(TMPDIR)へ置く。
# - repo の外なので、追加しても後始末漏れ検知(git status --porcelain)には一切現れない。
# - ファイル名は「記号を除去した可読部(デバッグ時に見て分かるため残す)」+「$ROOT 全体の
#   cksum チェックサム」で構成する。可読部だけだと記号の位置が異なる別の worktree パスが
#   同じ名前に丸められうる(例: "a/b_c" と "a_b/c" は記号除去だけだと同名になる)ため、
#   チェックサムを付けて実質的に別ファイルへ分離する(32bit チェックサムなので理論上の
#   衝突確率はゼロではないが、worktree の実運用規模では無視できる水準)。
# - 追記(>>)モードで蓄積するため、再実行して通った後も直前の失敗の記録が残る。
_FAILLOG="${TMPDIR:-/tmp}/yosage-dev-harness-test-failures-$(printf '%s' "$ROOT" | tr -c 'A-Za-z0-9' '_')-$(printf '%s' "$ROOT" | cksum | awk '{print $1}').log"
ng() { fail=$((fail+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; _failures+=("$1"); }
# 失敗一覧を人間可読なレポート文字列に整形する(純粋関数)。ng() の副作用(fail カウンタの加算)
# から分離しておくことで、この関数自体を直接呼んでテストしても本スイートの pass/fail 集計に
# 影響しない(_dirt_diff と同じ設計判断: 上の後始末漏れ検知参照)。
_format_failure_report() {
  local n="$1"; shift
  echo "== failures (${n}) =="
  local f
  for f in "$@"; do
    printf '  \033[31m✗\033[0m %s\n' "$f"
  done
}
exit_is()  { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (expected exit $2, got $3)"; fi; }
out_has()  { case "$3" in *"$2"*) ok "$1";; *) ng "$1 (missing: $2)";; esac; }
out_hasnt(){ case "$3" in *"$2"*) ng "$1 (unexpected: $2)";; *) ok "$1";; esac; }
file_is()  { if [ -e "$2" ]; then ok "$1"; else ng "$1 (missing path: $2)"; fi; }
file_isnt(){ if [ -e "$2" ]; then ng "$1 (unexpected path: $2)"; else ok "$1"; fi; }
out_is_empty() { if [ -z "$2" ]; then ok "$1"; else ng "$1 (unexpected output: $2)"; fi; }

json_cmd()  { python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1"; }
json_cmd_cwd() { python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
json_file() { python3 -c 'import json,sys;print(json.dumps({"tool_input":{"file_path":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
json_notify() {  # <hook_event_name> <session_id> <cwd> [notification_type]
  python3 -c 'import json,sys
d={"hook_event_name":sys.argv[1],"session_id":sys.argv[2],"cwd":sys.argv[3]}
if len(sys.argv) > 4 and sys.argv[4]:
    d["notification_type"]=sys.argv[4]
print(json.dumps(d))' "$1" "$2" "$3" "${4:-}"
}
gitc() { git -c user.email=t@example.com -c user.name=test "$@"; }
# knowledge-audit.sh の TSV 出力(<relpath>\t<check-code>\t<message>)から、指定した
# relpath/check-code の組がちょうど存在するかを厳密一致で判定する(部分一致だと
# 例えば "dangling-link" が "dangling-link-skipped" の部分文字列になり誤判定するため)。
ka_has() { printf '%s\n' "$3" | awk -F'\t' -v f="$1" -v c="$2" '$1==f && $2==c {found=1} END{exit !found}'; }

# harness/README.md 等の git 追跡ファイルを一時的に書き換えて検証したい節は、実 repo(トラック済み)を
# 直接書き換えず、payload 一式(harness/ scripts/ README.md .claude-plugin/)を一時ディレクトリへ
# コピーしてそちら側で書き換える(コピー元の追跡ファイルには一切触れない)。scripts/catalog.sh は
# 自分自身の BASH_SOURCE から ROOT_DIR を解決するため、コピー先の scripts/catalog.sh を起動すれば
# コピー先の payload を読む。
# 使い方: SRC="$(_src_copy)" ; ... "$SRC/scripts/catalog.sh" ... ; rm -rf "$SRC"
_src_copy() {
  local d
  d="$(mktemp -d)"
  cp -R "$ROOT/harness" "$d/harness"
  cp -R "$ROOT/scripts" "$d/scripts"
  cp -R "$ROOT/.claude-plugin" "$d/.claude-plugin"
  cp "$ROOT/README.md" "$d/README.md"
  printf '%s' "$d"
}

# 監査スクリプト自身(knowledge-audit.sh)は、自分自身の位置(BASH_SOURCE)から「プラグインの
# ルート」を自己解決する(ルール `knowledge` の設計どおり、consumer には
# 配布物の状態を管理する専用ファイルは無い)。fixture 自身の harness/ を「プラグインのルート」として
# 使わせたい検査(check3 のプレフィックス補完・check4 の skill/agent/rule 名前解決等)は、実体
# ($H/lib/knowledge-audit.sh)をそのまま呼ばず、fixture の harness/lib/ 配下へコピーしたものを
# 呼ぶ(コピー先の BASH_SOURCE から見た「プラグインのルート」が fixture 自身の harness/ になる)。
# 使い方: mk_ka_copy <fixture-dir> の後 bash "<fixture-dir>/harness/lib/knowledge-audit.sh" ... を呼ぶ。
mk_ka_copy() {  # <fixture-dir>
  mkdir -p "$1/harness/lib"
  cp "$H/lib/knowledge-audit.sh" "$1/harness/lib/knowledge-audit.sh"
}

# test/run.sh・test/lib/*.sh・test/suites/*.sh を連結した一時ファイルを作る(自己参照検査用)。
# 分割前は単一ファイル(test/run.sh)だった走査対象を、分割後も1件の走査として扱うため
# (HSH ディスガイズ検査等、テストソース自身を読んで検証する節が使う)。
# 呼び出し側が返り値のパスを rm すること(親ディレクトリごと消す)。
_all_test_src() {
  local d
  # _dirt_diff と同じ fail-loud: mktemp 失敗を無視すると、以降の cat/リダイレクトが
  # 空文字列パス相手に失敗するだけで、呼び出し側は不正なパスを黙って受け取りうる。
  d="$(mktemp -d)" || { echo "_all_test_src: mktemp failed"; return 1; }
  { cat "$ROOT/test/run.sh"; cat "$ROOT/test/lib"/*.sh; cat "$ROOT/test/suites"/[0-9][0-9]-*.sh; } > "$d/all-test-src.sh"
  printf '%s' "$d/all-test-src.sh"
}

# 導入先(プラグインを有効にしたリポジトリに相当する最小の状態)を作る。CLI は無い
# (ハーネスの検査は harness/hooks/<x>.sh・harness/lib/<x>.sh を直接呼ぶ形に一本化済み。
# ルール `knowledge` 等の内容検査も $H(=$ROOT/harness)を直接読む)。
# 使い方: mk_consumer [--git] [--workspace] <dir>
#   --git      : git init -q する(git を前提にした箇所だけに付ける)
#   --workspace: .claude/yosage-dev-harness.local.json に {"workspace": true} を書く
#
# プラグイン形では、sync が生成する pull 物(review/criteria.md・knowledge/global/ 等)を
# git 管理外にする行は導入先自身の .gitignore が持つ(setup の Sub-issue が書く。配布 payload の
# review/.gitignore・knowledge/.gitignore は撤去済み)。この関数はそれらの行を書かない
# (書く必要がある個別の検査は、その検査自身が対象の .gitignore をその場で書く)。
mk_consumer() {
  local git="" ws=""
  while [ "$#" -gt 1 ]; do
    case "$1" in
      --git) git=1; shift ;;
      --workspace) ws=1; shift ;;
      *) break ;;
    esac
  done
  mkdir -p "$1/.claude/knowledge" "$1/.claude/review" || return 1
  [ -n "$git" ] && { git -C "$1" init -q || return 1; }
  [ -n "$ws" ] && printf '{"workspace": true}\n' > "$1/.claude/yosage-dev-harness.local.json"
  return 0
}


# テスト用の bare remote と、それを clone した作業用リポジトリの組を作る。
# 素の git init の既定ブランチは環境で変わるので、ブランチは必ず明示して作る
# (リモートの既定ブランチ・追加のブランチとも)。番号の小さい suite からも後ろの suite からも
# 使えるよう、suite ではなくここ(共通の道具)に置く。
# 使い方: mk_bare_remote_clone <dir> [--default <branch>] [--branch <name>]... [--no-origin-head]
#   <dir>               … 既存の空ディレクトリ(例 "$(mktemp -d)")。呼び出し側が後で rm -rf する。
#                         <dir>/remote.git (bare remote) と <dir>/work (clone) ができる。
#   --default <branch>  … リモートの既定ブランチ(既定 main)。work は clone 直後にこれをチェックアウトし、
#                         origin/HEAD がこれを指す。初期コミットが1つ入る。
#   --branch <name>     … 追加のブランチ(何度でも指定可。既定ブランチと同じコミットを指す)。
#                         work には origin/<name> として見える(ローカルブランチは作らない)。
#   --no-origin-head    … clone のあとで origin/HEAD を消し(git remote set-head origin -d)、
#                         git config remote.origin.followRemoteHEAD never を入れて、fetch で戻らないようにする。
# コミットの作者は gitc と同じ。work の user 設定は入れない(コミットが要る側は gitc -C か gitc を使う)。
mk_bare_remote_clone() {
  local dir="${1:?dir is required}" default="main" nohead="" extra=() seed b
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --default) default="${2:?--default needs a branch}"; shift 2 ;;
      --branch) extra+=("${2:?--branch needs a name}"); shift 2 ;;
      --no-origin-head) nohead=1; shift ;;
      *) echo "mk_bare_remote_clone: unknown option: $1" >&2; return 2 ;;
    esac
  done
  git init -q --bare -b "$default" "$dir/remote.git" || return 1
  # 初期コミットは使い捨ての seed リポジトリから push する(clone した work に余計な履歴を持ち込まない)。
  seed="$(mktemp -d "$dir/seed.XXXXXXXX")" || return 1
  git init -q -b "$default" "$seed" || return 1
  gitc -C "$seed" commit -q --allow-empty -m init || return 1
  git -C "$seed" remote add origin "$dir/remote.git" || return 1
  git -C "$seed" push -q origin "$default" || return 1
  for b in ${extra[@]+"${extra[@]}"}; do
    git -C "$seed" push -q origin "$default:refs/heads/$b" || return 1
  done
  rm -rf "$seed"
  git clone -q "$dir/remote.git" "$dir/work" 2>/dev/null || return 1
  if [ -n "$nohead" ]; then
    git -C "$dir/work" remote set-head origin -d >/dev/null 2>&1 || return 1
    git -C "$dir/work" config remote.origin.followRemoteHEAD never || return 1
  fi
  return 0
}
