#!/usr/bin/env bash
# update-base.sh — マージ後の掃除の前に、手元の base ブランチを壊さない範囲で origin に追いつかせる。
#
# なぜ要るか: `git branch -d` は、消すブランチが「今の HEAD」か「そのブランチの追跡先」に取り込まれて
# いるかで判定する。手元の base が origin より遅れていると、マージ済みのブランチでも未マージと判定
# されて消せない(追跡先を持たない worktree-agent-* ブランチは必ずこうなる)。
#
# 手順: git fetch origin → base を解決(lib/base-branch.sh) → 手元の base を次のどれかで進める。
#   - 手元の base が無い          … 何もしない(rc 0)
#   - 手元と origin が同じ・手元が先行 … 何もしない(rc 0。先行分は戻さない)
#   - 遅れていて、どこかの作業ツリーでチェックアウト中 … 変更が無ければそこで git merge --ff-only
#   - 遅れていて、チェックアウトされていない        … git fetch origin <base>:<base>
#   - 分岐している・変更がある・進められない … 何もせず理由を stderr に出して非0(強制しない)
# reset --hard・pull(merge コミットを作りうる)・-D・--force は使わない。
#
# 終了コード(別のスクリプトなので、base-branch.sh・epic-cleanup.sh の終了コードとは独立。1/2/3 だけは
# base の解決の結果をそのまま返す):
#   0  進めた／進める必要が無かった
#   1/2/3 base を解決できなかった(lib/base-branch.sh の意味のまま)
#   10 git fetch origin に失敗した
#   11 早送りで進められない(分岐している・早送りの実行が失敗した)
#   12 base をチェックアウト中の作業ツリーに、追跡ファイルの未コミットの変更がある
#   13 origin/<base> が実在しない(prune 後など。名前を直すか git remote set-head origin --auto を実行する)
#   64 引数の誤り(--declared の値が空・無い、不明なオプション等)
#
# 使い方: yosage-dev-harness-update-base [--declared <name>] [<repo-root>]
set -uo pipefail

# shellcheck source=./base-branch.sh
source "$(dirname "${BASH_SOURCE[0]}")/base-branch.sh"

UB_RC_FETCH=10
UB_RC_NOFF=11
UB_RC_DIRTY=12
UB_RC_NO_REF=13

ub_log() { printf 'update-base: %s\n' "$1" >&2; }

# base をチェックアウト中の作業ツリーのパスを表示する(無ければ何も出さない)。
ub_checkout_path() {  # <repo> <branch>
  git -C "$1" worktree list --porcelain | awk -v b="refs/heads/$2" '
    $1=="worktree" { sub(/^worktree /,""); p=$0 }
    $1=="branch" && $2==b { print p; exit }'
}

ub_update_base() {  # <repo> [declared]
  local repo="${1:?repo is required}" declared="${2:-}" base wt
  git -C "$repo" fetch origin >/dev/null 2>&1 || { ub_log "git fetch origin に失敗したため、手元の base を進めずに終了する"; return "$UB_RC_FETCH"; }
  base="$(bb_resolve "$repo" "$declared" 2>/dev/null)" || { local rc=$?; ub_log "base を決められない(base-branch の終了コード $rc)。進めずに終了する"; return "$rc"; }
  if ! git -C "$repo" show-ref --verify -q "refs/remotes/origin/$base"; then
    ub_log "origin に $base が無い(refs/remotes/origin/$base が実在しない)ため進めずに終了する(名前を直すか、git remote set-head origin --auto を実行する)"; return "$UB_RC_NO_REF"
  fi
  if ! git -C "$repo" show-ref --verify -q "refs/heads/$base"; then
    ub_log "手元に $base が無いため何もしない"; return 0
  fi
  local l o
  l="$(git -C "$repo" rev-parse "refs/heads/$base")"; o="$(git -C "$repo" rev-parse "refs/remotes/origin/$base")"
  if [ "$l" = "$o" ]; then ub_log "$base は origin/$base と同じ"; return 0; fi
  if git -C "$repo" merge-base --is-ancestor "$o" "$l"; then
    ub_log "$base は origin/$base より先行している(戻さない・進めない)"; return 0
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$l" "$o"; then
    ub_log "$base は origin/$base と分岐していて早送りできない。進めずに終了する(人が判断する)"; return "$UB_RC_NOFF"
  fi
  wt="$(ub_checkout_path "$repo" "$base")"
  if [ -n "$wt" ]; then
    if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no)" ]; then
      ub_log "$base をチェックアウト中の $wt に未コミットの変更があるため進めずに終了する(人が判断する)"; return "$UB_RC_DIRTY"
    fi
    git -C "$wt" merge --ff-only "refs/remotes/origin/$base" >/dev/null 2>&1 \
      || { ub_log "$wt での git merge --ff-only に失敗した(未追跡ファイルの衝突等)。進めずに終了する"; return "$UB_RC_NOFF"; }
  else
    git -C "$repo" fetch origin "$base:$base" >/dev/null 2>&1 \
      || { ub_log "git fetch origin $base:$base に失敗した。進めずに終了する"; return "$UB_RC_NOFF"; }
  fi
  ub_log "$base を origin/$base まで進めた"
  return 0
}

ub_main() {
  local declared="" repo=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --declared)
        [ "$#" -ge 2 ] && [ -n "$2" ] || { ub_log "--declared には空でない名前が要る"; return 64; }
        declared="$2"; shift 2 ;;
      --declared=*)
        declared="${1#--declared=}"
        [ -n "$declared" ] || { ub_log "--declared には空でない名前が要る"; return 64; }
        shift ;;
      -*) ub_log "不明なオプション: $1"; return 64 ;;
      *) [ -z "$repo" ] || { ub_log "引数が多い"; return 64; }; repo="$1"; shift ;;
    esac
  done
  repo="${repo:-$PWD}"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { ub_log "git リポジトリの外($repo)"; return 2; }
  ub_update_base "$repo" "$declared"
}

if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  ub_main "$@"
fi
