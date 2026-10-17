#!/usr/bin/env bash
# test/run.sh — yosage-dev-harness 自己テスト。
#   外部依存なし(純シェル + JSON 組立に python3)。回帰を防ぐための最小スイート。
#   使い方: bash test/run.sh   (任意の cwd から)。失敗があれば exit 1。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/test/lib/common.sh"
# 後始末漏れ検知: 開始時の git status --porcelain スナップショットを記録する。末尾で
# 「(終了時 - 開始時) が空」を判定することで、作業者が worktree に最初から置いていた未追跡
# ファイル(未追跡の knowledge エントリ・.epic_docs/・下書き等)を除外しつつ、スイートが新たに
# 汚した分(追跡ファイルの改変・未追跡残骸の新規発生。命名は問わない)だけを捕捉する。
#
# 境界(意図的): この判定は $ROOT の中だけを見る。$ROOT が複数リポジトリ同居のワークスペースへ
# 入れ子で置かれる構成でも、親ワークスペース側の残骸(cwd を取り違えた相対パスが逃げた先)までは
# 原理的に見えない。広げない(親が git 管理下でない構成では成立しない・dev-only の本スイートに
# ワークスペース依存の仮定を持ち込みたくない)。対策は検知の拡張ではなく発生源側:
# アドホックな(このスイート外での)使い捨て fixture は、パステンプレート付き mktemp -d
# (例: mktemp -d "$ROOT/test/scratch.XXXXXXXX")で、割り当て済み作業ツリー配下の gitignore
# されない場所に作る(cwd 非依存の絶対パスなので親ワークスペースへ漏れる余地が無く、片付け忘れは
# この後始末漏れ検知に拾われる)。素の mktemp -d(パステンプレート無し・OS の一時領域を返す)は
# 使わない: そこに置いたスクリプトを実行すると guard.sh の no-litter ブロックに無条件で止められる。
# 一般的な技法の根拠は .claude/knowledge/harness-dev/ の
# ad-hoc-fixture-absolute-path-must-anchor-to-assigned-tree-not-system-tmp、この境界判断自体は同
# ディレクトリの leftover-detection-boundary-stays-repo-internal-not-extended-to-parent-workspace。
# (この下のスイート自身の fixture 群が使う素の mktemp -d は別物: Bash ツール越しに渡る「アドホックな
# コマンド文字列」ではなくスクリプト内部のサブプロセスなので guard の no-litter 静的マッチの対象外)
_initial_status="$(cd "$ROOT" && git status --porcelain 2>/dev/null)"

# test/suites/NN-<area>.sh を番号順に自動で見つける(手書きの一覧を持たない。一覧を手で書くと、
# suite を足す・消す作業のすべてがその一覧を書き換える共有の衝突点になるため)。
# 番号は分割前の出現順(最初の行番号の順)。全体実行はこの順を保つ(ある領域が別の領域の変数に
# 頼っていた場合に結果が変わりうるため)。後から足す suite は空いている番号を取る。
_suites=()
for _f in "$ROOT"/test/suites/[0-9][0-9]-*.sh; do [ -f "$_f" ] && _suites+=("$_f"); done
if [ "$#" -gt 0 ]; then
  _sel=()
  for _a in "$@"; do
    _m=("$ROOT"/test/suites/[0-9][0-9]-"$_a".sh)
    [ -f "${_m[0]}" ] || { echo "unknown suite: $_a" >&2; exit 2; }
    _sel+=("${_m[0]}")
  done
  _suites=("${_sel[@]}")
fi
for _f in "${_suites[@]}"; do
  # shellcheck disable=SC1090
  . "$_f"
done
echo "== 追跡ファイルの後始末漏れ検知: スイート実行中に git 追跡ファイルが新たに汚れていない =="
# test/run.sh は payload(bin/ harness/ README.md 等)を一時ディレクトリへコピーして検証するため、
# git 追跡ファイルを直接書き換えない設計になっている。後始末漏れ(コピー隔離を経ずに実ファイルを
# 書き換えた・一時バックアップの残留)が無いことを、スイート末尾で機械的に検知する。
#
# 判定は「開始時スナップショットとの差分」(冒頭の _initial_status を参照): 作業者が worktree に
# 最初から置いていた未追跡ファイルは開始時にも現れるため差分に出ず除外される。スイートが新たに
# 汚した分(追跡ファイルの改変・未追跡残骸の新規発生。命名は問わない)は開始時に無く終了時に在る
# ため差分に出て捕捉される。名前ベースの残骸救済(.bak 等の特別扱い)は検証不能な免除になるため
# 入れない。
_final_status="$(cd "$ROOT" && git status --porcelain 2>/dev/null)"
_new_dirt="$(_dirt_diff "$_initial_status" "$_final_status")"
out_is_empty "後始末漏れ検知: (終了時 - 開始時)の git status --porcelain が空(スイートによる新規汚染なし)" "$_new_dirt"

# 失敗詳細の保全: fail > 0 のときだけ、summary の直前に失敗一覧を再掲する。summary は
# 常にスイート出力の最終行付近にあるため、出力を末尾数十行だけ確認する運用でもこの一覧に届く。
# この画面再掲は、下の $_FAILLOG への追記が失敗しても(書けなくても)独立に機能する
# (先に実行し、結果を後続のログ書き込みの成否に依存させない)。
#
# 加えて $_FAILLOG へ追記し、非決定的な赤を再実行して通した場合でも直前の失敗の記録を残す。
# ログはあくまで補助(画面出力を末尾で見逃した場合の保険)であり、書き込みに失敗しても
# スイートの結果(fail カウンタ・exit code)には影響させない。ただし失敗を握り潰して
# 「記録した」と偽らないよう、追記の成否を見てメッセージを変える(この保全機構自体が
# 「失敗したのに何も残らない」を再現しないようにするため)。
if [ "$fail" -gt 0 ]; then
  echo
  _format_failure_report "$fail" "${_failures[@]}"
  echo
  # 2>/dev/null を先に適用してから >> を試す(逆順だと、追記先を開けなかったときの bash 自身の
  # 診断("...: Is a directory" 等)が /dev/null 適用前のstderrへ出て漏れる。この意図的な順序が
  # 効いていることは、追記先を意図的に塞いだ検証で確認済み)。
  if {
    echo "---- $(date -u +%Y-%m-%dT%H:%M:%SZ) : ${fail} failed / ${pass} passed (${ROOT}) ----"
    printf '%s\n' "${_failures[@]}"
  } 2>/dev/null >> "$_FAILLOG"; then
    echo "(failure log: ${_FAILLOG} — 過去の失敗履歴を含む)"
  else
    echo "(failure log への追記に失敗した: ${_FAILLOG} — このログは保全されていない。今回の失敗詳細は上の画面表示のみに残っている)"
  fi
fi

echo
echo "== summary: ${pass} passed, ${fail} failed =="
[ "$fail" -eq 0 ]
