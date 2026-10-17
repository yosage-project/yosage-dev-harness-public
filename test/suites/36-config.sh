echo "== config.sh: ydh_config_get の解決順(ファイル無し→既定値・ファイルの値が既定値に勝つ・ネストしたキー・真偽値) =="
cft="$(mktemp -d)"; mkdir -p "$cft/.claude"
cf_out="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" workspace; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "ファイル無し: workspace は既定値 false" "false rc=0" "$cf_out"
cf_out2="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" knowledge.ref; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "ファイル無し: knowledge.ref はネストした既定値 main" "main rc=0" "$cf_out2"

printf '{ "workspace": true, "knowledge": { "enabled": true, "source": "https://example.test/store.git" } }\n' > "$cft/.claude/yosage-dev-harness.local.json"
cf_out3="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" workspace; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "ファイルの値: workspace はファイルの true が既定値 false に勝つ" "true rc=0" "$cf_out3"
cf_out4="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" knowledge.enabled; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "ネストしたキー: knowledge.enabled はファイルの true を返す" "true rc=0" "$cf_out4"
cf_out5="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" knowledge.ref; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "ファイルに無いネストしたキー: knowledge.ref は既定値 main へフォールバック" "main rc=0" "$cf_out5"
cf_out6="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" knowledge.source; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "ネストしたキー: knowledge.source はファイルの値を返す" "https://example.test/store.git rc=0" "$cf_out6"

# キーがファイルに存在し、値が明示的な空文字列の場合は既定値へフォールバックしない
# (「ファイルの値 > defaults.json の値」というヘッダの約束の回帰防止。一次レビュー指摘)。
printf '{ "knowledge": { "ref": "" } }\n' > "$cft/.claude/yosage-dev-harness.local.json"
cf_out7="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" knowledge.ref; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "明示的な空文字列: knowledge.ref は既定値(main)へフォールバックせず空を返す" " rc=0" "$cf_out7"
out_hasnt "明示的な空文字列: knowledge.ref に既定値 main が紛れ込まない" "main" "$cf_out7"

echo "== config.sh: 壊れた JSON は rc=4(jq経路・python3経路とも) =="
printf '{broken' > "$cft/.claude/yosage-dev-harness.local.json"
cf_broken_jq="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" workspace; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "壊れたJSON(jq経路): rc=4" " rc=4" "$cf_broken_jq"

cf_nojq="$(mktemp -d)"
realpy="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
for t in bash cat dirname basename sed; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$cf_nojq/$t"; done
[ -n "$realpy" ] && ln -sf "$realpy" "$cf_nojq/python3"
cf_broken_py="$(PATH="$cf_nojq" bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" workspace; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "壊れたJSON(python3経路): rc=4" " rc=4" "$cf_broken_py"

echo "== config.sh: jq 非在(python3 フォールバック)でも同じ結果になる =="
printf '{ "workspace": true, "knowledge": { "ref": "dev" } }\n' > "$cft/.claude/yosage-dev-harness.local.json"
cf_jq_result="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" knowledge.ref' _ "$ROOT" "$cft")"
cf_py_result="$(PATH="$cf_nojq" bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" knowledge.ref' _ "$ROOT" "$cft")"
if [ "$cf_jq_result" = "$cf_py_result" ] && [ "$cf_jq_result" = "dev" ]; then
  ok "jq経路とpython3経路が同じ結果(dev)を返す"
else
  ng "jq経路とpython3経路が同じ結果を返す (jq=$cf_jq_result python3=$cf_py_result)"
fi

echo "== config.sh: jq も python3 も無い場合は rc=3 =="
cf_nothing="$(mktemp -d)"
for t in bash cat dirname basename sed; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$cf_nothing/$t"; done
cf_rc3="$(PATH="$cf_nothing" bash -c '. "$1/harness/lib/config.sh"; ydh_config_get "$2" workspace; echo " rc=$?"' _ "$ROOT" "$cft")"
out_has "jq/python3 どちらも無い: rc=3" " rc=3" "$cf_rc3"
rm -rf "$cf_nothing" "$cf_nojq" "$cft"

echo "== config.sh: ydh_config_is_secret(スキーマの writeOnly:true をたどる) =="
cfs_secret="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_is_secret notify.url; echo $?' _ "$ROOT")"
out_has "notify.url は秘密(writeOnly:true) → 0" "0" "$cfs_secret"
cfs_nonsecret="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_is_secret notify.provider; echo $?' _ "$ROOT")"
out_has "notify.provider は秘密でない → 1" "1" "$cfs_nonsecret"
cfs_unknown="$(bash -c '. "$1/harness/lib/config.sh"; ydh_config_is_secret no.such.key; echo $?' _ "$ROOT")"
out_has "不明なキーは秘密でない扱い → 1" "1" "$cfs_unknown"

echo "== config/yosage-dev-harness.schema.json の default が config/defaults.json と全項目で一致する =="
_cf_schema_match="$(python3 -c "
import json
defaults = json.load(open('$H/config/defaults.json'))
schema = json.load(open('$H/config/yosage-dev-harness.schema.json'))

def walk(d, s, path):
    mismatches = []
    props = s.get('properties', {})
    for k, v in d.items():
        node = props.get(k)
        if node is None:
            mismatches.append(f'{path}{k}: schema に無い')
            continue
        if isinstance(v, dict):
            mismatches.extend(walk(v, node, path + k + '.'))
        else:
            if node.get('default') != v:
                mismatches.append(f'{path}{k}: default={node.get(\"default\")!r} != defaults.json={v!r}')
    return mismatches

ms = walk(defaults, schema, '')
if ms:
    print('MISMATCH: ' + '; '.join(ms))
else:
    print('MATCH')
" 2>&1)"
out_has "スキーマの default が defaults.json と全項目で一致する" "MATCH" "$_cf_schema_match"

echo "== config.sh: ydh_repo_root はサブディレクトリ・worktree からも元のチェックアウトのルートを返す・git の外では非ゼロ =="
# $ROOT/.claude/tmp は harness を自分自身へ install(dogfood)した場合にしか実在しない
# (このリポジトリの .claude/ は丸ごと gitignore・素の新規 clone には無い)。`test/` は
# 追跡対象で常に実在するため、他 suite と同じ `test/scratch.XXXXXXXX` テンプレートを使う
# (mktemp 自体の失敗も検知する。失敗した mktemp の空出力を変数に入れたまま `cd ""`
# (何もしない)経由で処理を進めると、この後の git init 等がリポジトリ直下に意図しない
# ディレクトリ(例: `repo/`)を作って残す一次レビュー指摘の回帰防止)。
crr_ws="$(mktemp -d "$ROOT/test/scratch.XXXXXXXX")" || crr_ws=""
if [ -z "$crr_ws" ]; then
  ng "ydh_repo_root(サブディレクトリ/worktree): mktemp -d に失敗したため検証をスキップ"
else
  ( cd "$crr_ws" && git init -q repo && cd repo && git commit -q --allow-empty -m init )
  mkdir -p "$crr_ws/repo/sub"
  crr_sub_out="$(cd "$crr_ws/repo/sub" && bash -c '. "$1/harness/lib/config.sh"; ydh_repo_root' _ "$ROOT")"
  out_has "サブディレクトリから: 元のチェックアウトのルートを返す" "$crr_ws/repo" "$crr_sub_out"
  ( cd "$crr_ws/repo" && git worktree add -q ../wt HEAD )
  crr_wt_out="$(cd "$crr_ws/wt" && bash -c '. "$1/harness/lib/config.sh"; ydh_repo_root' _ "$ROOT")"
  out_has "worktree の中から: 元のチェックアウトのルートを返す(作業ツリーではない)" "$crr_ws/repo" "$crr_wt_out"
  ( cd "$crr_ws/repo" && git worktree remove --force ../wt ) >/dev/null 2>&1
  rm -rf "$crr_ws"
fi
# git の外(GIT_CEILING_DIRECTORIES で上位の git リポジトリへの探索を止め、素の非git ディレクトリを再現する。
# この worktree 自体が git 管理下にあるため、素の mktemp -d だけでは「外」を作れない)。
crr_nogit="$(mktemp -d "$ROOT/test/scratch.XXXXXXXX")" || crr_nogit=""
if [ -z "$crr_nogit" ]; then
  ng "ydh_repo_root(git の外): mktemp -d に失敗したため検証をスキップ"
else
  crr_outside_rc="$(cd "$crr_nogit" && GIT_CEILING_DIRECTORIES="$(dirname "$crr_nogit")" bash -c '. "$1/harness/lib/config.sh"; ydh_repo_root >/dev/null 2>&1; echo $?' _ "$ROOT")"
  if [ "$crr_outside_rc" != "0" ]; then ok "git の外では非ゼロ終了"; else ng "git の外では非ゼロ終了 (got rc=$crr_outside_rc)"; fi
  rm -rf "$crr_nogit"
fi

echo "== config-get.sh: workspace は値を出し、notify.url は秘密として exit 5(値を出さない) =="
cg_proj="$(mktemp -d)"; mkdir -p "$cg_proj/.claude"
( cd "$cg_proj" && git init -q )
printf '{ "workspace": true, "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx" } }\n' > "$cg_proj/.claude/yosage-dev-harness.local.json"
cg_ws_out="$(cd "$cg_proj" && bash "$H/lib/config-get.sh" workspace)"
out_has "config-get.sh workspace: 値を出す" "true" "$cg_ws_out"
cg_url_out="$(cd "$cg_proj" && bash "$H/lib/config-get.sh" notify.url 2>/dev/null)"; cg_url_rc=$?
exit_is "config-get.sh notify.url: exit 5(秘密)" 5 "$cg_url_rc"
out_hasnt "config-get.sh notify.url: 値そのものを出力しない(値でgrepして0件)" "hooks.slack.com" "$cg_url_out"
if [ -z "$cg_url_out" ]; then ok "config-get.sh notify.url: 標準出力は空"; else ng "config-get.sh notify.url: 標準出力は空 (got: $cg_url_out)"; fi
rm -rf "$cg_proj"

echo "== config-get.sh: 引数無しは使い方を示して exit 2 =="
cg_noarg_rc="$(bash "$H/lib/config-get.sh" 2>/dev/null; echo $?)"
exit_is "config-get.sh 引数無し: exit 2" 2 "$cg_noarg_rc"
