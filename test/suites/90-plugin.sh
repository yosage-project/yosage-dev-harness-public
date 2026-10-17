# プラグインの約束事(marketplace.json・plugin.json・hooks.json)を、`claude` を起動せずに
# 静的に検査する(`claude plugin validate --strict` は実行に claude 本体が要るため別途手動実行で
# 確認する。ここは CI 相当の速い静的検査)。python3 で JSON を読む(この repo の他 suite も同じ流儀)。
#
# check1/check2 はどちらも negative control(壊れた fixture に対して実際に検査を再実行し、期待どおり
# 赤になること)を取るため、判定ロジックをシェル関数 `_p90_check_marketplace()` /
# `_p90_check_hooks_json()` として切り出し、実物と negative control fixture の両方に対して
# 同じ関数を呼ぶ(判定を2箇所に書かない)。

# --- check1: marketplace.json / plugin.json が JSON として正しく、決められた形になっている ---
# 出力の各行は "OK:<field>" または "FAIL:<field>:<詳細>"。呼び出し側は out_has/out_hasnt で
# 個々の行を検査する。
_p90_check_marketplace() {  # <marketplace.jsonのパス> <plugin.jsonのパス>
  python3 -c '
import json,sys
mkt_path, plugin_path = sys.argv[1], sys.argv[2]
try:
    m = json.load(open(mkt_path))
except Exception as e:
    print("FAIL:parse_marketplace:" + str(e)); sys.exit(0)
try:
    p = json.load(open(plugin_path))
except Exception as e:
    print("FAIL:parse_plugin:" + str(e)); sys.exit(0)
print("OK:parse")

mkt_name = m.get("name")
# 開発用(yosage-dev-harness-dev)と公開用(yosage-dev-harness)のどちらかなら OK。
# 公開用の名前を開発用リポジトリに置いた誤りは公開スクリプト側が止める。ここは2つのどちらでもない値を止める。
print(("OK:" if mkt_name in ("yosage-dev-harness-dev", "yosage-dev-harness") else "FAIL:") + "mkt_name:" + str(mkt_name))

import re
desc = m.get("description")
# description は開発用・公開用で共通の中立の文言。語「開発用」と、開発用マーケットプレイス名(-dev が語の末尾)を含めない。
# 欠落(None)は OK のまま。文字列以外は TypeError で落とさず明示の FAIL にする。
if desc is None:
    print("OK:mkt_desc:(none)")
elif not isinstance(desc, str):
    print("FAIL:mkt_desc:not a string:" + repr(desc))
else:
    print(("FAIL:" if ("開発用" in desc or re.search(r"-dev([^0-9A-Za-z-]|$)", desc)) else "OK:") + "mkt_desc:" + desc)

owner_name = (m.get("owner") or {}).get("name")
print(("OK:" if owner_name == "yosage-project" else "FAIL:") + "owner_name:" + str(owner_name))

plugins0 = (m.get("plugins") or [{}])[0]
print(("OK:" if plugins0.get("source") == "./harness" else "FAIL:") + "plugins0_source:" + str(plugins0.get("source")))

plugin_name = p.get("name")
print(("OK:" if plugins0.get("name") == plugin_name and plugin_name else "FAIL:") + "name_match:" + str(plugins0.get("name")) + "!=" + str(plugin_name))

author_name = (p.get("author") or {}).get("name")
print(("OK:" if author_name == owner_name and author_name else "FAIL:") + "author_name:" + str(author_name) + "!=" + str(owner_name))
' "$1" "$2"
}
echo "== プラグイン骨格: marketplace.json / plugin.json の形 =="
_p90_mkt_out="$(_p90_check_marketplace "$ROOT/.claude-plugin/marketplace.json" "$H/.claude-plugin/plugin.json")"
out_hasnt "marketplace.json/plugin.json は両方とも JSON として正しくパースできる" "FAIL:parse" "$_p90_mkt_out"
out_has "marketplace.json: name は開発用(yosage-dev-harness-dev)または公開用(yosage-dev-harness)の名前" "OK:mkt_name:" "$_p90_mkt_out"
out_has "marketplace.json: description は語「開発用」を含まず、開発用マーケットプレイス名が語として現れない" "OK:mkt_desc:" "$_p90_mkt_out"
out_has "marketplace.json: owner.name は yosage-project" "OK:owner_name:yosage-project" "$_p90_mkt_out"
out_has "marketplace.json: plugins[0].source は ./harness" "OK:plugins0_source:./harness" "$_p90_mkt_out"
out_has "marketplace.json: plugins[0].name と plugin.json の name が一致する" "OK:name_match:" "$_p90_mkt_out"
out_has "plugin.json: author.name が marketplace.json の owner.name と一致する" "OK:author_name:" "$_p90_mkt_out"

# marketplace.json の1フィールドを差し替えた fixture で check1 を走らせ、その出力を返す。
# $1=フィールド名 $2=差し替える値(JSON)。$2 が "__DELETE__" ならフィールドを消す。
_p90_mutated_out() {
  local dir out
  dir="$(mktemp -d)"
  python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))
if sys.argv[3] == "__DELETE__":
    d.pop(sys.argv[2], None)
else:
    d[sys.argv[2]] = json.loads(sys.argv[3])
json.dump(d, open(sys.argv[4], "w"))
' "$ROOT/.claude-plugin/marketplace.json" "$1" "$2" "$dir/marketplace.json"
  out="$(_p90_check_marketplace "$dir/marketplace.json" "$H/.claude-plugin/plugin.json")"
  rm -rf "$dir"
  printf '%s\n' "$out"
}
_p90_desc_out() { _p90_mutated_out description "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")"; }

echo "== marketplace.json の name: 開発用・公開用の両方で OK、どちらでもない値は赤くなる =="
# 実ファイルの name は公開スナップショットでは公開用に書き換わるため、ここでは固定しない(上の「2つのどちらか」の検査だけ)。
# 値まで含めた照合はフィクスチャの対照だけで行う。
_p90_nc2_out="$(_p90_mutated_out name '"yosage-dev-harness-dev"')"
out_has "開発用の名前 yosage-dev-harness-dev は値まで含めて OK になる" $'OK:mkt_name:yosage-dev-harness-dev\n' "$_p90_nc2_out"
_p90_nc2_out="$(_p90_mutated_out name '"yosage-dev-harness"')"
out_has "公開用の名前 yosage-dev-harness は OK になる(許可リストから公開用を外す退行を検知する)" $'OK:mkt_name:yosage-dev-harness\n' "$_p90_nc2_out"
_p90_nc2_out="$(_p90_mutated_out name '"yosage-dev-harness-other"')"
out_has "negative control: name を開発用・公開用以外の値に書き換えると mkt_name 判定が FAIL になる" "FAIL:mkt_name:yosage-dev-harness-other" "$_p90_nc2_out"

echo "== marketplace.json の description: 「開発用」・開発用名(語として)が現れると赤くなる(3系統) =="
# (a) 語「開発用」だけを含み、開発用マーケットプレイス名を含まない → 「開発用」の検査だけで落ちる。
out_has "(a) 「開発用」だけを含む description は FAIL になる" "FAIL:mkt_desc:" "$(_p90_desc_out 'yosage-dev-harness の開発用マーケットプレイス')"
# (b) 開発用名だけを含み、語「開発用」を含まない → 正規表現の検査だけで落ちる。直後が全角括弧・句点・文末・空白の各形。
out_has "(b) 開発用名の直後が全角括弧でも FAIL になる" "FAIL:mkt_desc:" "$(_p90_desc_out '配る（yosage-dev-harness-dev）マーケットプレイス')"
out_has "(b) 開発用名の直後が句点でも FAIL になる" "FAIL:mkt_desc:" "$(_p90_desc_out 'マーケットプレイス yosage-dev-harness-dev。')"
out_has "(b) 開発用名が文末でも FAIL になる" "FAIL:mkt_desc:" "$(_p90_desc_out 'マーケットプレイス yosage-dev-harness-dev')"
out_has "(b) 開発用名の直後が空白でも FAIL になる" "FAIL:mkt_desc:" "$(_p90_desc_out 'yosage-dev-harness-dev を配る')"
# (c) 製品名 yosage-dev-harness だけ(-dev の後に - が続く) → OK。
out_has "(c) 製品名 yosage-dev-harness だけの中立の description は OK になる" "OK:mkt_desc:" "$(_p90_desc_out 'Claude Code のプラグイン yosage-dev-harness を配るマーケットプレイス')"
out_has "description が文字列でない場合は明示の FAIL になる(TypeError で落ちない)" "FAIL:mkt_desc:" "$(_p90_mutated_out description 123)"
out_has "description の欠落は OK のまま(検査の趣旨は開発用の文言が戻らないこと)" "OK:mkt_desc:" "$(_p90_mutated_out description __DELETE__)"


echo "== negative control: plugin.json の author.name を marketplace.json の owner.name と食い違わせると check1 が赤くなる =="
_p90_nc3_dir="$(mktemp -d)"
python3 -c '
import json
d = json.load(open("'"$H"'/.claude-plugin/plugin.json"))
d["author"] = {"name": "someone-else"}
json.dump(d, open("'"$_p90_nc3_dir"'/plugin.json", "w"))
'
_p90_nc3_out="$(_p90_check_marketplace "$ROOT/.claude-plugin/marketplace.json" "$_p90_nc3_dir/plugin.json")"
out_has "negative control: author.name を owner.name と食い違わせると author_name 判定が FAIL になる" "FAIL:author_name:someone-else" "$_p90_nc3_out"
rm -rf "$_p90_nc3_dir"

# --- check2: hooks.json の全フック参照先(exec形式)が harness/ 配下に実在し読める ---
_p90_check_hooks_json() {  # <hooks.json のパス> <harness ルート絶対パス>
  python3 -c '
import json,sys,os
hooks_path, harness_root = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(hooks_path))
except Exception as e:
    print("FAIL:parse:" + str(e)); sys.exit(0)
bad = []
total = 0
for event, groups in (d.get("hooks") or {}).items():
    for g in groups:
        for hk in g.get("hooks", []):
            total += 1
            if hk.get("type") != "command":
                bad.append(f"{event}: type!=command"); continue
            cmd = hk.get("command")
            if cmd != "bash":
                bad.append(f"{event}: command!=bash({cmd})"); continue
            args = hk.get("args") or []
            arg0 = str(args[0]) if args else ""
            if not arg0.startswith("${CLAUDE_PLUGIN_ROOT}/"):
                bad.append(f"{event}: args[0] does not start with CLAUDE_PLUGIN_ROOT ({arg0})"); continue
            if "CLAUDE_PROJECT_DIR" in arg0 or ".claude/" in arg0:
                bad.append(f"{event}: args[0] points at .claude/ install path ({arg0})"); continue
            rel = arg0[len("${CLAUDE_PLUGIN_ROOT}/"):]
            target = harness_root + "/" + rel
            if not (os.path.isfile(target) and os.access(target, os.R_OK)):
                bad.append(f"{event}: target not found/readable: {target}")
if total == 0:
    print("FAIL:no hooks found")
elif bad:
    print("FAIL:" + " | ".join(bad))
else:
    print("OK:" + str(total))
' "$1" "$2"
}
echo "== プラグイン骨格: hooks.json の全フックが exec 形式で harness/ 配下の実在ファイルを指す =="
_p90_hooks_check="$(_p90_check_hooks_json "$H/hooks/hooks.json" "$H")"
out_has "hooks.json: 全フックが exec 形式・実在するスクリプトを指す(件数>0)" "OK:" "$_p90_hooks_check"

echo "== プラグイン骨格: hooks.json の PreToolUse に guard.sh の配線がある(Bash/Edit|Write|MultiEdit/Read|Grep) =="
# guard.sh は Bash 用の matcher に加え、Edit|Write|MultiEdit・Read|Grep 用の matcher でも呼ばれる
# 必要がある(呼ばれなければ guard.sh 側のコードがどれだけ正しくても発火しない=配線側の回帰)。
_p90_guard_wiring="$(python3 -c "
import json
d = json.load(open('$H/hooks/hooks.json'))
pre = d.get('hooks', {}).get('PreToolUse', [])
def wired(matcher):
    return any(e.get('matcher') == matcher and any('guard.sh' in (h.get('args') or [''])[0] for h in e.get('hooks', [])) for e in pre)
missing = [m for m in ('Bash', 'Edit|Write|MultiEdit', 'Read|Grep') if not wired(m)]
print('FAIL:' + str(missing) if missing else 'OK')
" 2>&1)"
out_has "hooks.json: PreToolUse に Bash/Edit|Write|MultiEdit/Read|Grep いずれも guard.sh が配線されている" "OK" "$_p90_guard_wiring"

echo "== プラグイン骨格: SessionStart グループに matcher が無い(全開始種別で発火) =="
_p90_sessionstart_has_matcher="$(python3 -c '
import json
d = json.load(open("'"$H"'/hooks/hooks.json"))
groups = d.get("hooks", {}).get("SessionStart", [])
print("has_matcher" if any("matcher" in g for g in groups) else "no_matcher")
')"
out_hasnt "hooks.json: SessionStart に matcher キーが無い" "has_matcher" "$_p90_sessionstart_has_matcher"

echo "== プラグイン骨格: plugin.json の version が semver で、VERSION ファイルは存在しない =="
_p90_version="$(python3 -c 'import json;print(json.load(open("'"$H"'/.claude-plugin/plugin.json")).get("version",""))' 2>/dev/null)"
if printf '%s' "$_p90_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok "plugin.json: version が semver(x.y.z)形式(実測: $_p90_version)"
else
  ng "plugin.json: version が semver(x.y.z)形式(実測: $_p90_version)"
fi
file_isnt "リポジトリに VERSION ファイルが無い(版の正本は plugin.json の version 1箇所)" "$ROOT/VERSION"

echo "== negative control: hooks.json に存在しないスクリプト名を入れると check2 が赤くなる =="
_p90_nc_dir="$(mktemp -d)"
mkdir -p "$_p90_nc_dir/harness/hooks"
cp "$H/hooks/hooks.json" "$_p90_nc_dir/harness/hooks/hooks.json"
python3 -c '
import json
p = "'"$_p90_nc_dir"'/harness/hooks/hooks.json"
d = json.load(open(p))
d["hooks"]["PreToolUse"][0]["hooks"][0]["args"][0] = "${CLAUDE_PLUGIN_ROOT}/hooks/nonexistent-script-xyz.sh"
json.dump(d, open(p, "w"))
'
_p90_nc_hooks_check="$(_p90_check_hooks_json "$_p90_nc_dir/harness/hooks/hooks.json" "$_p90_nc_dir/harness")"
out_has "negative control: 存在しないスクリプト名を仕込むと check2 は FAIL になる" "FAIL:" "$_p90_nc_hooks_check"
rm -rf "$_p90_nc_dir"
