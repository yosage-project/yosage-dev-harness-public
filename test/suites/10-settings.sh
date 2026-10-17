echo "== JSON 妥当性 =="
for f in github/labels.json config/defaults.json config/yosage-dev-harness.schema.json hooks/hooks.json .claude-plugin/plugin.json; do
  if python3 -c "import json;json.load(open('$H/$f'))" 2>/dev/null; then ok "valid: $f"; else ng "invalid: $f"; fi
done

echo "== lib/secret-patterns.sh: 秘密ファイル一覧(SECRET_FILE_DENY_GLOBS)が唯一の置き場 =="
# 推奨設定の見本(setup の段で作る)との一致検査はそちらの Sub-issue に委ねる。ここでは
# secret-patterns.sh 自身の内部一貫性(一覧の件数・判定関数との整合)だけを固定する。
_sfg_result="$(bash -c "
set -uo pipefail
source '$H/lib/secret-patterns.sh'
_deny_count=\${#SECRET_FILE_DENY_GLOBS[@]}
[ \"\$_deny_count\" -eq 38 ] || { echo \"FAIL: SECRET_FILE_DENY_GLOBS count=\$_deny_count (expected 38)\"; exit 1; }
for g in \"\${SECRET_FILE_DENY_GLOBS[@]}\"; do
  sf_is_secret_path \"\$g\" || { echo \"FAIL: sf_is_secret_path 偽: \$g\"; exit 1; }
done
_rules_count=\$(sf_deny_rules | wc -l | tr -d '[:space:]')
[ \"\$_rules_count\" -eq 38 ] || { echo \"FAIL: sf_deny_rules count=\$_rules_count (expected 38)\"; exit 1; }
echo OK
" 2>&1)"
out_has "secret-patterns.sh: SECRET_FILE_DENY_GLOBS が38件・全件 sf_is_secret_path で真・sf_deny_rules も38行" "OK" "$_sfg_result"

echo "== 配布 payload: gh pr merge を実行する記述が無いこと =="
# skills/agents/hooks/lib/rules のいずれにも PR マージ操作を実行する記述(手順書での
# 指示・許可等)を残さない。guard.sh 自身はマージ呼び出しを検知する側であり、
# 検知パターンは「gh」「pr」「merge」を別トークンとして正規表現に分解して持つため(fold_quotes_and_heredocs
# 由来の判定と同じ書き方)、この文字列の逐語一致(3語連続のリテラル)には現れない。
_gpm_hits="$(grep -rlF 'gh pr merge' "$H/skills" "$H/agents" "$H/hooks" "$H/lib" "$H/rules" 2>/dev/null || true)"
out_is_empty "配布 payload(skills/agents/hooks/lib/rules)に gh pr merge の逐語記述が無い" "$_gpm_hits"
