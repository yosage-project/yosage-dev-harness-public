echo "== worktree-root.sh: 割り当て作業ツリー置き場の単一ホーム =="
file_is "lib: worktree-root.sh が存在" "$H/lib/worktree-root.sh"
_wtr_guard_body="$(cat "$H/hooks/guard.sh" 2>/dev/null)"
_wtr_ec_body="$(cat "$H/lib/epic-cleanup.sh" 2>/dev/null)"
out_has "guard.sh: worktree-root.sh を source する(判定側が単一ホームを参照)" "lib/worktree-root.sh" "$_wtr_guard_body"
out_has "epic-cleanup.sh: worktree-root.sh を source する(掃除側が単一ホームを参照)" "worktree-root.sh" "$_wtr_ec_body"
out_hasnt "epic-cleanup.sh: 走査既定値にリテラル .claude/worktrees を直書きしていない(単一ホームの変数を参照)" '.claude/worktrees' "$_wtr_ec_body"

# guard.sh 側のリテラル .claude/worktrees は、単一ホームを説明する散文コメント2箇所だけになって
# いること(パターン一致・sed による切り詰めの再実装がもう無いこと)を件数で確認する。
_wtr_guard_lit_count="$(grep -c '\.claude/worktrees' "$H/hooks/guard.sh" 2>/dev/null || true)"
if [ "${_wtr_guard_lit_count:-0}" = "2" ]; then
  ok "guard.sh: リテラル .claude/worktrees の出現は説明コメント2箇所のみ(判定ロジックは単一ホームの関数を参照)"
else
  ng "guard.sh: リテラル .claude/worktrees の出現は説明コメント2箇所のみ(判定ロジックは単一ホームの関数を参照) (実測: ${_wtr_guard_lit_count:-0}件)"
fi

# 規律ファイル(不変条件)が置かれ、cross-repo 手順(SKILL.md)が散文で再記述せず名前参照している。
out_has "rules/harness: worktree-placement.md が存在" "割り当て作業ツリーの置き場" "$(cat "$H/rules/worktree-placement.md" 2>/dev/null)"
out_has "epic-implement: cross-repo 手順が worktree-placement を名前参照する" "[[worktree-placement]]" "$(cat "$H/skills/epic-implement/SKILL.md" 2>/dev/null)"

# 壊して確認: 単一ホーム(worktree-root.sh)の値を変えたとき、判定側(guard.sh)・掃除側
# (epic-cleanup.sh)の両方が追随することを見る。片方しか追随しなければ集約できていない。
# 空振りした場合にどう見えるか: 判定側が追随しなければ新置き場での exit_is が 0 のまま(旧置き場と
# 区別が付かず block されない)、掃除側が追随しなければ $WT_ASSIGNED_ROOT_RELPATH が旧値のまま
# ".claude/worktrees" が出力される。
# guard.sh・epic-cleanup.sh は worktree-root.sh を自分自身の BASH_SOURCE から見た相対位置
# (../lib/worktree-root.sh)で source する(CLI で導入先へコピーした .claude/lib/ を読みに
# 行かない)ため、値を壊すには payload 一式を一時コピーしてそちら側の harness/lib/ を書き換える
# (_src_copy。実 repo の追跡ファイルは書き換えない)。
t_wtm="$(_src_copy)"
cat > "$t_wtm/harness/lib/worktree-root.sh" <<'MUTATED'
#!/usr/bin/env bash
set -uo pipefail
WT_ASSIGNED_ROOT_RELPATH=".claude/wt-mutated"
wt_assigned_root() {
  local cwd="${1:-}"
  local relpath_re="${WT_ASSIGNED_ROOT_RELPATH//./\\.}"
  case "$cwd" in
    */"$WT_ASSIGNED_ROOT_RELPATH"/*)
      printf '%s' "$cwd" | sed -E "s#(.*/${relpath_re}/[^/]+).*#\\1#"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
MUTATED

_wtm_old="/Users/x/repo/.claude/worktrees/agent-1"
_wtm_new="/Users/x/repo/.claude/wt-mutated/agent-1"
_wtm_outer="/Users/x/repo"
json_cmd_cwd "cd $_wtm_outer/.. && git checkout -b x" "$_wtm_old" | bash "$t_wtm/harness/hooks/guard.sh" >/dev/null 2>&1
exit_is "壊して確認(guard.sh (C) Bash経由git): 単一ホームを変えると旧置き場では発火しなくなる" 0 "$?"
json_cmd_cwd "cd $_wtm_outer/.. && git checkout -b x" "$_wtm_new" | bash "$t_wtm/harness/hooks/guard.sh" >/dev/null 2>&1
exit_is "壊して確認(guard.sh (C) Bash経由git): 単一ホームを変えると新置き場で発火する(判定側が単一ホームに追随)" 2 "$?"

# (I) Write/Edit/MultiEdit 経路(tool_input.file_path 判定)も同じ wt_assigned_root を呼ぶため、
# (C) と独立に直接叩いて確認する((C) の間接証明だけでは (I) 側の追随を担保しない)。
# 事前に決めた空振りの見え方: (I) が単一ホームに追随していなければ、旧置き場ケースが exit 2 の
# まま(発火し続ける)か、新置き場ケースが exit 0 のまま(発火しない)のどちらかになる。
json_file "$_wtm_outer/foo.txt" "$_wtm_old" | bash "$t_wtm/harness/hooks/guard.sh" >/dev/null 2>&1
exit_is "壊して確認(guard.sh (I) 書き込み先判定): 単一ホームを変えると旧置き場では発火しなくなる" 0 "$?"
json_file "$_wtm_outer/foo.txt" "$_wtm_new" | bash "$t_wtm/harness/hooks/guard.sh" >/dev/null 2>&1
exit_is "壊して確認(guard.sh (I) 書き込み先判定): 単一ホームを変えると新置き場で発火する(判定側が単一ホームに追随)" 2 "$?"

_wtm_val="$(bash -c 'source "$1"; printf "%s" "$WT_ASSIGNED_ROOT_RELPATH"' _ "$t_wtm/harness/lib/epic-cleanup.sh" 2>/dev/null)"
out_has "壊して確認(epic-cleanup.sh): 単一ホームを変えると走査既定値も追随する(掃除側が単一ホームに追随)" ".claude/wt-mutated" "$_wtm_val"
rm -rf "$t_wtm"

echo "== worktree-root.sh: 共有ライブラリの欠落/読み取り不可時、判定できないまま止める(fail-closed) =="
# 以前は guard.sh が worktree-root.sh を best-effort で source しており、欠落/読み取り不可時は
# worktree 隔離判定がエラーも警告も出さずに無効化されていた(fail-open)。_guard_require_lib
# 導入によりこの経路は撤去し、lib が読み込めない場合は判定できないとして exit 2 で止める
# (fail-open をやめる。フックは exit 2 以外で終わると素通りになるため、止めるときは必ず exit 2)。
# guard.sh は自分自身の BASH_SOURCE から見た相対位置で worktree-root.sh を source するため、
# 欠落/読み取り不可を再現するにも payload 一式の一時コピー(_src_copy)を使う。
t_wtl="$(_src_copy)"
_wtl_wt="/Users/x/repo/.claude/worktrees/agent-1"
_wtl_outer="/Users/x/repo"

# 対照: ライブラリがある状態では遮断される(片側だけで確認すると「常に素通ししているだけ」の
# 可能性を排除できないため、必ず対になる遮断側も確認する)。
json_file "$_wtl_outer/foo.txt" "$_wtl_wt" | bash "$t_wtl/harness/hooks/guard.sh" >/dev/null 2>&1
exit_is "worktree-root.sh 欠落回帰: ライブラリがある状態では遮断される(対照)" 2 "$?"

# 欠落(ファイルが存在しない): 判定できないため exit 2 で止まる(fail-closed)
rm -f "$t_wtl/harness/lib/worktree-root.sh"
_wtl_missing_out="$(json_file "$_wtl_outer/foo.txt" "$_wtl_wt" | bash "$t_wtl/harness/hooks/guard.sh" 2>&1)"
_wtl_missing_exit=$?
exit_is "worktree-root.sh 欠落回帰: ライブラリが存在しないと判定できず exit 2(fail-closed)" 2 "$_wtl_missing_exit"
out_has "worktree-root.sh 欠落回帰: ライブラリが存在しない場合は読み込めない旨のメッセージが出る" "worktree-root.sh" "$_wtl_missing_out"

# 権限不可(存在するが読めない): 同じく判定できず exit 2 で止まる。
cp "$H/lib/worktree-root.sh" "$t_wtl/harness/lib/worktree-root.sh"
chmod 000 "$t_wtl/harness/lib/worktree-root.sh"
_wtl_denied_out="$(json_file "$_wtl_outer/foo.txt" "$_wtl_wt" | bash "$t_wtl/harness/hooks/guard.sh" 2>&1)"
_wtl_denied_exit=$?
exit_is "worktree-root.sh 欠落回帰: ライブラリが読み取り不可でも判定できず exit 2(fail-closed)" 2 "$_wtl_denied_exit"
out_has "worktree-root.sh 欠落回帰: 読み取り不可時も読み込めない旨のメッセージが出る" "worktree-root.sh" "$_wtl_denied_out"
chmod 644 "$t_wtl/harness/lib/worktree-root.sh"
rm -rf "$t_wtl"
