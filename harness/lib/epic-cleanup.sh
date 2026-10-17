#!/usr/bin/env bash
# epic-cleanup.sh — Epic 実装完了後の「ローカルブランチ・worktree クリーンアップ」ロジック。
#
# 目的: PR 作成済み(push 済み)の Epic ブランチ・worktree を安全に掃除する。安全性は「マージ後も
# リモートブランチが残るので再取得できる」という前提(自動削除設定の有無は導入先のリポジトリ設定
# 次第で断定できない)ではなく、削除コマンドの選択によって担保する — force(`-D`)は使わず merge
# 確認つき削除(`-d`)だけを行うため、未マージ/使用中なら削除が失敗する側に倒れる(詳細は下記
# 「安全設計」の該当項)。
#
# 安全設計(いずれも過去の実装検証で判明した既知の落とし穴への対策):
# - 判定は fetch したうえでリモートの Epic ブランチ(origin/<epic>)を基準にする。ローカルの Epic
#   ブランチは更新されないことがあり、それを基準にすると途中でマージ済みの Sub-issue を消せない。
#   fetch の失敗・基準の ref が無いときは、古いローカルで判定せず何も消さずに止める(終了コードは
#   epic_cleanup の上の定義)。
# - Epic の途中(Epic ブランチが既定ブランチへ未マージ)は Epic ブランチ自身と、それをチェックアウト
#   している作業ツリーを消さない。完了時(既定ブランチの first-parent に Epic ブランチを取り込んだ
#   マージコミットがある)だけ、ローカルの Epic ブランチも消す。
# - 対象は「この Epic 集合」(epic ブランチに merge 済みのブランチ。完了時は epic ブランチ本体も) だけに
#   限定する。worktree 置き場には他タスク・他 Epic の現役 worktree が同時に存在しうるため、
#   「その置き場の配下にある」だけでは対象を絞ったことにならない(無関係な稼働中 worktree を
#   巻き込みうる)。worktree の削除もブランチの削除も、必ずこの Epic 集合でフィルタする。
# - 「epic ブランチに merge 済み」だけで絞ると、epic ブランチは base(導入先の既定ブランチ)から分岐して
#   いるため base の履歴を丸ごと祖先に持ち、「base へ既に merge 済みで消し忘れているだけの
#   無関係な古いブランチ」まで無条件でヒットしてしまう。base に対する `--no-merged` を併せて
#   課すことで、base に既に含まれる履歴を除外し、この Epic 固有の履歴だけに絞る。
# - detached HEAD 等でチェックアウト中ブランチ名が空になる worktree がある場合、空文字列を
#   そのまま `grep -qFx` の検索パターンに使うと「空行」(merge 済み集合が空のときの
#   `printf '%s\n' ""` 出力等) に誤マッチしうる。ブランチ名が空なら対象判定そのものをスキップする。
# - worktree の置き場フィルタは末尾スラッシュを正規化して境界を確定する。素の部分文字列一致
#   のままだと、置き場のパスがプレフィックスとして重なるだけの別ディレクトリ(例 "<root>-legacy/...")
#   の worktree まで巻き込んでしまう。
# - force(`-D`)は使わず merge 確認つき削除(`-d`)だけを行う。`-d` で消せない未マージ/使用中の
#   ブランチは削除せず一覧表示し、要否の判断を人に委ねる(全ローカルブランチの強制削除は行わない)。
#
# 使い方: yosage-dev-harness-epic-cleanup <epic_branch> [base_branch] [worktrees_root]
#   epic_branch     … 例 epic/<epic-name>
#   base_branch     … 既定は lib/base-branch.sh の解決(導入先の既定ブランチ＝origin/HEAD)。決まらなければ
#                      何も消さずに非ゼロで終わる(epic ブランチの分岐元。この履歴を除外基準に使う)。
#                      比較は常に origin/<base_branch>(ローカルの base は使わない)
#   worktrees_root  … 既定は割り当て作業ツリー置き場の単一ホーム(worktree-root.sh)の値
#                      (worktree 走査を絞る置き場)
#
# 出力: 先頭に「基準: <R>@<sha>（途中|完了）、base: <name>（<出どころ>）、除外の基準: <ref>」。
#   対象が0件なら「対象: 0件（…）」。続いて「deleted: <branch>」「skip (未マージ or 使用中): <branch>」を1行ずつ標準出力へ。
#   worktree 除去は stderr へ 1行ログ(epic-cleanup: worktree removed: <path> (<branch>))。
set -uo pipefail

# 割り当て作業ツリー置き場の単一ホーム(WT_ASSIGNED_ROOT_RELPATH)を source する。遮断の判定
# (hooks/guard.sh)と同じ値を参照するため、既定値をここへ直接書かない(worktree-root.sh 冒頭
# コメント参照)。
# shellcheck source=./worktree-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/worktree-root.sh"

# 保護すべきブランチ集合(base ブランチ・main・master・epic ブランチ)の単一ホームを source する。
# 除外リストをここへ直接書かない(branch-protection.sh 冒頭コメント参照。過去に除外リストを
# このファイルの中だけにハードコードしていたため `master` の欠落が起きたことがある)。
# shellcheck source=./branch-protection.sh
source "$(dirname "${BASH_SOURCE[0]}")/branch-protection.sh"

# ベースブランチの解決の単一ホーム(base_branch が渡されないときの既定値。ここへ直書きしない)。
# shellcheck source=./base-branch.sh
source "$(dirname "${BASH_SOURCE[0]}")/base-branch.sh"

ec_log() { printf 'epic-cleanup: %s\n' "$1" >&2; }

# 終了コード(`lib/base-branch.sh` の 0/1/2/3/64 と重ならない値。1 は base が決まらないときの既存の値):
#   0  掃除した(対象が0件でも、0件と出して0)
#   1  ベースブランチが決まらない(何も消さない)
#   10 git fetch --prune origin に失敗した(古いローカルで判定しない。何も消さない)
#   11 基準の ref が実在しない(リモートの Epic ブランチ・origin/<base> が無く、救済もできない。何も消さない)
#   マージコミットが無く、Epic ブランチが既定ブランチの先端と同じか祖先なだけのときは、途中として何も消さずに0で終わる
#   (fast-forward で入ったかは、作ったばかりの場合と履歴から区別できないため判定しない)
EC_RC_FETCH=10
EC_RC_NO_REF=11

# 完了の判定: <base_ref> の first-parent の履歴の上に、<R> を取り込んだマージコミット
# (R が第2親の祖先で、第1親の祖先ではない)があれば、そのマージコミットを表示して rc 0。無ければ rc 1。
# Epic の PR はマージコミットで入る(squash・rebase はしない)ので、これが完了の印になる。
ec_find_integration_merge() {  # <R> <base_ref>
  local r="${1:?R is required}" bref="${2:?base_ref is required}" m
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    git merge-base --is-ancestor "$r" "$m^2" 2>/dev/null || continue
    git merge-base --is-ancestor "$r" "$m^1" 2>/dev/null && continue
    printf '%s\n' "$m"
    return 0
  done < <(git rev-list --first-parent --merges --reverse "$bref" --not "$r" 2>/dev/null)
  return 1
}

# この Epic に merge 済みのブランチ集合を改行区切りで表示する(保護すべきブランチは除外)。
# worktree の有無に依存しないため、worktree を消した後の再実行でも同じ集合を再収集できる。
#   R           … 「マージ済み」の基準(リモートの Epic ブランチ。origin/<epic>)
#   exclude_ref … これに含まれる履歴を除く(途中は origin/<base>、完了時は取り込み前の親)
ec_merged_branches() {  # <epic_branch> <base_branch> <R> <exclude_ref>
  local epic_branch="${1:?epic_branch is required}" base_branch="${2:?base_branch is required}"
  local r="${3:?R is required}" exclude="${4:?exclude_ref is required}"
  git branch --format='%(refname:short)' --merged "$r" --no-merged "$exclude" \
    | grep -vFxf <(bp_protected_branches "$base_branch" "$epic_branch")
}

# 対象 worktree(チェックアウト中ブランチが対象集合に入るもの)だけを remove する。
# 他タスク・他 Epic の現役 worktree はこの集合に入らないので触らない。Epic ブランチをチェックアウト
# している作業ツリーは、Epic ブランチが対象集合に入るとき(完了時)だけ消える。
ec_remove_worktrees() {  # <targets(改行区切り)> [worktrees_root]
  local targets="${1:-}" root="${2:-$WT_ASSIGNED_ROOT_RELPATH}"
  # 末尾スラッシュを正規化して境界を確定させる(`${root%/}/`)。素の `grep -F "$root"` は部分文字列
  # 一致なので、`$root` がプレフィックスとして重なるだけの別ディレクトリ(例 "$root-legacy/...")の
  # worktree 行まで巻き込んでしまう。末尾スラ付きにすることで「そのディレクトリ配下」だけに絞る。
  git worktree list --porcelain | grep '^worktree ' | grep -F "${root%/}/" | awk '{print $2}' | while IFS= read -r wt; do
    br=$(git -C "$wt" branch --show-current)
    # detached HEAD 等で br が空だと、対象集合が空のとき空行に grep -qFx "" が誤マッチしうる。
    # 空なら即 skip する。
    [ -z "$br" ] && continue
    # here-string(パイプではなく単純なリダイレクト)で渡す。`printf ... | grep -qFx` という
    # 素朴なパイプだと、`grep -q` は一致した時点で読み込みを打ち切るため、`printf` 側がまだ
    # 書き込み中だと SIGPIPE(終了コード141)で終了しうる。set -o pipefail 下ではこの141が
    # パイプライン全体の終了コードになり、実際には一致していたのに「不一致」として扱ってしまう
    # (高負荷でタイミングがずれると顕在化するレース)。
    # here-string はパイプラインの一員ではない: `<<<` の中身を書き込むのはコマンド起動前の
    # シェル自身であり、`grep` を fork/exec する時点で書き込みは既に完了している。SIGPIPE を
    # 受けうる別プロセスの書き手が存在しないため、この種のレースが構造的に起きない。`-e` は `$br` が
    # `-` で始まる値であってもオプションと誤認されないようにする安全策。
    if grep -qFx -e "$br" <<< "$targets"; then
      git worktree remove "$wt" && ec_log "worktree removed: $wt ($br)"
    fi
  done
}

# 削除対象は対象集合のみ(全ローカルブランチは対象にしない)。
# force(-D) は使わず merge 済み確認つき削除(-d)だけを行う。-d で消せない未マージ/使用中の
# ブランチは削除せず一覧表示し、要否の判断を人に委ねる。
# マージ後にリモートのブランチが自動で消える導入先では、ローカルのブランチの上流が消えて
# `-d` が「not fully merged」で失敗する。消す前に上流を基準 R へ付け替えて、R に入っているかで
# `-d` に判定させる(force にはしない)。Epic ブランチ自身(完了時)は R が自分なので、上流を
# 既定ブランチ側(<epic_upstream>)にする。
ec_delete_branches() {  # <R の上流にする ref> <epic_branch> <epic_upstream> <targets(改行区切り。Epic ブランチは最後)>
  local r="${1:?R is required}" epic_branch="${2:?epic_branch is required}" epic_up="${3:?epic_upstream is required}" targets="${4:-}"
  local b up
  printf '%s\n' "$targets" | while IFS= read -r b; do
    [ -z "$b" ] && continue
    up="$r"
    [ "$b" = "$epic_branch" ] && up="$epic_up"
    git branch --set-upstream-to="$up" "$b" >/dev/null 2>&1
    if git branch -d "$b" >/dev/null 2>&1; then
      echo "deleted: $b"
    else
      echo "skip (未マージ or 使用中): $b"
    fi
  done
}

epic_cleanup() {  # <epic_branch> [base_branch] [worktrees_root]
  local epic_branch="${1:?epic_branch is required}"
  local base_branch="${2:-}"
  local worktrees_root="${3:-$WT_ASSIGNED_ROOT_RELPATH}"
  local base_source="指定" r r_label phase merge_commit exclude_ref targets merged n

  # 1. 判定の前に必ず fetch する。失敗したら古いローカルで判定せず止める。
  if ! git fetch --prune origin >/dev/null; then
    ec_log "git fetch --prune origin に失敗したため、古いローカルのブランチでは判定せず、何も消さずに終了する"
    return "$EC_RC_FETCH"
  fi

  # ベース: 渡されなければ導入先の既定ブランチ(origin/HEAD)で決める。決まらなければ何も消さずに止める。
  if [ -z "$base_branch" ]; then
    base_branch="$(bb_resolve "$PWD")" || { ec_log "ベースブランチを決められないため何も消さずに終了する"; return 1; }
    base_source="origin/HEAD"
  fi
  # 比較の基準は常に origin 側(ローカルの base は古いことがあるので優先しない)。実在しなければ
  # (origin/HEAD が削除・prune 済みのブランチを指す等)、空の集合で黙って終わらず止めて報告する。
  if ! git show-ref --verify -q "refs/remotes/origin/$base_branch"; then
    ec_log "基準の ref origin/$base_branch が実在しないため、何も消さずに終了する(名前を直すか、git remote set-head origin --auto を実行する)"
    return "$EC_RC_NO_REF"
  fi

  # 2. 基準 R: リモートの Epic ブランチ。無い(完了してリモートが消えた)ときは、既定ブランチの first-parent の
  #    履歴から Epic ブランチを取り込んだマージコミット M を探し、あれば M の第2親を使う。ローカルの Epic ブランチは
  #    古いまま(計画をコミットしない構成では、作成時点の既定ブランチと同じ位置)でも、取り込み前の親の祖先に
  #    なるだけで完了を検出できないため、先に使わない。M が無いときだけ、ローカルの Epic ブランチが既定ブランチに
  #    取り込まれている場合に限ってローカルを使う。それ以外は止めて報告する。
  #    r_up は、ブランチの上流に付け替える ref(R が SHA のときは、R を含む origin/<base> で代える)。
  local r_up
  if git show-ref --verify -q "refs/remotes/origin/$epic_branch"; then
    r="origin/$epic_branch"; r_up="$r"; r_label="$r"
  elif merge_commit="$(git log --first-parent --merges -E "origin/$base_branch" \
         --grep="${epic_branch}(\$|[^[:alnum:]_/.-])" --format=%H 2>/dev/null | head -n 1)" \
       && [ -n "$merge_commit" ] && r="$(git rev-parse --verify -q "$merge_commit^2")"; then
    r_up="origin/$base_branch"; r_label="$epic_branch"
  elif git show-ref --verify -q "refs/heads/$epic_branch" \
       && git merge-base --is-ancestor "refs/heads/$epic_branch" "origin/$base_branch" 2>/dev/null; then
    r="refs/heads/$epic_branch"; r_up="$r"; r_label="$epic_branch"
  else
    ec_log "基準の ref origin/$epic_branch が実在しない(ローカルの $epic_branch が origin/$base_branch に取り込まれているわけでもない)ため、何も消さずに終了する"
    return "$EC_RC_NO_REF"
  fi

  # 3. 途中か完了か。
  if merge_commit="$(ec_find_integration_merge "$r" "origin/$base_branch")"; then
    phase="完了"
    exclude_ref="$(git rev-parse "$merge_commit^1")"
  else
    phase="途中"
    exclude_ref="origin/$base_branch"
  fi

  printf '基準: %s@%s（%s）、base: %s（%s）、除外の基準: %s\n' \
    "$r_label" "$(git rev-parse --short "$r")" "$phase" "$base_branch" "$base_source" "$exclude_ref"
  if [ "$phase" = "途中" ] && git merge-base --is-ancestor "$r" "origin/$base_branch" 2>/dev/null; then
    # マージコミットが無く、Epic ブランチが既定ブランチの先端と同じか祖先: 作ったばかり(Sub-issue が
    # まだ入らないうちに既定ブランチが進んだ場合を含む)の場合と、fast-forward で入った場合とを、履歴から
    # 区別できない。判定せず途中として扱い、何も消さない(Epic の PR はマージコミットで入る決まりなので、
    # fast-forward は普通は起きない)。
    echo "注意: $r_label は origin/$base_branch の先端と同じか祖先で、取り込んだマージコミットが無い(作ったばかりの場合と、fast-forward で入った場合と区別できない)。途中として扱い、何も消さない"
  fi

  # 4. 集合。完了時だけ、ローカルの Epic ブランチを最後に足す(途中は Epic ブランチ自身を消さない)。
  merged="$(ec_merged_branches "$epic_branch" "$base_branch" "$r" "$exclude_ref")"
  targets="$merged"
  if [ "$phase" = "完了" ] && git show-ref --verify -q "refs/heads/$epic_branch"; then
    targets="$(printf '%s\n%s' "$merged" "$epic_branch" | sed '/^$/d')"
  fi
  if [ -z "$targets" ]; then
    echo "対象: 0件（$r_label に取り込み済みで、$exclude_ref に含まれないブランチは無い）"
  fi

  # 5・6. 作業ツリー → ブランチ。
  ec_remove_worktrees "$targets" "$worktrees_root"
  ec_delete_branches "$r_up" "$epic_branch" "origin/$base_branch" "$targets"

  # 7. 完了時、リモートの Epic ブランチが残っていれば報告する(消さない)。
  if [ "$phase" = "完了" ]; then
    n="$(git ls-remote --heads origin "$epic_branch" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n:-0}" -gt 0 ]; then
      echo "remote に Epic ブランチが残っている: origin/$epic_branch（消していない。人に削除を依頼する）"
    fi
  fi
  return 0
}

# 直接実行された場合のみ CLI として動く(テストからの source では呼ばれない)。
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  epic_cleanup "$@"
fi
