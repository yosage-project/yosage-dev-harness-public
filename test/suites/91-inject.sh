# test/suites/91-inject.sh — ルール注入(SessionStart/SubagentStart)の静的テスト。
# `claude` は起動しない(実測は手動: PR 本文に記録)。ここは CI 相当の速い静的検査。

RULES_DIR="$H/rules"
HOOKS_JSON="$H/hooks/hooks.json"

echo "== 注入サイズ: 前置き込みで9,000字未満(1万字上限に余裕1,000字) =="
# Claude Code が上限を数える単位(UTF-16 相当の可能性がある)と python の len() の数え方が
# 一致する保証は無いため、1万字の上限に対して1,000字の余裕を取ることでその差を吸収する。
# 先頭の文字が `{` でないことも確認する(SessionStart はプレーンな標準出力を文脈に入れるが、
# JSON として読めそうな出力は JSON として解釈が試みられ、読めないとテキストとしても入らない)。
_size_fail=0
for _rule_path in "$RULES_DIR"/*.md; do
  [ -f "$_rule_path" ] || continue
  _rname="$(basename "$_rule_path" .md)"
  _out="$(bash "$H/hooks/inject-rule.sh" SessionStart "$_rname" </dev/null)"
  _len="$(printf '%s' "$_out" | python3 -c 'import sys;print(len(sys.stdin.read()))')"
  if [ "$_len" -ge 9000 ]; then
    ng "注入サイズ: ルール $_rname が9,000字以上(実測: ${_len})"
    _size_fail=1
  fi
  case "$_out" in
    '{'*) ng "注入サイズ: ルール $_rname の先頭文字が { (JSON と誤解釈されうる)"; _size_fail=1 ;;
  esac
done
[ "$_size_fail" = "0" ] && ok "注入サイズ: 全ルールが9,000字未満・先頭が { でない"

echo "== negative control: ルールを9,500字に水増しすると上のサイズ検査が赤くなる =="
_nc_size_dir="$(mktemp -d)"
mkdir -p "$_nc_size_dir/harness/hooks" "$_nc_size_dir/harness/rules"
cp "$H/hooks/inject-rule.sh" "$_nc_size_dir/harness/hooks/inject-rule.sh"
python3 -c "
with open('$_nc_size_dir/harness/rules/bloated.md', 'w') as f:
    f.write('# bloated\n\n' + ('x' * 9500))
"
_nc_size_out="$(bash "$_nc_size_dir/harness/hooks/inject-rule.sh" SessionStart bloated </dev/null)"
_nc_size_len="$(printf '%s' "$_nc_size_out" | python3 -c 'import sys;print(len(sys.stdin.read()))')"
if [ "$_nc_size_len" -ge 9000 ]; then
  ok "negative control: 9,500字に水増ししたルールは9,000字以上になる(実測: ${_nc_size_len})"
else
  ng "negative control: 水増ししたはずが9,000字未満(実測: ${_nc_size_len})"
fi
rm -rf "$_nc_size_dir"

echo "== hooks.json: ルールファイル名の集合 == SessionStart注入対象 == SubagentStart注入対象(過不足なし) =="
_hj_check="$(python3 -c '
import json, glob, os

rules_dir = "'"$RULES_DIR"'"
hooks_path = "'"$HOOKS_JSON"'"

rule_names = {os.path.splitext(os.path.basename(f))[0] for f in glob.glob(os.path.join(rules_dir, "*.md"))}

d = json.load(open(hooks_path))

def collect(event, target_event):
    names = set()
    for group in d.get("hooks", {}).get(event, []):
        for hk in group.get("hooks", []):
            args = hk.get("args") or []
            if len(args) >= 3 and "inject-rule.sh" in str(args[0]) and args[1] == target_event:
                names.add(args[2])
    return names

session_names = collect("SessionStart", "SessionStart")
subagent_names = collect("SubagentStart", "SubagentStart")

problems = []
if session_names != rule_names:
    problems.append("SessionStart != rules: only-in-session=%s only-in-rules=%s" % (sorted(session_names - rule_names), sorted(rule_names - session_names)))
if subagent_names != rule_names:
    problems.append("SubagentStart != rules: only-in-subagent=%s only-in-rules=%s" % (sorted(subagent_names - rule_names), sorted(rule_names - subagent_names)))

print("FAIL:" + " | ".join(problems) if problems else "OK:" + str(len(rule_names)))
')"
out_has "hooks.json: ルール名の集合が SessionStart/SubagentStart の両方と過不足なく一致" "OK:" "$_hj_check"

echo "== negative control: hooks.json から1ルールの SubagentStart 配線を外すと上の一致検査が赤くなる =="
_nc_hj_dir="$(mktemp -d)"
python3 -c '
import json
d = json.load(open("'"$HOOKS_JSON"'"))
groups = d["hooks"]["SubagentStart"]
for g in groups:
    hooks = g.get("hooks", [])
    for i, hk in enumerate(hooks):
        args = hk.get("args") or []
        if len(args) >= 3 and args[2] == "commit":
            del hooks[i]
            break
json.dump(d, open("'"$_nc_hj_dir"'/hooks.json", "w"))
'
_nc_hj_check="$(python3 -c '
import json, glob, os

rule_names = {os.path.splitext(os.path.basename(f))[0] for f in glob.glob("'"$RULES_DIR"'/*.md")}
d = json.load(open("'"$_nc_hj_dir"'/hooks.json"))

def collect(event, target_event):
    names = set()
    for group in d.get("hooks", {}).get(event, []):
        for hk in group.get("hooks", []):
            args = hk.get("args") or []
            if len(args) >= 3 and "inject-rule.sh" in str(args[0]) and args[1] == target_event:
                names.add(args[2])
    return names

subagent_names = collect("SubagentStart", "SubagentStart")
print("FAIL" if subagent_names != rule_names else "OK")
')"
out_has "negative control: SubagentStart から1ルール外すと一致検査が FAIL になる" "FAIL" "$_nc_hj_check"
rm -rf "$_nc_hj_dir"

echo "== hooks.json: SessionStart・SubagentStart のグループに matcher が無い(全開始種別で発火) =="
_no_matcher_check="$(python3 -c '
import json
d = json.load(open("'"$HOOKS_JSON"'"))
bad = []
for event in ("SessionStart", "SubagentStart"):
    for g in d.get("hooks", {}).get(event, []):
        if "matcher" in g:
            bad.append(event)
print("FAIL:" + str(bad) if bad else "OK")
')"
out_has "hooks.json: SessionStart/SubagentStart に matcher キーが無い" "OK" "$_no_matcher_check"

echo "== inject-rule.sh 単体: SessionStart は「前置き＋空行＋ルール本文」と完全一致 =="
_ir_expected="$(printf '以下は、このリポジトリで利用者が有効にしたプラグイン yosage-dev-harness の取り決めです（ルール: naming）。\n\n%s' "$(cat "$RULES_DIR/naming.md")")"
_ir_actual="$(bash "$H/hooks/inject-rule.sh" SessionStart naming </dev/null)"
if [ "$_ir_expected" = "$_ir_actual" ]; then
  ok "inject-rule.sh: SessionStart 出力が前置き＋空行＋本文と完全一致"
else
  ng "inject-rule.sh: SessionStart 出力が期待値と不一致"
fi

echo "== inject-rule.sh 単体: SubagentStart は JSON(hookSpecificOutput.additionalContext) =="
_ir_sa_out="$(bash "$H/hooks/inject-rule.sh" SubagentStart naming </dev/null)"
_ir_sa_check="$(printf '%s' "$_ir_sa_out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ev = d.get("hookSpecificOutput", {}).get("hookEventName")
ctx = d.get("hookSpecificOutput", {}).get("additionalContext", "")
print("event=" + str(ev))
print("has_naming=" + str("naming" in ctx and "命名の優先順位" in ctx))
')"
out_has "inject-rule.sh: SubagentStart の hookEventName が SubagentStart" "event=SubagentStart" "$_ir_sa_check"
out_has "inject-rule.sh: SubagentStart の additionalContext にルール本文を含む" "has_naming=True" "$_ir_sa_check"

echo "== inject-rule.sh 単体: python3 だけの PATH でも SubagentStart が同じ結果になる =="
_minpath_dir="$(mktemp -d)"
for _t in bash cat grep sed dirname printf; do
  _p="$(command -v "$_t" 2>/dev/null)"; [ -n "$_p" ] && ln -sf "$_p" "$_minpath_dir/$_t"
done
_realpy="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
[ -n "$_realpy" ] && ln -sf "$_realpy" "$_minpath_dir/python3"
_ir_py_out="$(PATH="$_minpath_dir" bash "$H/hooks/inject-rule.sh" SubagentStart naming </dev/null)"
_ir_py_check="$(printf '%s' "$_ir_py_out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("event=" + str(d.get("hookSpecificOutput", {}).get("hookEventName")))
'  2>&1)"
out_has "inject-rule.sh: python3のみのPATHでもSubagentStartが正しいJSONを返す" "event=SubagentStart" "$_ir_py_check"

echo "== inject-rule.sh 単体: 存在しないルール名は exit 1 =="
bash "$H/hooks/inject-rule.sh" SessionStart nonexistent-rule-xyz </dev/null >/dev/null 2>&1
exit_is "inject-rule.sh: 存在しないルール名は exit 1" 1 "$?"

echo "== inject-rule.sh 単体: jq も python3 も無い PATH で SubagentStart は exit 1 =="
_noboth_dir="$(mktemp -d)"
for _t in bash cat grep sed dirname printf; do
  _p="$(command -v "$_t" 2>/dev/null)"; [ -n "$_p" ] && ln -sf "$_p" "$_noboth_dir/$_t"
done
PATH="$_noboth_dir" bash "$H/hooks/inject-rule.sh" SubagentStart naming </dev/null >/dev/null 2>&1
exit_is "inject-rule.sh: jq/python3 両欠で SubagentStart は exit 1" 1 "$?"
rm -rf "$_minpath_dir" "$_noboth_dir"

echo "== inject-check.sh 単体: 正常なら無出力・exit 0 =="
_ick_out="$(bash "$H/hooks/inject-check.sh" </dev/null 2>&1)"; _ick_rc="$?"
out_is_empty "inject-check.sh: 正常時は無出力" "$_ick_out"
exit_is "inject-check.sh: 正常時は exit 0" 0 "$_ick_rc"

echo "== inject-check.sh 単体: jq も python3 も無い PATH では exit 1・1行目が意味の通る文 =="
_ick_noboth_dir="$(mktemp -d)"
for _t in bash cat grep sed dirname printf; do
  _p="$(command -v "$_t" 2>/dev/null)"; [ -n "$_p" ] && ln -sf "$_p" "$_ick_noboth_dir/$_t"
done
_ick_noboth_out="$(PATH="$_ick_noboth_dir" bash "$H/hooks/inject-check.sh" </dev/null 2>&1)"; _ick_noboth_rc="$?"
exit_is "inject-check.sh: jq/python3 両欠で exit 1" 1 "$_ick_noboth_rc"
out_has "inject-check.sh: 1行目が yosage-dev-harness: で始まる" "yosage-dev-harness:" "$(printf '%s\n' "$_ick_noboth_out" | head -1)"
rm -rf "$_ick_noboth_dir"

echo "== inject-check.sh 単体: ルールの1本が読めない一時コピーでは exit 1 =="
_ick_unreadable_dir="$(mktemp -d)"
mkdir -p "$_ick_unreadable_dir/harness/hooks" "$_ick_unreadable_dir/harness/rules"
cp "$H/hooks/inject-check.sh" "$_ick_unreadable_dir/harness/hooks/inject-check.sh"
cp "$RULES_DIR"/*.md "$_ick_unreadable_dir/harness/rules/"
chmod 000 "$_ick_unreadable_dir/harness/rules/naming.md"
bash "$_ick_unreadable_dir/harness/hooks/inject-check.sh" </dev/null >/dev/null 2>&1
_ick_unreadable_rc="$?"
chmod 644 "$_ick_unreadable_dir/harness/rules/naming.md"
exit_is "inject-check.sh: ルールが1本読めないと exit 1" 1 "$_ick_unreadable_rc"
rm -rf "$_ick_unreadable_dir"

echo "== パス参照が残っていない: harness/scripts/README.md に rules/harness/ 形の参照が0件 =="
# README.md は catalog-gen.sh の自動生成区間の外に手書きの prose を持つ(一次レビューで実際に
# この手書き部分への書き換え漏れが1件見つかった)。harness/scripts だけでなく README.md も
# 走査対象に含めることで、この種の漏れを機械的に検知する。
_path_refs="$(grep -rnE 'rules/harness/' "$ROOT/harness" "$ROOT/scripts" "$ROOT/README.md" 2>/dev/null || true)"
out_is_empty "パス参照が残っていない(rules/harness/ 形が0件)" "$_path_refs"
