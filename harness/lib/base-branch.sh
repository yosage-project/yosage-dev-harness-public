#!/usr/bin/env bash
# base-branch.sh — ベースブランチ(作業ブランチの起点・PR の向け先)を解決する単一ホーム。
#
# 解決の順: 呼び出し側から渡された宣言(投入時に明示されたもの／導入先の profile の宣言。どちらも
# モデルが読んで --declared で渡す。このスクリプトは profile の文章を解析しない)
#   → GitHub の既定ブランチ(refs/remotes/origin/HEAD が指す先)→ 決まらなければ失敗する。
# ネットワークには問い合わせない(git ls-remote / gh を使わない)。fetch もしない(呼び出し側の責任)。
#
# 終了コード(epic-scope-resolve.sh の「2＝前提が欠けている」に揃える):
#   0 決まった / 1 決まらない / 2 git の外 / 3 宣言したブランチが origin に無い
#   (CLI の引数の誤りは 64)。
#
# 使い方: yosage-dev-harness-base-branch [--declared <name>] [<repo-root>]
#   stdout はブランチ名だけ(origin/ は付けない)。どちらで決まったか(source: declared|origin/HEAD)は
#   stderr に1行出す。
set -uo pipefail

bb_log() { printf 'base-branch: %s\n' "$1" >&2; }

# bb_origin_head <dir> [<git-dir>]
#   GitHub の既定ブランチ(refs/remotes/origin/HEAD が指す先)を、先頭の refs/remotes/origin/ を
#   取り除いた名前で stdout に出す(ブランチ名に / を含んでもそのまま。例 release/x)。
#   未設定なら rc 1(何も出さない)。<git-dir> は guard (J) が --git-dir 付きで呼ぶ経路のため。
bb_origin_head() {
  local dir="${1:?dir is required}" gitdir="${2:-}" ref
  local opt=()
  [ -n "$gitdir" ] && opt=(--git-dir="$gitdir")
  ref="$(git -C "$dir" "${opt[@]+"${opt[@]}"}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" || return 1
  case "$ref" in
    refs/remotes/origin/?*) printf '%s\n' "${ref#refs/remotes/origin/}" ;;
    *) return 1 ;;
  esac
}

# bb_resolve <repo_dir> [<declared>]
#   <declared> が空でなければ refs/remotes/origin/<declared> が実在するかを確かめて名前を出す(rc 0)。
#   実在しなければ rc 3。空なら bb_origin_head の結果を出す(rc 0)。決まらなければ rc 1。
#   <repo_dir> が git の外なら rc 2。
bb_resolve() {
  local dir="${1:?repo_dir is required}" declared="${2:-}" name
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || {
    bb_log "git リポジトリの外($dir)のため決められない"
    return 2
  }
  if [ -n "$declared" ]; then
    # origin/HEAD 自身は ref 名ではなく既定ブランチへの別名なので、宣言としては受け付けない。
    if [ "$declared" != "HEAD" ] \
       && git -C "$dir" show-ref --verify -q "refs/remotes/origin/$declared" 2>/dev/null; then
      printf '%s\n' "$declared"
      bb_log "source: declared"
      return 0
    fi
    bb_log "宣言されたブランチ '$declared' が origin に無い(refs/remotes/origin/$declared が実在しない)。名前を直すか、git fetch origin を実行する"
    return 3
  fi
  if name="$(bb_origin_head "$dir")"; then
    printf '%s\n' "$name"
    bb_log "source: origin/HEAD"
    return 0
  fi
  bb_log 'ベースブランチを決められない。投入時に明示する／profile に `- **base ブランチ: `<名前>`**` を書く／`git remote set-head origin --auto` を実行する、のいずれかで解決する'
  return 1
}

base_branch_main() {  # [--declared <name>] [<repo-root>]
  local declared="" dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --declared)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { bb_log "--declared には空でない名前が要る"; return 64; }
        declared="$2"; shift 2 ;;
      --declared=*)
        declared="${1#--declared=}"
        [ -n "$declared" ] || { bb_log "--declared には空でない名前が要る"; return 64; }
        shift ;;
      -*) bb_log "不明なオプション: $1(使い方: yosage-dev-harness-base-branch [--declared <name>] [<repo-root>])"; return 64 ;;
      *)
        [ -z "$dir" ] || { bb_log "<repo-root> は1つだけ指定する(2つ目: $1)"; return 64; }
        dir="$1"; shift ;;
    esac
  done
  bb_resolve "${dir:-.}" "$declared"
}

# 直接実行された場合のみ CLI として動く(source されたときは呼ばれない)。
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then base_branch_main "$@"; fi
