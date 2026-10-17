echo "== update-base.sh: マージ後の掃除の前に手元の base を壊さない範囲で進める =="
file_is "lib: update-base.sh が存在" "$H/lib/update-base.sh"
file_is "bin: yosage-dev-harness-update-base が存在" "$H/bin/yosage-dev-harness-update-base"
_ub_bin="$H/bin/yosage-dev-harness-update-base"

# 1回の実行で stdout・stderr・rc をまとめて取る。
_ub_run() {  # <args...>: _ub_out / _ub_err / _ub_rc
  local ef; ef="$(mktemp)"
  _ub_out="$(bash "$_ub_bin" "$@" 2>"$ef")"; _ub_rc=$?
  _ub_err="$(cat "$ef")"; rm -f "$ef"
}
# 構成: remote.git(develop)・work(掃除をする側)・other(別の人。origin の develop を進める側)。
_ub_setup() {  # <dir>: feat/x を work で作って push し、other で develop へマージして push する(work の develop は遅れ)
  local d="$1"
  mk_bare_remote_clone "$d" --default develop || return 1
  git clone -q "$d/remote.git" "$d/other" 2>/dev/null || return 1
  gitc -C "$d/work" checkout -q -b feat/x && gitc -C "$d/work" commit -q --allow-empty -m f1 \
    && git -C "$d/work" push -q origin feat/x && git -C "$d/work" checkout -q develop || return 1
  git -C "$d/other" fetch -q origin && gitc -C "$d/other" merge -q --no-ff origin/feat/x -m "merge x" \
    && git -C "$d/other" push -q origin develop
}
_ub_origin_sha() { git -C "$1/remote.git" rev-parse develop; }

# --- 遅れていて develop をチェックアウト中・変更なし: merge --ff-only で進み、-d で消せる ---
_ub_a="$(mktemp -d)"; _ub_setup "$_ub_a"
git -C "$_ub_a/work" fetch -q origin
git -C "$_ub_a/work" branch -d feat/x >/dev/null 2>&1
exit_is "実測: 手元の develop が遅れたままだとマージ済みの feat/x を -d で消せない" 1 "$?"
_ub_run "$_ub_a/work"
exit_is "チェックアウト中・変更なし・遅れ: rc 0" 0 "$_ub_rc"
[ "$(git -C "$_ub_a/work" rev-parse develop)" = "$(_ub_origin_sha "$_ub_a")" ] && ok "develop が origin/develop まで進んだ" || ng "develop が origin/develop まで進んだ"
git -C "$_ub_a/work" branch -d feat/x >/dev/null 2>&1
exit_is "進めたあとは feat/x を -d で消せる" 0 "$?"
_ub_run "$_ub_a/work"
exit_is "もう一度実行(すでに同じ): rc 0" 0 "$_ub_rc"

# --- 分岐: 手元の develop に独自コミット + origin も別コミットで進む → 進めず rc 11 ---
gitc -C "$_ub_a/work" commit -q --allow-empty -m local-only
gitc -C "$_ub_a/other" commit -q --allow-empty -m remote-only && git -C "$_ub_a/other" push -q origin develop
_ub_before="$(git -C "$_ub_a/work" rev-parse develop)"
git -C "$_ub_a/work" fetch -q origin
git -C "$_ub_a/work" merge --ff-only origin/develop >/dev/null 2>&1
exit_is "実測: merge --ff-only は分岐していると失敗する(非0)" 128 "$?"
_ub_run "$_ub_a/work"
exit_is "分岐(チェックアウト中): rc 11" 11 "$_ub_rc"
[ "$(git -C "$_ub_a/work" rev-parse develop)" = "$_ub_before" ] && ok "分岐のときは develop を動かさない" || ng "分岐のときは develop を動かさない"
# --- 手元が先行(origin の先端が手元の祖先): 何もしない rc 0 ---
git -C "$_ub_a/work" reset -q --hard origin/develop~1 2>/dev/null; gitc -C "$_ub_a/work" commit -q --allow-empty -m ahead1
git -C "$_ub_a/work" reset -q --hard origin/develop; gitc -C "$_ub_a/work" commit -q --allow-empty -m ahead2
_ub_before="$(git -C "$_ub_a/work" rev-parse develop)"
_ub_run "$_ub_a/work"
exit_is "手元が先行: rc 0(戻さない)" 0 "$_ub_rc"
[ "$(git -C "$_ub_a/work" rev-parse develop)" = "$_ub_before" ] && ok "先行しているときは develop を動かさない" || ng "先行しているときは develop を動かさない"
rm -rf "$_ub_a"

# --- 未コミットの変更(追跡ファイル): 進めず rc 12 ---
_ub_b="$(mktemp -d)"; mk_bare_remote_clone "$_ub_b" --default develop
git clone -q "$_ub_b/remote.git" "$_ub_b/other" 2>/dev/null
echo v1 > "$_ub_b/other/t"; gitc -C "$_ub_b/other" add t; gitc -C "$_ub_b/other" commit -q -m t1; git -C "$_ub_b/other" push -q origin develop
git -C "$_ub_b/work" pull -q --ff-only origin develop 2>/dev/null
echo v2 >> "$_ub_b/other/t"; gitc -C "$_ub_b/other" commit -q -am t2; git -C "$_ub_b/other" push -q origin develop
echo dirty >> "$_ub_b/work/t"
_ub_before="$(git -C "$_ub_b/work" rev-parse develop)"
_ub_run "$_ub_b/work"
exit_is "未コミットの変更あり(チェックアウト中): rc 12" 12 "$_ub_rc"
[ "$(git -C "$_ub_b/work" rev-parse develop)" = "$_ub_before" ] && ok "変更があるときは develop を動かさない" || ng "変更があるときは develop を動かさない"
out_has "変更ありの理由を stderr に出す" "未コミットの変更" "$_ub_err"
rm -rf "$_ub_b"

# --- develop をチェックアウトしていない: fetch origin develop:develop で進む ---
_ub_c="$(mktemp -d)"; _ub_setup "$_ub_c"
git -C "$_ub_c/work" fetch -q origin
git -C "$_ub_c/work" fetch origin develop:develop >/dev/null 2>&1
exit_is "実測: develop をチェックアウト中の fetch origin develop:develop は拒否される(非0)" 128 "$?"
gitc -C "$_ub_c/work" checkout -q feat/x
_ub_run "$_ub_c/work"
exit_is "チェックアウトしていない・遅れ: rc 0" 0 "$_ub_rc"
[ "$(git -C "$_ub_c/work" rev-parse develop)" = "$(_ub_origin_sha "$_ub_c")" ] && ok "チェックアウトしていない develop が進んだ" || ng "チェックアウトしていない develop が進んだ"
# 分岐(チェックアウトしていない)
gitc -C "$_ub_c/work" commit -q --allow-empty -m diverge
gitc -C "$_ub_c/work" branch -f develop feat/x 2>/dev/null
_ub_before="$(git -C "$_ub_c/work" rev-parse develop)"
git -C "$_ub_c/work" fetch origin develop:develop >/dev/null 2>&1
exit_is "実測: fetch origin develop:develop は分岐していると拒否される(非0)" 1 "$?"
_ub_run "$_ub_c/work"
exit_is "分岐(チェックアウトしていない): rc 11" 11 "$_ub_rc"
[ "$(git -C "$_ub_c/work" rev-parse develop)" = "$_ub_before" ] && ok "分岐のときは(チェックアウトしていなくても)develop を動かさない" || ng "分岐のときは develop を動かさない"
rm -rf "$_ub_c"

# --- 別の作業ツリーが develop をチェックアウト中でも、その作業ツリーで進む ---
_ub_d="$(mktemp -d)"; _ub_setup "$_ub_d"
gitc -C "$_ub_d/work" checkout -q feat/x
git -C "$_ub_d/work" worktree add -q "$_ub_d/wt" develop 2>/dev/null
_ub_run "$_ub_d/work"
exit_is "別の作業ツリーがチェックアウト中: rc 0" 0 "$_ub_rc"
[ "$(git -C "$_ub_d/wt" rev-parse HEAD)" = "$(_ub_origin_sha "$_ub_d")" ] && ok "別の作業ツリーの develop が進んだ" || ng "別の作業ツリーの develop が進んだ"
rm -rf "$_ub_d"

# --- 未追跡ファイルが早送りで上書きされる衝突: ff-only が拒否 → rc 11・develop もファイルも動かない ---
_ub_f="$(mktemp -d)"; mk_bare_remote_clone "$_ub_f" --default develop
git clone -q "$_ub_f/remote.git" "$_ub_f/other" 2>/dev/null
echo remote > "$_ub_f/other/g"; gitc -C "$_ub_f/other" add g; gitc -C "$_ub_f/other" commit -q -m addg; git -C "$_ub_f/other" push -q origin develop
echo untracked > "$_ub_f/work/g"
_ub_before="$(git -C "$_ub_f/work" rev-parse develop)"
_ub_run "$_ub_f/work"
exit_is "未追跡ファイルとの衝突: rc 11" 11 "$_ub_rc"
[ "$(git -C "$_ub_f/work" rev-parse develop)" = "$_ub_before" ] && ok "衝突のとき develop を動かさない" || ng "衝突のとき develop を動かさない"
[ "$(cat "$_ub_f/work/g")" = "untracked" ] && ok "衝突のとき未追跡ファイルが残る" || ng "衝突のとき未追跡ファイルが残る"
rm -rf "$_ub_f"

# --- detached HEAD(どこにもチェックアウトされていない base は fetch base:base で進む) ---
_ub_g="$(mktemp -d)"; _ub_setup "$_ub_g"
git -C "$_ub_g/work" checkout -q --detach
_ub_run "$_ub_g/work"
exit_is "detached HEAD: rc 0" 0 "$_ub_rc"
[ "$(git -C "$_ub_g/work" rev-parse develop)" = "$(_ub_origin_sha "$_ub_g")" ] && ok "detached HEAD でも develop が進む" || ng "detached HEAD でも develop が進む"
rm -rf "$_ub_g"

# --- 手元に base が無い: 何もせず rc 0(ブランチを作らない) ---
_ub_h="$(mktemp -d)"; _ub_setup "$_ub_h"
git -C "$_ub_h/work" checkout -q feat/x; git -C "$_ub_h/work" branch -D develop >/dev/null 2>&1
_ub_run "$_ub_h/work"
exit_is "手元に base が無い: rc 0" 0 "$_ub_rc"
git -C "$_ub_h/work" show-ref --verify -q refs/heads/develop && ng "手元に base が無いとき作らない" || ok "手元に base が無いとき作らない"
rm -rf "$_ub_h"

# --- origin/<base> が無い(prune 後など): 誤報せず専用の理由で rc 13 ---
_ub_i="$(mktemp -d)"; _ub_setup "$_ub_i"
git -C "$_ub_i/work" update-ref -d refs/remotes/origin/develop
git -C "$_ub_i/work" config remote.origin.fetch "+refs/heads/feat/*:refs/remotes/origin/feat/*"
_ub_run "$_ub_i/work"
exit_is "origin/<base> が無い: rc 13(分岐の誤報 11 ではない)" 13 "$_ub_rc"
out_has "origin に base が無い旨を理由に出す" "origin に develop が無い" "$_ub_err"
rm -rf "$_ub_i"

# --- --declared を bb_resolve に渡す: 宣言した dev を進め、既定ブランチ(develop)は進めない ---
_ub_j="$(mktemp -d)"; mk_bare_remote_clone "$_ub_j" --default develop --branch dev
git clone -q "$_ub_j/remote.git" "$_ub_j/other" 2>/dev/null
git -C "$_ub_j/other" checkout -q dev; gitc -C "$_ub_j/other" commit -q --allow-empty -m d1; git -C "$_ub_j/other" push -q origin dev
git -C "$_ub_j/work" branch -q dev origin/dev
_ub_dev_before="$(git -C "$_ub_j/work" rev-parse dev)"
_ub_run --declared dev "$_ub_j/work"
exit_is "--declared dev: rc 0" 0 "$_ub_rc"
[ "$(git -C "$_ub_j/work" rev-parse dev)" = "$(git -C "$_ub_j/remote.git" rev-parse dev)" ] && ok "--declared で宣言した dev が進む" || ng "--declared で宣言した dev が進む"
_ub_run --declared nope "$_ub_j/work"
exit_is "--declared が origin に無い: rc 3" 3 "$_ub_rc"
rm -rf "$_ub_j"

# --- 失敗するべきときに失敗する ---
_ub_e="$(mktemp -d)"; mk_bare_remote_clone "$_ub_e" --default develop
_ub_run --declared nope "$_ub_e/work"
exit_is "--declared が origin に無い: rc 3(base-branch の意味のまま)" 3 "$_ub_rc"
_ub_nogit="$(mktemp -d)"; _ub_run "$_ub_nogit"
exit_is "git の外: rc 2" 2 "$_ub_rc"
git -C "$_ub_e/work" remote set-url origin "$_ub_e/nonexistent.git"
_ub_run "$_ub_e/work"
exit_is "git fetch origin に失敗: rc 10" 10 "$_ub_rc"
_ub_run --declared "" "$_ub_e/work"
exit_is "--declared \"\"(空の宣言): 宣言なしとして通さず rc 64" 64 "$_ub_rc"
_ub_run --declared= "$_ub_e/work"
exit_is "--declared=(空の宣言): rc 64" 64 "$_ub_rc"
_ub_run --bogus "$_ub_e/work"
exit_is "不明なオプション: rc 64" 64 "$_ub_rc"
rm -rf "$_ub_e" "$_ub_nogit"

# --- ルール・手順書からの参照(同じ要求を再記述せず名前で参照する) ---
_ub_pl="$(cat "$H/rules/pr-loop.md")"
out_has "pr-loop.md: 掃除の前に update-base を実行し --declared を渡せる形で案内(ベースと同じ)" "yosage-dev-harness-update-base [--declared" "$_ub_pl"
out_has "pr-loop.md: 非0なら理由を人に知らせ、掃除は続けてよい旨を明記" "掃除は続けてよい" "$_ub_pl"
out_has "epic-implement: base を進める手順は pr-loop の節が正本で update-base を名前で参照" "yosage-dev-harness-update-base" "$(cat "$H/skills/epic-implement/SKILL.md")"
