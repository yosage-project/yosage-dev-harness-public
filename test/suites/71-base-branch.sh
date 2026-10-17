echo "== base-branch.sh: ベースブランチを解決する単一ホーム(lib と実行ファイル) =="
file_is "lib: base-branch.sh が存在" "$H/lib/base-branch.sh"
file_is "bin: yosage-dev-harness-base-branch が存在" "$H/bin/yosage-dev-harness-base-branch"
_bb_bin="$H/bin/yosage-dev-harness-base-branch"

# --- develop の無い導入先(既定ブランチが main だけ) ---
_bb_main="$(mktemp -d)"
mk_bare_remote_clone "$_bb_main" --default main
_bb_out="$(bash "$_bb_bin" "$_bb_main/work" 2>/dev/null)"; _bb_rc=$?
exit_is "既定ブランチが main だけのリモート: 解決できる(rc 0)" 0 "$_bb_rc"
out_has "既定ブランチが main だけのリモート: main を返す(develop を前提にしない)" "main" "$_bb_out"
[ "$_bb_out" = "main" ] && ok "stdout はブランチ名だけ(origin/ を付けない)" || ng "stdout はブランチ名だけ(got: $_bb_out)"
_bb_err="$(bash "$_bb_bin" "$_bb_main/work" 2>&1 1>/dev/null)"
out_has "どちらで決まったかを stderr に出す(origin/HEAD)" "source: origin/HEAD" "$_bb_err"
_bb_out2="$(bash "$_bb_bin" "$_bb_main/work" 2>/dev/null)"
[ "$_bb_out2" = "$_bb_out" ] && ok "2回目の実行で同じ結果" || ng "2回目の実行で同じ結果(1回目: $_bb_out / 2回目: $_bb_out2)"
# カレントディレクトリが既定(<repo-root> 省略)
_bb_out="$(cd "$_bb_main/work" && bash "$_bb_bin" 2>/dev/null)"
[ "$_bb_out" = "main" ] && ok "<repo-root> 省略時はカレントディレクトリで解決する" || ng "<repo-root> 省略時はカレントディレクトリで解決する(got: $_bb_out)"

# --- 両方向: 既定ブランチが develop / --declared が origin/HEAD より優先 ---
_bb_dev="$(mktemp -d)"
mk_bare_remote_clone "$_bb_dev" --default develop --branch dev
_bb_out="$(bash "$_bb_bin" "$_bb_dev/work" 2>/dev/null)"
[ "$_bb_out" = "develop" ] && ok "既定ブランチが develop のリモート: develop を返す" || ng "既定ブランチが develop のリモート(got: $_bb_out)"
_bb_out="$(bash "$_bb_bin" --declared dev "$_bb_dev/work" 2>/dev/null)"; _bb_rc=$?
exit_is "--declared dev(origin に dev がある): rc 0" 0 "$_bb_rc"
[ "$_bb_out" = "dev" ] && ok "--declared が origin/HEAD より優先される" || ng "--declared が origin/HEAD より優先される(got: $_bb_out)"
_bb_err="$(bash "$_bb_bin" --declared dev "$_bb_dev/work" 2>&1 1>/dev/null)"
out_has "--declared で決まったら source: declared を出す" "source: declared" "$_bb_err"

# --- 失敗するべきときに失敗する ---
# 1回の実行で stdout・stderr・rc をまとめて取る(stderr は一時ファイルへ)。
_bb_run() {  # <args...>: _bb_out / _bb_err / _bb_rc を設定する
  local ef; ef="$(mktemp)"
  _bb_out="$(bash "$_bb_bin" "$@" 2>"$ef")"; _bb_rc=$?
  _bb_err="$(cat "$ef")"; rm -f "$ef"
}
_bb_run --declared nope "$_bb_dev/work"
exit_is "--declared nope(origin に無い): rc 3" 3 "$_bb_rc"
out_has "--declared nope: 宣言したブランチが origin に無い旨を出す" "nope" "$_bb_err"
out_is_empty "--declared nope: stdout は空" "$_bb_out"
_bb_run --declared HEAD "$_bb_dev/work"
exit_is "--declared HEAD は宣言として受け付けない(rc 3)" 3 "$_bb_rc"
# revision 構文は実在する ref の名前ではないので宣言として通さない
# 直す前の実装(rev-parse --verify)でも解決できる形だけが検査になる(初期コミット1つの fixture では
# ~1・:README.md・@{0} は直す前でも rc 3 になり何も守らない)ので、^0・^{commit}・^{tree} を使い、
# ~1 と :README.md は2コミット目と README を push してから検査する。
( cd "$_bb_dev/work" && echo r > README.md && gitc add README.md && gitc commit -q -m second \
  && git push -q origin develop ) >/dev/null 2>&1
for _bb_rev in 'develop^0' 'develop^{commit}' 'develop^{tree}' 'develop~1' 'develop:README.md'; do
  _bb_run --declared "$_bb_rev" "$_bb_dev/work"
  exit_is "--declared '$_bb_rev'(revision 構文): rc 3" 3 "$_bb_rc"
  out_is_empty "--declared '$_bb_rev': stdout は空" "$_bb_out"
done
_bb_run --declared
exit_is "--declared に名前が無い: rc 64(引数の誤り)" 64 "$_bb_rc"
_bb_run --declared "" "$_bb_dev/work"
exit_is "--declared \"\"(空): rc 64(黙って origin/HEAD にしない)" 64 "$_bb_rc"
_bb_run --declared= "$_bb_dev/work"
exit_is "--declared=(空): rc 64" 64 "$_bb_rc"
_bb_run "$_bb_dev/work" "$_bb_dev/work"
exit_is "位置引数が2つ: rc 64(後勝ちで黙らない)" 64 "$_bb_rc"

_bb_nohead="$(mktemp -d)"
mk_bare_remote_clone "$_bb_nohead" --default main --no-origin-head
_bb_run "$_bb_nohead/work"
exit_is "origin/HEAD が無い: rc 1" 1 "$_bb_rc"
out_is_empty "origin/HEAD が無い: stdout は空" "$_bb_out"
out_has "origin/HEAD が無い: 投入時に明示する案内" "投入時に明示する" "$_bb_err"
out_has "origin/HEAD が無い: profile に書く案内" "base ブランチ" "$_bb_err"
out_has "origin/HEAD が無い: git remote set-head origin --auto の案内" "git remote set-head origin --auto" "$_bb_err"
_bb_run --declared main "$_bb_nohead/work"
[ "$_bb_out" = "main" ] && ok "origin/HEAD が無くても --declared があれば決まる" || ng "origin/HEAD が無くても --declared があれば決まる(got: $_bb_out)"

_bb_nogit="$(mktemp -d)"
bash "$_bb_bin" "$_bb_nogit" >/dev/null 2>&1; _bb_rc=$?
exit_is "git の外: rc 2" 2 "$_bb_rc"

# --- `/` を含む既定ブランチ ---
_bb_rel="$(mktemp -d)"
mk_bare_remote_clone "$_bb_rel" --default release/x --branch x
_bb_out="$(bash "$_bb_bin" "$_bb_rel/work" 2>/dev/null)"
[ "$_bb_out" = "release/x" ] && ok "既定ブランチが release/x: release/x を返す(末尾の1要素だけにならない)" || ng "既定ブランチが release/x(got: $_bb_out)"

# --- スクリプトの既定値: doc-drift-check(引数なし) ---
# main が既定で develop が無い導入先。feat ブランチでコードだけ変更 → origin/main と比べて FINDINGS。
( cd "$_bb_main/work" && git checkout -q -b feat && mkdir -p src \
  && echo y > src/a.py && gitc add -A && gitc commit -qm code-only ) >/dev/null 2>&1
_bb_dd="$(cd "$_bb_main/work" && bash "$H/lib/doc-drift-check.sh" 2>&1)"; _bb_rc=$?
out_has "doc-drift-check(引数なし): origin/HEAD の指す main と比べて検知する" "FINDINGS" "$_bb_dd"
exit_is "doc-drift-check(引数なし): 終了コード 0" 0 "$_bb_rc"
( cd "$_bb_main/work" && mkdir -p .docs && echo d > .docs/a.md && gitc add -A && gitc commit -qm docs ) >/dev/null 2>&1
_bb_dd="$(cd "$_bb_main/work" && bash "$H/lib/doc-drift-check.sh" 2>&1)"
out_has "doc-drift-check(引数なし): 比較先は origin/main" "vs origin/main" "$_bb_dd"
_bb_dd2="$(cd "$_bb_main/work" && bash "$H/lib/doc-drift-check.sh" 2>&1)"
[ "$_bb_dd" = "$_bb_dd2" ] && ok "doc-drift-check(引数なし): 2回目の実行で同じ結果" || ng "doc-drift-check(引数なし): 2回目の実行で同じ結果"
_bb_dd="$(cd "$_bb_nohead/work" && bash "$H/lib/doc-drift-check.sh" 2>&1)"; _bb_rc=$?
out_has "doc-drift-check(引数なし・origin/HEAD 無し): RESULT: SKIP" "RESULT: SKIP" "$_bb_dd"
exit_is "doc-drift-check(引数なし・origin/HEAD 無し): 終了コード 0(Sensor)" 0 "$_bb_rc"
_bb_dd="$(cd "$_bb_nogit" && bash "$H/lib/doc-drift-check.sh" 2>&1)"; _bb_rc=$?
out_has "doc-drift-check(引数なし・git の外): RESULT: SKIP" "RESULT: SKIP" "$_bb_dd"
exit_is "doc-drift-check(引数なし・git の外): 終了コード 0" 0 "$_bb_rc"
_bb_dd_body="$(cat "$H/lib/doc-drift-check.sh")"
out_hasnt "doc-drift-check.sh: 固定の候補リスト(origin/develop …)を持たない" "origin/develop" "$_bb_dd_body"
out_has "doc-drift-check.sh: base-branch.sh を単一ホームとして使う" "base-branch.sh" "$_bb_dd_body"

# --- スクリプトの既定値: epic-cleanup(base 省略) ---
_bb_ec_body="$(cat "$H/lib/epic-cleanup.sh")"
out_hasnt "epic-cleanup.sh: base_branch の既定値に develop を直書きしない" ':-develop' "$_bb_ec_body"
out_has "epic-cleanup.sh: base-branch.sh を単一ホームとして使う" "base-branch.sh" "$_bb_ec_body"
_bb_mk_epic() {  # <work-dir>: epic/demo(origin にも push する)に merge 済みの sub ブランチを作り epic/demo に居る
  ( cd "$1" && gitc checkout -q -b epic/demo \
    && gitc checkout -q -b epic-sub-merged && echo y > f.txt && gitc add -A && gitc commit -qm sub \
    && gitc checkout -q epic/demo && gitc merge -q --no-ff epic-sub-merged -m merge-sub \
    && git push -q origin epic/demo ) >/dev/null 2>&1
}
_bb_ec="$(mktemp -d)"
mk_bare_remote_clone "$_bb_ec" --default main
_bb_mk_epic "$_bb_ec/work"
# ローカルに main が無い(origin/main だけ)導入先でも develop を前提にせず動く
git -C "$_bb_ec/work" branch -D main >/dev/null 2>&1
_bb_out="$(cd "$_bb_ec/work" && bash "$H/lib/epic-cleanup.sh" epic/demo 2>&1)"; _bb_rc=$?
out_has "epic-cleanup(base 省略): origin/HEAD の main を基準に merge 済みの sub を消す" "deleted: epic-sub-merged" "$_bb_out"
out_has "epic-cleanup(base 省略): 解決の出どころを出す" "source: origin/HEAD" "$_bb_out"
# 決まらない: 何も消さずに非ゼロ
_bb_ecn="$(mktemp -d)"
mk_bare_remote_clone "$_bb_ecn" --default main --no-origin-head
_bb_mk_epic "$_bb_ecn/work"
_bb_out="$(cd "$_bb_ecn/work" && bash "$H/lib/epic-cleanup.sh" epic/demo 2>&1)"; _bb_rc=$?
if [ "$_bb_rc" -ne 0 ]; then ok "epic-cleanup(base 省略・origin/HEAD 無し): 非ゼロで終わる"; else ng "epic-cleanup(base 省略・origin/HEAD 無し): 非ゼロで終わる(rc=$_bb_rc)"; fi
out_hasnt "epic-cleanup(base 省略・origin/HEAD 無し): 何も消さない(deleted 行が無い)" "deleted:" "$_bb_out"
_bb_br="$(git -C "$_bb_ecn/work" branch --format='%(refname:short)')"
out_has "epic-cleanup(base 省略・origin/HEAD 無し): sub ブランチが残る" "epic-sub-merged" "$_bb_br"
_bb_out2="$(cd "$_bb_ecn/work" && bash "$H/lib/epic-cleanup.sh" epic/demo 2>&1)"
[ "$_bb_out" = "$_bb_out2" ] && ok "epic-cleanup(base 省略・origin/HEAD 無し): 2回目の実行で同じ結果" || ng "epic-cleanup(base 省略・origin/HEAD 無し): 2回目の実行で同じ結果"

# --- guard (J): origin/HEAD の読み取りが lib の単一ホームにある ---
_bb_guard_body="$(cat "$H/hooks/guard.sh")"
out_has "guard.sh: base-branch.sh を必須の lib として読む" "lib/base-branch.sh" "$_bb_guard_body"
out_has "guard.sh (J): bb_origin_head で既定ブランチを読む" "bb_origin_head" "$_bb_guard_body"
out_hasnt "guard.sh (J): origin/HEAD を直接読まない(symbolic-ref の直読みが無い)" "symbolic-ref refs/remotes/origin/HEAD" "$_bb_guard_body"

# 決定が変える振る舞い: 既定ブランチが release/x の clone では release/x が保護され、x は保護されない。
json_cmd_cwd "git commit -m x" "$_bb_rel/work" | bash "$H/hooks/guard.sh" >/dev/null 2>&1
exit_is "guard (J): 既定ブランチ release/x 上の git commit は block する" 2 "$?"
( cd "$_bb_rel/work" && git checkout -q -b x origin/x ) >/dev/null 2>&1
json_cmd_cwd "git commit -m x" "$_bb_rel/work" | bash "$H/hooks/guard.sh" >/dev/null 2>&1
exit_is "guard (J): x という名前の別のブランチは block しない(末尾の1要素だけを見ない)" 0 "$?"
( cd "$_bb_rel/work" && git checkout -q release/x ) >/dev/null 2>&1
# --git-dir 経路(bb_origin_head の第2引数): cwd は無関係なリポジトリ/ディレクトリで、
# コマンドラインの --git-dir または GIT_DIR 環境変数で release/x の clone を指す commit も止める。
_bb_gd="$_bb_rel/work/.git"
json_cmd_cwd "git --git-dir=$_bb_gd commit -m x" "$_bb_nogit" | bash "$H/hooks/guard.sh" >/dev/null 2>&1
exit_is "guard (J): cwd が無関係でも --git-dir で release/x の clone を指す commit は block する" 2 "$?"
json_cmd_cwd "GIT_DIR=$_bb_gd git commit -m x" "$_bb_nogit" | bash "$H/hooks/guard.sh" >/dev/null 2>&1
exit_is "guard (J): GIT_DIR 環境変数で release/x の clone を指す commit は block する" 2 "$?"
( cd "$_bb_rel/work" && git checkout -q x ) >/dev/null 2>&1
json_cmd_cwd "git --git-dir=$_bb_gd commit -m x" "$_bb_nogit" | bash "$H/hooks/guard.sh" >/dev/null 2>&1
exit_is "guard (J): --git-dir 経路でも x ブランチ上の commit は block しない" 0 "$?"
( cd "$_bb_rel/work" && git checkout -q release/x ) >/dev/null 2>&1
# 置き換え前の実装(symbolic-ref の結果の末尾の1要素だけを見る)では止まらないことを、写しの上で確かめる。
# 写しの guard.sh の (J) の1箇所だけを置き換え前の形へ戻す(置き換えが効かなかったら検査自体を失敗させる)。
_bb_old="$(mktemp -d)"
cp -R "$H/hooks" "$_bb_old/hooks"; cp -R "$H/lib" "$_bb_old/lib"
python3 - "$_bb_old/hooks/guard.sh" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
new = '''_bpc_default_branch="$(bb_origin_head "$_bpc_dir" "${_bpc_gitdir_eff:-}")" || true'''
old = '''_bpc_default_ref="$(git -C "$_bpc_dir" "${_bpc_gitdiropt[@]+"${_bpc_gitdiropt[@]}"}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" || true
          _bpc_default_branch="${_bpc_default_ref##*/}"'''
if s.count(new) != 1:
    sys.exit(3)
open(p, "w").write(s.replace(new, old))
PYEOF
_bb_py_rc=$?
exit_is "置き換え前の実装の写しを作れた(guard.sh の (J) の置き換え箇所が1つだけ見つかる)" 0 "$_bb_py_rc"
json_cmd_cwd "git commit -m x" "$_bb_rel/work" | bash "$_bb_old/hooks/guard.sh" >/dev/null 2>&1
exit_is "置き換え前の実装(末尾の1要素だけ)では release/x 上の commit が止まらない" 0 "$?"
rm -rf "$_bb_old"

rm -rf "$_bb_main" "$_bb_dev" "$_bb_nohead" "$_bb_nogit" "$_bb_rel" "$_bb_ec" "$_bb_ecn"
