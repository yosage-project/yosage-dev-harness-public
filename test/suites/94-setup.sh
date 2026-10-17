echo "== setup.sh / bin/{setup,update,status,ensure-worktrees-ignore}: 導入先に守りに必要な最小のものだけを書き込む =="

# 本スイート専用の後始末漏れ検知: $ROOT(このリポジトリ自身)に対して setup/update/status を
# 直接実行したわけではないが、実行ファイル内の実装が cwd 解決を誤ると $ROOT(ないし親)へ書き込みうる
# (dogfood worktree から ydh_repo_root で誤って上位チェックアウトへ書き込んだ実例があるための回帰
# 防止)。スイート開始時と終了時で $ROOT の git 状態が変わっていないことを確かめる。
_s94_initial="$(cd "$ROOT" && git status --porcelain 2>/dev/null)"

# --- 0. gitignore-lines.txt と 35-knowledge.sh(並行して同じ導入先レイアウトへ依存する別スイート)
#        が前提にする行が食い違っていないこと(35-knowledge.sh 自体は編集しない・読むだけ) ---
_s94_gi_check="$(python3 - "$ROOT/test/suites/35-knowledge.sh" "$H/config/gitignore-lines.txt" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
canon = set(l.strip() for l in open(sys.argv[2], encoding="utf-8") if l.strip())
pattern = re.compile(r"printf\s+'([^']*)'\s*\n?\s*>\s*\"\$[A-Za-z0-9_]+/\.claude/\.gitignore\"", re.S)
missing = []
found_any = False
for m in pattern.finditer(src):
    found_any = True
    content = m.group(1).replace("\\n", "\n")
    for raw in content.split("\n"):
        raw = raw.strip()
        if not raw:
            continue
        cand = "/.claude/" + raw
        if cand not in canon:
            missing.append(cand)
if not found_any:
    print("NONE_FOUND")
elif missing:
    print("MISSING:" + ",".join(sorted(set(missing))))
else:
    print("OK")
PY
)"
out_has "gitignore-lines.txt: 35-knowledge.sh の fixture が前提にする行と食い違わない" "OK" "$_s94_gi_check"

# --- 1. ydh_gitignore_plan / ydh_gitignore_apply(関数単体) ---

s94_g1="$(mktemp -d)"
( cd "$s94_g1" && git init -q )
bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2" >/dev/null' _ "$ROOT" "$s94_g1"
s94_g1_lines="$(wc -l < "$s94_g1/.gitignore" | tr -d ' ')"
out_has "1: .gitignore が無い→8行すべて追加(1行目)" "/.claude/yosage-dev-harness.local.json" "$(cat "$s94_g1/.gitignore")"
if [ "$s94_g1_lines" = "8" ]; then ok "1: .gitignore が無い→ちょうど8行"; else ng "1: .gitignore が無い→ちょうど8行 (実測: $s94_g1_lines)"; fi

s94_g2="$(mktemp -d)"
( cd "$s94_g2" && git init -q )
printf '/.claude/\n' > "$s94_g2/.gitignore"
s94_g2_out="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g2")"
out_is_empty "2: 既に /.claude/ を持つ .gitignore→何も足さない(出力なし)" "$s94_g2_out"
s94_g2_lines="$(wc -l < "$s94_g2/.gitignore" | tr -d ' ')"
if [ "$s94_g2_lines" = "1" ]; then ok "2: 既に /.claude/ を持つ .gitignore→中身は変わらず1行"; else ng "2: 既に /.claude/ を持つ .gitignore→中身は変わらず1行 (実測: $s94_g2_lines)"; fi

s94_g3="$(mktemp -d)"
( cd "$s94_g3" && git init -q )
printf '/.claude/tmp/\n' > "$s94_g3/.gitignore"
bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2" >/dev/null' _ "$ROOT" "$s94_g3"
s94_g3_lines="$(wc -l < "$s94_g3/.gitignore" | tr -d ' ')"
if [ "$s94_g3_lines" = "8" ]; then ok "3: /.claude/tmp/ だけ→残り7行を足して計8行"; else ng "3: /.claude/tmp/ だけ→残り7行を足して計8行 (実測: $s94_g3_lines)"; fi
out_has "3: 既存の /.claude/tmp/ は重複しない(1回だけ出現)" "/.claude/tmp/" "$(cat "$s94_g3/.gitignore")"
s94_g3_tmp_count="$(grep -c '^/\.claude/tmp/$' "$s94_g3/.gitignore")"
if [ "$s94_g3_tmp_count" = "1" ]; then ok "3: /.claude/tmp/ の出現回数は1"; else ng "3: /.claude/tmp/ の出現回数は1 (実測: $s94_g3_tmp_count)"; fi

# 個人のグローバル除外に頼らない: HOME を一時化し、(a) ~/.gitconfig の core.excludesFile と
# (b) XDG 既定 ~/.config/git/ignore、いずれも -c core.excludesFile= で無効化されることを確かめる。
s94_home_a="$(mktemp -d)"
printf '%s\n' '/.claude/yosage-dev-harness.local.json
/.claude/knowledge/global/
/.claude/knowledge/.global.tmp*
/.claude/knowledge/.global.old/
/.claude/knowledge/.global-sync
/.claude/knowledge/.sync-log
/.claude/review/criteria.md
/.claude/tmp/' > "$s94_home_a/globalignore"
printf '[core]\n\texcludesFile = %s/globalignore\n' "$s94_home_a" > "$s94_home_a/.gitconfig"
s94_g4="$(mktemp -d)"
( cd "$s94_g4" && git init -q )
s94_g4_out="$(HOME="$s94_home_a" bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g4")"
s94_g4_added="$(printf '%s\n' "$s94_g4_out" | grep -c '^added\t')"
if [ "$s94_g4_added" = "8" ]; then ok "4a: ~/.gitconfig の core.excludesFile に頼らず全8行を足す"; else ng "4a: ~/.gitconfig の core.excludesFile に頼らず全8行を足す (実測: $s94_g4_added)"; fi

s94_home_b="$(mktemp -d)"
mkdir -p "$s94_home_b/.config/git"
printf '%s\n' '/.claude/yosage-dev-harness.local.json
/.claude/knowledge/global/
/.claude/knowledge/.global.tmp*
/.claude/knowledge/.global.old/
/.claude/knowledge/.global-sync
/.claude/knowledge/.sync-log
/.claude/review/criteria.md
/.claude/tmp/' > "$s94_home_b/.config/git/ignore"
s94_g5="$(mktemp -d)"
( cd "$s94_g5" && git init -q )
s94_g5_out="$(HOME="$s94_home_b" XDG_CONFIG_HOME= bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g5")"
s94_g5_added="$(printf '%s\n' "$s94_g5_out" | grep -c '^added\t')"
if [ "$s94_g5_added" = "8" ]; then ok "4b: XDG 既定 ~/.config/git/ignore に頼らず全8行を足す"; else ng "4b: XDG 既定 ~/.config/git/ignore に頼らず全8行を足す (実測: $s94_g5_added)"; fi

# .git/info/exclude だけに書かれていても、missing として扱い .gitignore へ足す。
s94_g6="$(mktemp -d)"
( cd "$s94_g6" && git init -q )
printf '/.claude/tmp/\n' >> "$s94_g6/.git/info/exclude"
s94_g6_out="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g6")"
out_has "5: .git/info/exclude だけの行は missing として足す" "added	/.claude/tmp/" "$s94_g6_out"

# 打ち消しの行: 他の行は足すが、打ち消された行は足さず report する。
s94_g7="$(mktemp -d)"
( cd "$s94_g7" && git init -q )
printf '!/.claude/tmp/\n' > "$s94_g7/.gitignore"
s94_g7_out="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g7")"
out_has "6: 打ち消しの行は negated として報告する" "negated	/.claude/tmp/" "$s94_g7_out"
out_hasnt "6: 打ち消しの行は .gitignore へ追加しない(added に出ない)" "added	/.claude/tmp/" "$s94_g7_out"
s94_g7_tmp_count="$(grep -c '/\.claude/tmp/$' "$s94_g7/.gitignore")"
if [ "$s94_g7_tmp_count" = "1" ]; then ok "6: /.claude/tmp/ は打ち消し行のまま(足されていない)"; else ng "6: /.claude/tmp/ は打ち消し行のまま (実測件数: $s94_g7_tmp_count)"; fi
s94_g7_other_added="$(printf '%s\n' "$s94_g7_out" | grep -c '^added\t')"
if [ "$s94_g7_other_added" = "7" ]; then ok "6: 打ち消し行以外の7行は足す"; else ng "6: 打ち消し行以外の7行は足す (実測: $s94_g7_other_added)"; fi

# 対象の行が既にあり、その後に同じ行を打ち消す行がある場合(一次レビュー指摘): ファイル対象の
# エントリでは git check-ignore -v が最後に一致した打ち消しパターンを表示しつつ exit 0 を返す
# (-v 無しでは exit 1)。「出力が空でない→covered」だけで判定すると、この打ち消し済みの状態を
# 誤って足りていると判定してしまう(直す前のコードではこの検査が赤くなることを実際に確認済み)。
s94_g7b="$(mktemp -d)"
( cd "$s94_g7b" && git init -q )
printf '/.claude/yosage-dev-harness.local.json\n!/.claude/yosage-dev-harness.local.json\n' > "$s94_g7b/.gitignore"
s94_g7b_plan="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_plan "$2"' _ "$ROOT" "$s94_g7b")"
out_has "6b: 対象の行の後に打ち消し行がある(ファイル対象)→ covered ではなく negated と判定する" "negated	/.claude/yosage-dev-harness.local.json" "$s94_g7b_plan"
out_hasnt "6b: 対象の行の後に打ち消し行があるのに covered と誤判定しない" "covered	/.claude/yosage-dev-harness.local.json" "$s94_g7b_plan"
s94_g7b_out="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g7b")"
out_has "6b: 対象の行の後に打ち消し行がある場合も apply は negated として報告する(書き込まない)" "negated	/.claude/yosage-dev-harness.local.json" "$s94_g7b_out"
s94_g7b_target_count="$(grep -c '^/\.claude/yosage-dev-harness\.local\.json$' "$s94_g7b/.gitignore")"
if [ "$s94_g7b_target_count" = "1" ]; then ok "6b: 対象の行は重複して追加されない(元の1行のまま)"; else ng "6b: 対象の行は重複して追加されない (実測: $s94_g7b_target_count)"; fi

# 実在しないディレクトリ/ファイルでも判定できる(check-ignore はパスの実在を要求しない)。
s94_g8="$(mktemp -d)"
( cd "$s94_g8" && git init -q )
bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2" >/dev/null' _ "$ROOT" "$s94_g8"
s94_g8_out2="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g8")"
out_is_empty "7: 対象が実在しなくても2回目は何も足さない" "$s94_g8_out2"

# 追跡済みのファイルがあっても2回目に同じ行を足さない。
s94_g9="$(mktemp -d)"
( cd "$s94_g9" && git init -q )
mkdir -p "$s94_g9/.claude"
echo x > "$s94_g9/.claude/yosage-dev-harness.local.json"
( cd "$s94_g9" && gitc add -f .claude/yosage-dev-harness.local.json )
bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2" >/dev/null' _ "$ROOT" "$s94_g9"
s94_g9_out2="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2"' _ "$ROOT" "$s94_g9")"
out_is_empty "8: 追跡済みファイルがあっても2回目は何も足さない" "$s94_g9_out2"

# CRLF・末尾改行なしの維持
s94_g10="$(mktemp -d)"
printf '/.claude/tmp/\r\n' > "$s94_g10/.gitignore"
bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2" >/dev/null' _ "$ROOT" "$s94_g10"
if LC_ALL=C grep -q $'\r' "$s94_g10/.gitignore"; then ok "9a: CRLF の .gitignore に足した行も CRLF"; else ng "9a: CRLF の .gitignore に足した行も CRLF"; fi
out_hasnt "9a: CRLF が崩れて \\r が消えていない行が無い(足した行の末尾は全て \\r\\n)" $'.claude/knowledge/global/\n' "$(cat "$s94_g10/.gitignore")"

s94_g11="$(mktemp -d)"
printf '/.claude/tmp/' > "$s94_g11/.gitignore"
bash -c '. "$1/harness/lib/setup.sh"; ydh_gitignore_apply "$2" >/dev/null' _ "$ROOT" "$s94_g11"
out_hasnt "9b: 末尾改行が無い既存行と足した行が連結されない" "/.claude/tmp//.claude/" "$(cat "$s94_g11/.gitignore")"
out_has "9b: 末尾改行が無くても既存の最終行はそのまま残る" "/.claude/tmp/" "$(cat "$s94_g11/.gitignore")"

# --- 2. .claude/worktrees/.gitignore(ydh_worktrees_ignore_ensure) ---

s94_w1="$(mktemp -d)"
bash -c '. "$1/harness/lib/setup.sh"; ydh_worktrees_ignore_ensure "$2" >/dev/null' _ "$ROOT" "$s94_w1"
out_has "10a: 無い→* だけの内容で作成される" "*" "$(cat "$s94_w1/.claude/worktrees/.gitignore" 2>/dev/null)"

s94_w2="$(mktemp -d)"
mkdir -p "$s94_w2/.claude/worktrees"
printf '*\n' > "$s94_w2/.claude/worktrees/.gitignore"
s94_w2_mtime_before="$(stat -f %m "$s94_w2/.claude/worktrees/.gitignore" 2>/dev/null || stat -c %Y "$s94_w2/.claude/worktrees/.gitignore")"
sleep 1
bash -c '. "$1/harness/lib/setup.sh"; ydh_worktrees_ignore_ensure "$2" >/dev/null' _ "$ROOT" "$s94_w2"
s94_w2_mtime_after="$(stat -f %m "$s94_w2/.claude/worktrees/.gitignore" 2>/dev/null || stat -c %Y "$s94_w2/.claude/worktrees/.gitignore")"
if [ "$s94_w2_mtime_before" = "$s94_w2_mtime_after" ]; then ok "10b: 中身が * → 触らない(更新時刻が変わらない)"; else ng "10b: 中身が * → 触らない(更新時刻が変わらない)"; fi

s94_w3="$(mktemp -d)"
( cd "$s94_w3" && git init -q )
mkdir -p "$s94_w3/.claude/worktrees"
printf 'a\nb\n' > "$s94_w3/.claude/worktrees/.gitignore"
bash -c '. "$1/harness/lib/setup.sh"; ydh_worktrees_ignore_ensure "$2" >/dev/null' _ "$ROOT" "$s94_w3"
out_has "10c: 追跡されていない複数行の中身→* に書き換わる" "*" "$(cat "$s94_w3/.claude/worktrees/.gitignore")"

s94_w4="$(mktemp -d)"
( cd "$s94_w4" && git init -q )
mkdir -p "$s94_w4/.claude/worktrees"
printf 'a\nb\n' > "$s94_w4/.claude/worktrees/.gitignore"
( cd "$s94_w4" && gitc add -f .claude/worktrees/.gitignore )
s94_w4_out="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_worktrees_ignore_ensure "$2"' _ "$ROOT" "$s94_w4")"
out_has "10d: 追跡されている複数行の中身→書き換わらず報告が出る" "tracked" "$s94_w4_out"
out_hasnt "10d: 追跡されている .gitignore の中身は書き換わらない" "*" "$(cat "$s94_w4/.claude/worktrees/.gitignore")"

# workspace: true で直下メンバー2つそれぞれに作られる(bin/yosage-dev-harness-setup 経由)
s94_wm="$(mktemp -d)"
( cd "$s94_wm" && git init -q )
mkdir -p "$s94_wm/memberA" "$s94_wm/memberB"
( cd "$s94_wm/memberA" && git init -q )
( cd "$s94_wm/memberB" && git init -q )
( cd "$s94_wm" && bash "$H/bin/yosage-dev-harness-setup" --workspace true >/dev/null )
out_has "10e: workspace:true → memberA にも .claude/worktrees/.gitignore が作られる" "*" "$(cat "$s94_wm/memberA/.claude/worktrees/.gitignore" 2>/dev/null)"
out_has "10e: workspace:true → memberB にも .claude/worktrees/.gitignore が作られる" "*" "$(cat "$s94_wm/memberB/.claude/worktrees/.gitignore" 2>/dev/null)"

# --- 3. 設定ファイル(bin/yosage-dev-harness-setup・-update 経由) ---

s94_c1="$(mktemp -d)"
( cd "$s94_c1" && git init -q )
( cd "$s94_c1" && bash "$H/bin/yosage-dev-harness-setup" --workspace true >/dev/null )
s94_c1_cfg="$(cat "$s94_c1/.claude/yosage-dev-harness.local.json")"
out_has "11a: setup で \$schema が書かれる" '"$schema"' "$s94_c1_cfg"
out_has "11a: setup で workspace:true が書かれる" '"workspace": true' "$s94_c1_cfg"
s94_c1_keys="$(python3 -c "import json; print(sorted(json.load(open('$s94_c1/.claude/yosage-dev-harness.local.json')).keys()))")"
if [ "$s94_c1_keys" = "['\$schema', 'workspace']" ]; then ok "11a: setup が書く項目は \$schema と workspace だけ"; else ng "11a: setup が書く項目は \$schema と workspace だけ (実測: $s94_c1_keys)"; fi

s94_c1_before="$(cat "$s94_c1/.claude/yosage-dev-harness.local.json")"
( cd "$s94_c1" && bash "$H/bin/yosage-dev-harness-update" >/dev/null )
( cd "$s94_c1" && bash "$H/bin/yosage-dev-harness-update" >/dev/null )
s94_c1_after="$(cat "$s94_c1/.claude/yosage-dev-harness.local.json")"
if [ "$s94_c1_before" = "$s94_c1_after" ]; then ok "11b: update を2回実行しても設定ファイルの中身は変わらない"; else ng "11b: update を2回実行しても設定ファイルの中身は変わらない"; fi

# スキーマに無い項目 foo は setup/update/status の出力に一覧で出て、ファイルからは消えない。
s94_c2="$(mktemp -d)"
( cd "$s94_c2" && git init -q )
mkdir -p "$s94_c2/.claude"
printf '{"$schema": "https://example.test/s.json", "workspace": false, "foo": 1}\n' > "$s94_c2/.claude/yosage-dev-harness.local.json"
s94_c2_setup="$( cd "$s94_c2" && bash "$H/bin/yosage-dev-harness-setup" --workspace false )"
out_has "12a: setup の出力にスキーマ無し項目 foo が一覧で出る" "foo" "$s94_c2_setup"
s94_c2_update="$( cd "$s94_c2" && bash "$H/bin/yosage-dev-harness-update" )"
out_has "12b: update の出力にスキーマ無し項目 foo が一覧で出る" "foo" "$s94_c2_update"
s94_c2_status="$( cd "$s94_c2" && bash "$H/bin/yosage-dev-harness-status" )"
out_has "12c: status の出力にスキーマ無し項目 foo が一覧で出る" "foo" "$s94_c2_status"
out_has "12d: foo はファイルから消えない" '"foo"' "$(cat "$s94_c2/.claude/yosage-dev-harness.local.json")"

# --- 4. 状態表示(bin/yosage-dev-harness-status 経由) ---

s94_st1="$(mktemp -d)"
( cd "$s94_st1" && git init -q )
mkdir -p "$s94_st1/.claude"
printf '{"notify": {"url": "https://hooks.example.test/T0P-SECRET-URL"}}\n' > "$s94_st1/.claude/yosage-dev-harness.local.json"
s94_st1_out="$( cd "$s94_st1" && bash "$H/bin/yosage-dev-harness-status" )"
out_has "13a: notify.url に値がある→「設定あり」と出る" "設定あり" "$s94_st1_out"
out_hasnt "13a: notify.url の値そのものはどこにも出ない" "T0P-SECRET-URL" "$s94_st1_out"

s94_st2="$(mktemp -d)"
( cd "$s94_st2" && git init -q )
s94_st2_out="$( cd "$s94_st2" && bash "$H/bin/yosage-dev-harness-status" )"
out_has "13b: notify.url が未設定→「設定なし」と出る" "設定なし" "$s94_st2_out"

# --- 5. 推奨設定の見本(ydh_recommended_settings_render / bin/yosage-dev-harness-update 経由) ---

s94_rs1="$(mktemp -d)"
( cd "$s94_rs1" && git init -q )
( cd "$s94_rs1" && bash "$H/bin/yosage-dev-harness-setup" --workspace false >/dev/null )
s94_rs1_deny_count="$(python3 -c "import json; print(len(json.load(open('$s94_rs1/.claude/yosage-dev-harness.recommended-settings.json'))['permissions']['deny']))")"
if [ "$s94_rs1_deny_count" = "41" ]; then ok "14a: 推奨設定の見本の permissions.deny はちょうど41件"; else ng "14a: 推奨設定の見本の permissions.deny はちょうど41件 (実測: $s94_rs1_deny_count)"; fi
s94_rs1_has_allow="$(python3 -c "import json; print('allow' in json.load(open('$s94_rs1/.claude/yosage-dev-harness.recommended-settings.json'))['permissions'])")"
if [ "$s94_rs1_has_allow" = "False" ]; then ok "14b: 推奨設定の見本に allow が無い"; else ng "14b: 推奨設定の見本に allow が無い"; fi

# 38件の集合が sf_deny_rules の出力(Read(<glob>) 形式)と一致する。
s94_rs1_secret_set="$(python3 -c "
import json
d = json.load(open('$s94_rs1/.claude/yosage-dev-harness.recommended-settings.json'))
extra = {'Bash(gh pr merge:*)', 'Bash(git commit -a:*)', 'Bash(git commit --all:*)'}
secrets = sorted(x for x in d['permissions']['deny'] if x not in extra)
print('\n'.join(secrets))
")"
s94_sf_rules="$(bash -c '. "$1/harness/lib/secret-patterns.sh"; sf_deny_rules' _ "$ROOT" | sort)"
if [ "$s94_rs1_secret_set" = "$s94_sf_rules" ]; then ok "14c: 秘密ファイル38件の集合は sf_deny_rules の出力と一致する"; else ng "14c: 秘密ファイル38件の集合は sf_deny_rules の出力と一致する"; fi

# ガードの一覧を変えると見本も変わる(一時コピーで1件足して確かめる)。
s94_sp_src="$(_src_copy)"
python3 - "$s94_sp_src/harness/lib/secret-patterns.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('  "**/secrets/**"\n)', '  "**/secrets/**"\n  "**/*.s94test"\n)')
open(p, "w", encoding="utf-8").write(s)
PY
s94_sp_deny_after="$(bash -c '. "$1/harness/lib/setup.sh"; ydh_recommended_settings_render' _ "$s94_sp_src" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['permissions']['deny']))")"
if [ "$s94_sp_deny_after" = "42" ]; then ok "14d: 秘密ファイル一覧に1件足すと見本の deny も1件増える(42件)"; else ng "14d: 秘密ファイル一覧に1件足すと見本の deny も1件増える(42件) (実測: $s94_sp_deny_after)"; fi
rm -rf "$s94_sp_src"

# 利用者が書き換えても update で元に戻る(丸ごと置き換え)。
printf '{"permissions": {"deny": ["Bash(rm:*)"]}}\n' > "$s94_rs1/.claude/yosage-dev-harness.recommended-settings.json"
( cd "$s94_rs1" && bash "$H/bin/yosage-dev-harness-update" >/dev/null )
s94_rs1_restored_count="$(python3 -c "import json; print(len(json.load(open('$s94_rs1/.claude/yosage-dev-harness.recommended-settings.json'))['permissions']['deny']))")"
if [ "$s94_rs1_restored_count" = "41" ]; then ok "14e: 利用者の書き換えは update で元に戻る(丸ごと置き換え)"; else ng "14e: 利用者の書き換えは update で元に戻る(丸ごと置き換え) (実測: $s94_rs1_restored_count)"; fi

# --- 6. jq も python3 も無い PATH → setup は exit 3・何も書き込まない ---

s94_nojq="$(mktemp -d)"
s94_realpy_bin_dir="$(mktemp -d)"
for t in bash cat dirname basename sed grep git od tail mktemp mkdir mv rm printf wc stat sleep; do
  p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$s94_realpy_bin_dir/$t"
done
s94_nojq_target="$(mktemp -d)"
( cd "$s94_nojq_target" && git init -q )
s94_nojq_out="$(PATH="$s94_realpy_bin_dir" bash -c 'cd "$1" && bash "$2/bin/yosage-dev-harness-setup" --workspace false' _ "$s94_nojq_target" "$H" 2>&1)"
s94_nojq_rc="$(PATH="$s94_realpy_bin_dir" bash -c 'cd "$1" && bash "$2/bin/yosage-dev-harness-setup" --workspace false >/dev/null 2>&1; echo $?' _ "$s94_nojq_target" "$H")"
if [ "$s94_nojq_rc" = "3" ]; then ok "15a: jq も python3 も無い PATH → setup は exit 3"; else ng "15a: jq も python3 も無い PATH → setup は exit 3 (実測: $s94_nojq_rc)"; fi
file_isnt "15b: jq/python3 が無いときは .gitignore を作らない" "$s94_nojq_target/.gitignore"
file_isnt "15b: jq/python3 が無いときは設定ファイルを作らない" "$s94_nojq_target/.claude/yosage-dev-harness.local.json"
rm -rf "$s94_realpy_bin_dir"

# --- 7. 壊れた JSON → setup/update は exit 4・何も書き込まない ---

s94_broken="$(mktemp -d)"
( cd "$s94_broken" && git init -q )
mkdir -p "$s94_broken/.claude"
printf '{broken' > "$s94_broken/.claude/yosage-dev-harness.local.json"
s94_broken_before="$(cat "$s94_broken/.claude/yosage-dev-harness.local.json")"
s94_broken_rc="$( cd "$s94_broken" && bash "$H/bin/yosage-dev-harness-setup" --workspace false >/dev/null 2>&1; echo $? )"
exit_is "16: 壊れた JSON → setup は exit 4" "4" "$s94_broken_rc"
s94_broken_after="$(cat "$s94_broken/.claude/yosage-dev-harness.local.json")"
if [ "$s94_broken_before" = "$s94_broken_after" ]; then ok "16: 壊れた JSON のときは設定ファイルに触らない"; else ng "16: 壊れた JSON のときは設定ファイルに触らない"; fi
file_isnt "16: 壊れた JSON のときは .gitignore も作らない" "$s94_broken/.gitignore"

# --- 8. git リポジトリの外 → exit 2(素の mktemp -d。OS の一時領域・どの git の管理下でもない) ---
# 事前に「本当に git の外か」を確かめてから動かす(参照: harness-dev の教訓。割り当て作業ツリー配下に
# ネストした未 git-init ディレクトリは「外」にならない事故があったため、ここでも同じ確認を機械的に行う)。
s94_outside="$(mktemp -d)"
if git -C "$s94_outside" rev-parse --path-format=absolute --git-common-dir >/dev/null 2>&1; then
  ng "17: git の外の fixture のはずが git 管理下にある(前提が崩れている・実行ファイルを動かさずスキップ)"
else
  s94_outside_rc="$( cd "$s94_outside" && bash "$H/bin/yosage-dev-harness-setup" --workspace false >/dev/null 2>&1; echo $? )"
  exit_is "17: git リポジトリの外 → setup は exit 2" "2" "$s94_outside_rc"
  file_isnt "17: git の外のときは何も作られない" "$s94_outside/.claude"
fi
rm -rf "$s94_outside"

# --- 9. ensure-worktrees-ignore(別リポジトリへの git worktree add 前に呼ぶ想定) ---

s94_ewi="$(mktemp -d)"
( cd "$s94_ewi" && git init -q )
s94_ewi_out="$(bash "$H/bin/yosage-dev-harness-ensure-worktrees-ignore" "$s94_ewi")"
out_has "18a: ensure-worktrees-ignore は対象を引数で受け取り作成する" "*" "$(cat "$s94_ewi/.claude/worktrees/.gitignore" 2>/dev/null)"
out_has "18a: ensure-worktrees-ignore は作成したことを報告する" "作成しました" "$s94_ewi_out"
s94_ewi_rc="$(bash "$H/bin/yosage-dev-harness-ensure-worktrees-ignore" >/dev/null 2>&1; echo $?)"
if [ "$s94_ewi_rc" != "0" ]; then ok "18b: 引数(対象リポジトリのルート)を渡さないと失敗する"; else ng "18b: 引数(対象リポジトリのルート)を渡さないと失敗する"; fi

# --- 10. 2回連続実行: setup・update それぞれ2回続けて、2回目は何も書かない ---

s94_idem="$(mktemp -d)"
( cd "$s94_idem" && git init -q -b main )
( cd "$s94_idem" && bash "$H/bin/yosage-dev-harness-setup" --workspace false >/dev/null )
( cd "$s94_idem" && gitc add -A && gitc commit -q -m "setup 初回" ) 2>/dev/null || true
s94_idem_status_before="$(cd "$s94_idem" && git status --porcelain 2>/dev/null)"
( cd "$s94_idem" && bash "$H/bin/yosage-dev-harness-update" >/dev/null )
( cd "$s94_idem" && bash "$H/bin/yosage-dev-harness-update" >/dev/null )
s94_idem_status_after="$(cd "$s94_idem" && git status --porcelain 2>/dev/null)"
if [ "$s94_idem_status_before" = "$s94_idem_status_after" ]; then ok "19: update を2回連続実行しても git status --porcelain が変わらない"; else ng "19: update を2回連続実行しても git status --porcelain が変わらない (before=[$s94_idem_status_before] after=[$s94_idem_status_after])"; fi

# --- 11. 共有ストアの案内: 知識の同期が無効なら出し、有効なら出さない(案内のみ・設定は書き換えない) ---

s94_kg="$(mktemp -d)"
( cd "$s94_kg" && git init -q -b main )
s94_kg_out="$(cd "$s94_kg" && bash "$H/bin/yosage-dev-harness-setup" --workspace false)"
out_has "21a: 知識の同期が無効(既定)→共有ストアの案内が出る" "yosage-dev-knowledge-template" "$s94_kg_out"
out_has "21a: 案内は設定ファイルを名指しする" ".claude/yosage-dev-harness.local.json" "$s94_kg_out"
out_has "21a: 案内は設定の項目名を示す" "knowledge.source" "$s94_kg_out"
out_has "21a: 案内は書き込まないと明示する" "setup は書き込みません" "$s94_kg_out"
# setup を一度流して落ち着いた状態を取り、案内が出る2回目の実行の前後で、導入先の中身(.git を除く全ファイル)が同一であること
s94_kg_snap() { ( cd "$s94_kg" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s\n' "$f"; cat "$f"; done ); }
( cd "$s94_kg" && bash "$H/bin/yosage-dev-harness-setup" >/dev/null )
s94_kg_before="$(s94_kg_snap)"
s94_kg_out_b="$(cd "$s94_kg" && bash "$H/bin/yosage-dev-harness-setup")"
s94_kg_after="$(s94_kg_snap)"
out_has "21b: 比較する実行でも案内が出ている" "yosage-dev-knowledge-template" "$s94_kg_out_b"
if [ "$s94_kg_before" = "$s94_kg_after" ]; then ok "21b: 案内を出す実行の前後で、導入先のファイル(設定ファイルを含む)は同一"; else ng "21b: 案内を出す実行の前後で、導入先のファイルが変わった"; fi
s94_kg_cfg="$(ls "$s94_kg"/.claude/*.local.json)"
python3 - "$s94_kg_cfg" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.setdefault("knowledge", {})["enabled"] = True
json.dump(d, open(p, "w"))
PY
s94_kg_out2="$(cd "$s94_kg" && bash "$H/bin/yosage-dev-harness-setup")"
out_hasnt "21c: 知識の同期が有効→共有ストアの案内は出ない" "yosage-dev-knowledge-template" "$s94_kg_out2"

# --- 後始末漏れ検知(本スイート専用): $ROOT(このリポジトリ自身)に新しいファイルができていない ---
_s94_final="$(cd "$ROOT" && git status --porcelain 2>/dev/null)"
if [ "$_s94_initial" = "$_s94_final" ]; then
  ok "20: 本スイートの実行中、\$ROOT(このリポジトリ自身)には何も書き込まれていない"
else
  ng "20: 本スイートの実行中、\$ROOT(このリポジトリ自身)には何も書き込まれていない (差分: $(_dirt_diff "$_s94_initial" "$_s94_final"))"
fi
