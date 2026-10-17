#!/usr/bin/env bash
# harness/lib/git-outermost-root.sh — 現在地から上へ辿って最も外側の git リポジトリを見つける共有ロジック。
#
# `gh-review.sh`(外向き投稿の識別子チェックで自組織を導出する箇所)と `epic-scope-resolve.sh`
# (Epic の計画ドキュメントの置き場を解決する箇所)の双方が同じ探索に依存している。
# 以前はこの探索ロジックが2箇所にバイト単位で重複していたため、ここへ1箇所へ集約する。
#
# このファイルは以下から source して使用する(BASH_SOURCE[0] 基点で解決 → install 先でも正しく動く):
#   - harness/lib/gh-review.sh
#   - harness/lib/epic-scope-resolve.sh
#
# CLI エントリポイントは持たない(source 専用。harness/lib/secret-patterns.sh と同じ位置づけ)。

# 現在地(cwd)から上へ辿って見つかる、最も外側の git リポジトリの絶対パスを表示する。
# 自分自身を候補に含める(own_top で初期化する。上に他の git リポジトリが見つかるたびに
# outer_top を更新し、見つからなくなったところで打ち切る=そこまでで見つかった最も外側の
# ものが残る)。上に他のリポジトリが無ければ自分自身が最も外側になる(単一リポジトリの
# 導入先での後方互換)。git リポジトリの外なら何も出力せず非ゼロ終了。
git_outermost_root() {
  local own_top outer_top probe t
  own_top="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$own_top" ] || return 1

  outer_top="$own_top"
  probe="$(dirname "$own_top")"
  while [ -n "$probe" ] && [ "$probe" != "/" ]; do
    t="$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$t" ]; then
      outer_top="$t"
      probe="$(dirname "$t")"
    else
      break
    fi
  done
  printf '%s\n' "$outer_top"
  return 0
}
