echo "== catalog-gen.sh: fixture の3種メタデータ形(skill/agent/rule/hook)から一覧を生成 =="
cg="$(mktemp -d)"
mkdir -p "$cg/skills/sample-skill" "$cg/agents" "$cg/rules" "$cg/hooks"
printf -- '---\nname: sample-skill\ndescription: サンプルスキルの説明文。\n---\n\n# body\n' > "$cg/skills/sample-skill/SKILL.md"
printf -- '---\nname: sample-agent\ndescription: サンプルエージェントの説明文。\ntools: Read\nmodel: sonnet\n---\n\nbody\n' > "$cg/agents/sample-agent.md"
printf -- '# サンプルルール（不変条件）\n\n> ルールの正本注記です。\n\n本文…\n' > "$cg/rules/sample-rule.md"
printf -- '#!/usr/bin/env bash\n# PreToolUse フック: サンプル用途の説明。\n#   2行目の続きコメント。\nset -uo pipefail\necho hi\n' > "$cg/hooks/sample-hook.sh"
cg_out="$(bash "$ROOT/scripts/catalog-gen.sh" "$cg" 2>&1)"
out_has "skills: name/description 抽出"     "sample-skill"      "$cg_out"
out_has "skills: description 本文が入る"     "サンプルスキルの説明文"  "$cg_out"
out_has "agents: name/description 抽出"     "sample-agent"      "$cg_out"
out_has "agents: description 本文が入る"     "サンプルエージェントの説明文" "$cg_out"
out_has "rules: 見出し抽出"                  "サンプルルール（不変条件）" "$cg_out"
out_hasnt "rules: 見出し直後の引用行は注記として抽出されない(注記列は廃止済み)" "ルールの正本注記です"    "$cg_out"
out_has "hooks: ヘッダコメントから用途抽出"    "サンプル用途の説明"     "$cg_out"
out_has "hooks: ヘッダコメント複数行を連結"    "2行目の続きコメント"    "$cg_out"
out_hasnt "hooks: シェバン行自体は混入しない"  "usr/bin/env"        "$cg_out"
rm -rf "$cg"

echo "== catalog-gen.sh: python3 が無ければ何もせず exit 0(安全側フォールバック) =="
cg2="$(mktemp -d)"; mkdir -p "$cg2/skills"
PATH="/nonexistent-empty-dir-$$" "$(command -v bash)" "$ROOT/scripts/catalog-gen.sh" "$cg2" >/dev/null 2>&1
exit_is "python3 非在でも exit 0" 0 "$?"
rm -rf "$cg2"

echo "== catalog-gen.sh: このリポジトリ自身の harness/ から実在する skill/agent/rule/hook 名が拾える =="
cg3_out="$(bash "$ROOT/scripts/catalog-gen.sh" "$ROOT/harness" 2>&1)"
out_has "catalog: skills 見出しを含む"   "### skills" "$cg3_out"
out_has "catalog: 実在する skill 名"     "capture-learning" "$cg3_out"
out_has "catalog: agents 見出しを含む"   "### agents" "$cg3_out"
out_has "catalog: 実在する agent 名"     "implementer" "$cg3_out"
out_has "catalog: rules 見出しを含む"    "### rules" "$cg3_out"
out_has "catalog: hooks 見出しを含む"    "### hooks" "$cg3_out"

echo "== README カタログ drift 回帰: harness/ から生成した managed 区間が README の現内容と一致 =="
# doc-drift-check が .docs/ 外の宣言済み正本(README の機能カタログ)を見落としていた欠落の回帰防止。
# 「機械管理区間」自体を、payload(harness/)から生成した内容と実 README の内容で突き合わせる
# (手で編集して古びても検知できる=催促役)。
readme_between="$(awk '/<!-- BEGIN yosage-dev-harness catalog \(generated\) -->/{f=1;next}/<!-- END yosage-dev-harness catalog \(generated\) -->/{f=0}f' "$ROOT/README.md")"
fresh_catalog="$(bash "$ROOT/scripts/catalog-gen.sh" "$ROOT/harness" 2>/dev/null)"
if [ "$readme_between" = "$fresh_catalog" ]; then
  ok "README の機能カタログ区間は生成物と一致(drift 無し)"
else
  ng "README の機能カタログ区間が生成物と乖離(要 scripts/catalog.sh --write)"
fi

echo "== scripts/catalog.sh --check: 再生成した結果と README.md の区間が一致すれば exit 0 =="
exit_is "catalog --check: drift が無ければ exit 0" 0 "$(bash "$ROOT/scripts/catalog.sh" --check >/dev/null 2>&1; echo $?)"

echo "== scripts/catalog.sh --check: README の区間を1行壊すと exit 1(失敗すべきときに失敗する) =="
_cc_src="$(_src_copy)"
python3 - "$_cc_src/README.md" <<'PY'
import sys
p = sys.argv[1]
begin = '<!-- BEGIN yosage-dev-harness catalog (generated) -->'
end = '<!-- END yosage-dev-harness catalog (generated) -->'
lines = open(p, encoding='utf-8').read().splitlines(keepends=True)
i = lines.index(begin + '\n')
j = lines.index(end + '\n')
assert i < j
for k in range(i + 1, j):
    if 'capture-learning' in lines[k]:
        lines[k] = lines[k].replace('capture-learning', 'capture-learning-BROKEN-FOR-TEST', 1)
        break
else:
    raise AssertionError('capture-learning not found inside managed block')
open(p, 'w', encoding='utf-8').writelines(lines)
PY
_cc_check_rc="$(bash "$_cc_src/scripts/catalog.sh" --check >/dev/null 2>&1; echo $?)"
exit_is "catalog --check: 区間を壊すと exit 1" 1 "$_cc_check_rc"
rm -rf "$_cc_src"

echo "== scripts/catalog.sh --write が README の機能カタログ区間を再生成 =="
# 追跡ファイル(README.md)を汚さないよう payload を一時コピーへ隔離し、コピー側の README.md を汚す。
_readme_src="$(_src_copy)"
printf '\n(手で書いた古い行)\n' >> "$_readme_src/README.md"   # わざと管理区間の外側を汚す(保存されるはず)
bash "$_readme_src/scripts/catalog.sh" --write >/dev/null 2>&1
out_has "catalog --write: 区間外の手書き追記は保存される" "(手で書いた古い行)" "$(cat "$_readme_src/README.md")"
readme_between2="$(awk '/<!-- BEGIN yosage-dev-harness catalog \(generated\) -->/{f=1;next}/<!-- END yosage-dev-harness catalog \(generated\) -->/{f=0}f' "$_readme_src/README.md")"
out_has "catalog --write: 再生成後も生成物と一致" "capture-learning" "$readme_between2"
[ ! -f "$_readme_src/README.md.pre-yosage" ] && ok "catalog --write: well-formed な区間は再生成に .pre-yosage を作らない" || ng "catalog --write: 想定外の .pre-yosage が生成された"
rm -rf "$_readme_src"

echo "== scripts/catalog.sh --write の well-formed 判定回帰(write_managed_block のマーカー境界誤認防止) =="
# write_managed_block 自体は README.md の機能カタログ区間で現役なので、一次レビューで追加された
# 回帰ラチェット(存在有無だけの判定は END欠落・複数組・利用者記述内の偶然一致行で境界を誤認し、
# 間の利用者記述を無警告で消しうる)を catalog --write 経由で再現する。追跡ファイル(README.md)を
# 汚さないよう payload を一時コピーへ隔離し、全ケース共通でコピー側の README.md を直接汚してから
# catalog --write を回す。
_cat_src="$(_src_copy)"

# (1) END マーカー欠落(利用者が誤って消した状態)
{
  printf '<!-- BEGIN yosage-dev-harness catalog (generated) -->\n'
  printf '重要な利用者記述(ENDマーカーが無い状態)\n'
} > "$_cat_src/README.md"
bash "$_cat_src/scripts/catalog.sh" --write >/dev/null 2>&1
file_is "catalog Must-2(END欠落): .pre-yosageへ退避される" "$_cat_src/README.md.pre-yosage"
out_has "catalog Must-2(END欠落): 退避ファイルに利用者記述が残る" "重要な利用者記述" "$(cat "$_cat_src/README.md.pre-yosage" 2>/dev/null)"
_cat_begin_n="$(grep -c 'BEGIN yosage-dev-harness catalog (generated)' "$_cat_src/README.md" 2>/dev/null)" || _cat_begin_n=0
_cat_end_n="$(grep -c 'END yosage-dev-harness catalog (generated)' "$_cat_src/README.md" 2>/dev/null)" || _cat_end_n=0
exit_is "catalog Must-2(END欠落): 再生成後はBEGINがちょうど1個" 1 "${_cat_begin_n:-0}"
exit_is "catalog Must-2(END欠落): 再生成後はENDがちょうど1個"   1 "${_cat_end_n:-0}"
rm -f "$_cat_src/README.md.pre-yosage"

# (2) BEGIN/END が2組(過去の不具合等で重複した状態)。2組目の間の利用者記述も含め退避で保全する。
{
  printf 'prefix\n'
  printf '<!-- BEGIN yosage-dev-harness catalog (generated) -->\nold body 1\n<!-- END yosage-dev-harness catalog (generated) -->\n'
  printf '2組の間の重要な利用者記述\n'
  printf '<!-- BEGIN yosage-dev-harness catalog (generated) -->\nold body 2\n<!-- END yosage-dev-harness catalog (generated) -->\n'
} > "$_cat_src/README.md"
bash "$_cat_src/scripts/catalog.sh" --write >/dev/null 2>&1
file_is "catalog Must-2(2組): .pre-yosageへ退避される" "$_cat_src/README.md.pre-yosage"
out_has "catalog Must-2(2組): 退避ファイルに2組間の利用者記述が残る" "2組の間の重要な利用者記述" "$(cat "$_cat_src/README.md.pre-yosage" 2>/dev/null)"
rm -f "$_cat_src/README.md.pre-yosage"

# (3) 利用者記述内にマーカーと byte 完全一致する行が紛れ込むケース(引用・コピペ例)。
{
  printf '利用者のメモ:\n'
  printf '<!-- BEGIN yosage-dev-harness catalog (generated) -->\n'
  printf '(上の行はマーカー文字列そのものをコピペした説明用の引用で、実際のブロック開始ではない)\n\n'
  printf '<!-- BEGIN yosage-dev-harness catalog (generated) -->\nreal old body\n<!-- END yosage-dev-harness catalog (generated) -->\n'
  printf 'SUFFIX after real block\n'
} > "$_cat_src/README.md"
bash "$_cat_src/scripts/catalog.sh" --write >/dev/null 2>&1
file_is "catalog Must-2(マーカー同一行): .pre-yosageへ退避される" "$_cat_src/README.md.pre-yosage"
out_has "catalog Must-2(マーカー同一行): 退避ファイルにreal old bodyが残る" "real old body" "$(cat "$_cat_src/README.md.pre-yosage" 2>/dev/null)"
out_has "catalog Must-2(マーカー同一行): 退避ファイルにSUFFIXが残る" "SUFFIX after real block" "$(cat "$_cat_src/README.md.pre-yosage" 2>/dev/null)"
rm -f "$_cat_src/README.md.pre-yosage"

# (4) 二度連続で catalog --write しても BEGIN/END マーカー・区間外の手書き記述が増殖しない(冪等)。
printf '手書きの区間外メモ\n<!-- BEGIN yosage-dev-harness catalog (generated) -->\nold body\n<!-- END yosage-dev-harness catalog (generated) -->\n' > "$_cat_src/README.md"
bash "$_cat_src/scripts/catalog.sh" --write >/dev/null 2>&1
bash "$_cat_src/scripts/catalog.sh" --write >/dev/null 2>&1
_cat_idem_begin_n="$(grep -c 'BEGIN yosage-dev-harness catalog (generated)' "$_cat_src/README.md" 2>/dev/null)" || _cat_idem_begin_n=0
_cat_idem_end_n="$(grep -c 'END yosage-dev-harness catalog (generated)' "$_cat_src/README.md" 2>/dev/null)" || _cat_idem_end_n=0
_cat_idem_outside_n="$(grep -c '手書きの区間外メモ' "$_cat_src/README.md" 2>/dev/null)" || _cat_idem_outside_n=0
exit_is "catalog 冪等性: 二度writeしてもBEGINマーカーは増殖しない"     1 "${_cat_idem_begin_n:-0}"
exit_is "catalog 冪等性: 二度writeしてもENDマーカーは増殖しない"       1 "${_cat_idem_end_n:-0}"
exit_is "catalog 冪等性: 二度writeしても区間外の手書き記述は増殖しない" 1 "${_cat_idem_outside_n:-0}"
if [ -f "$_cat_src/README.md.pre-yosage" ]; then
  ng "catalog 冪等性: well-formed な区間の再write は.pre-yosageを作らない"
else
  ok "catalog 冪等性: well-formed な区間の再write は.pre-yosageを作らない"
fi

rm -rf "$_cat_src"
