# test/suites/37-knowledge-store.sh — グローバル知識ストアの雛形(templates/knowledge-store/)と、
# ストア専用の形の検査コマンド(yosage-dev-harness-knowledge-store-check)の検査。
#   通る見本 = 雛形そのもの / 落ちる見本 = 雛形を一時ディレクトリへ写して一部を壊したもの。
#   ネットワークには出ない(同期の source はローカルの git リポジトリ)。
TPL="$ROOT/templates/knowledge-store"
KSC="$H/bin/yosage-dev-harness-knowledge-store-check"

# 正しいエントリは雛形に置かず、テストの中で雛形の写しに足す(frontmatter 等の検査を固定するために要る)。
# KSBASE = 雛形 + 正しいエントリ2件。落ちる見本・通す見本・同期は、これを写して使う。
ksb_E1="knowledge/process/2026-10-16-one-rule-and-its-reason-per-entry.md"
ksb_E2="knowledge/process/2026-10-16-review-promotion-prs-before-merge.md"
KSBASE_ROOT="$(mktemp -d)"; KSBASE="$KSBASE_ROOT/store"
cp -R "$TPL" "$KSBASE"; mkdir -p "$KSBASE/knowledge/process"
printf -- '---\nid: one-rule-and-its-reason-per-entry\ndate: 2026-10-16\ndomain: process\ntags: [knowledge, writing]\nscope: global\nstatus: active\nsummary: 1件に1つのルールと理由を書く\n---\n\n## 判断 / ルール\n1件に1つのルールを書く。\n\n## なぜ\n複数の主張を混ぜると、一部だけ古くなったときに直せない。\n' > "$KSBASE/$ksb_E1"
printf -- '---\nid: review-promotion-prs-before-merge\ndate: 2026-10-16\ndomain: process\ntags: [knowledge, review]\nscope: global\nstatus: active\nsummary: 昇格 PR は人が読んでからマージする\n---\n\n## 判断 / ルール\n人がレビューしてからマージする。\n\n## なぜ\n全プロジェクトに写されるため。\n' > "$KSBASE/$ksb_E2"
bash "$KSC" "$KSBASE" >/dev/null 2>&1; exit_is "テストで足した正しいエントリ2件は検査を通る(土台の対照)" 0 "$?"

echo "== 知識ストアの雛形: 形の検査コマンドを通る(通る見本) =="
file_is "雛形が実在する: README.md"          "$TPL/README.md"
file_is "雛形が実在する: LICENSE"            "$TPL/LICENSE"
file_is "雛形が実在する: review/criteria.md" "$TPL/review/criteria.md"
# 雛形には見本のエントリを置かない(消し忘れが同期で全プロジェクトに配られ、本物の知見として引かれるため)。
# review/criteria.md も役割の説明だけ(code-reviewer が組織の観点として読むため、見本の観点を置かない)。
tpl_entries="$(find "$TPL/knowledge" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$tpl_entries" = 0 ]; then ok "雛形にエントリ(見本)を置いていない"; else ng "雛形にエントリ(見本)を置いていない (got $tpl_entries 件)"; fi
file_is "雛形の knowledge/ は .gitkeep で残している" "$TPL/knowledge/.gitkeep"
out_hasnt "criteria.md に見本の観点を置かない" "見本" "$(cat "$TPL/review/criteria.md")"
out_hasnt "criteria.md に番号付きの観点の項目を置かない(役割の説明だけ)" "1." "$(grep -E '^[0-9]+\. ' "$TPL/review/criteria.md" | head -1)"
out_has "criteria.md の冒頭に「以下は説明であり観点ではない」と書く" "レビューの観点ではない" "$(head -4 "$TPL/review/criteria.md")"
ksc_out="$(bash "$KSC" "$TPL" 2>/dev/null)"; ksc_rc=$?
exit_is "雛形は形の検査コマンドを通る(exit 0)" 0 "$ksc_rc"
out_is_empty "雛形の検査は違反を1件も出さない" "$ksc_out"
ksc_err="$(bash "$KSC" "$TPL" 2>&1 >/dev/null)"
out_has "検査件数が標準エラー出力に出る(エントリ 0 件でも検査は走る)" "エントリ 0 件を検査し、違反 0 件" "$ksc_err"

echo "== 知識ストアの雛形: 内容の約束(公開面の決まり・丸ごと写される前提) =="
tpl_hits="$(grep -rEn '#[0-9]+|このリポジトリ|このリポ[^ジ]' "$TPL" 2>/dev/null || true)"
out_is_empty "雛形に issue/PR 番号・場所を指す言葉が無い(非公開の名前の検出は公開スクリプトの禁止語検査に任せる)" "$tpl_hits"
out_has "LICENSE は MIT" "MIT License" "$(cat "$TPL/LICENSE")"
out_has "LICENSE の著作権者はハーネスと同じ" "Copyright (c) 2026 Naoki Honjo" "$(cat "$TPL/LICENSE")"
tpl_readme="$(cat "$TPL/README.md")"
out_has "README: ブランチ main とマージコミットを書く" "マージコミット" "$tpl_readme"
out_has "README: 昇格 PR を人がレビューしてマージすると書く" "人がその PR をレビューして、マージする" "$tpl_readme"
out_has "README: 形の約束はハーネスの docs/knowledge.md を参照する" "docs/knowledge.md" "$tpl_readme"
# 公開時に置き換える2つの目印は、それぞれちょうど1回ずつだけ現れる(置換の漏れ・重複を防ぐ)。
for tok in '@HARNESS_VERSION@' '@HARNESS_DOCS_URL@'; do
  n="$(grep -rFo "$tok" "$TPL" | wc -l | tr -d ' ')"
  if [ "$n" = 1 ]; then ok "公開時に置き換える目印 $tok はちょうど1回"; else ng "公開時に置き換える目印 $tok はちょうど1回 (got $n)"; fi
done
other_tok="$(grep -rEoh '@[A-Z_]{3,}@' "$TPL" | grep -vFx -e '@HARNESS_VERSION@' -e '@HARNESS_DOCS_URL@' || true)"
out_is_empty "置き換える目印はこの2つだけ" "$other_tok"
out_has "criteria.md: 役割(基本の観点はハーネスのレビュアーの定義が持つ)を冒頭に書く" "ハーネスのレビュアーの定義が持つ" "$(cat "$TPL/review/criteria.md")"

echo "== 知識ストアの雛形: 同期にかけると global/・索引・criteria.md ができる(雛形にテストでエントリを足した写しを、ローカルの git リポジトリの source にする) =="
ksy="$(mktemp -d)"; ksy_src="$ksy/store"; ksy_proj="$ksy/proj"; ksy_cache="$ksy/cache/yosage-dev-harness/knowledge"
cp -R "$KSBASE" "$ksy_src"
( cd "$ksy_src" && git init -q && git checkout -q -b main && gitc add -A && gitc commit -qm init )
mk_consumer "$ksy_proj"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ksy_src" > "$ksy_proj/.claude/yosage-dev-harness.local.json"
bash "$H/lib/knowledge-sync.sh" "$ksy_proj" "$ksy_cache" >/dev/null 2>&1
exit_is "雛形を source にした同期は exit 0" 0 "$?"
file_is "同期: review/criteria.md ができる"               "$ksy_proj/.claude/review/criteria.md"
file_is "同期: knowledge/global/INDEX.md ができる"         "$ksy_proj/.claude/knowledge/global/INDEX.md"
file_is "同期: knowledge/global/INDEX.archive.md もできる"  "$ksy_proj/.claude/knowledge/global/INDEX.archive.md"
file_is "同期: エントリ(1件目)が global/ に写る" "$ksy_proj/.claude/knowledge/global/process/2026-10-16-one-rule-and-its-reason-per-entry.md"
file_is "同期: エントリ(2件目)が global/ に写る" "$ksy_proj/.claude/knowledge/global/process/2026-10-16-review-promotion-prs-before-merge.md"
ksy_index="$(cat "$ksy_proj/.claude/knowledge/global/INDEX.md" 2>/dev/null)"
out_has "同期: 索引にエントリの id が載る" "one-rule-and-its-reason-per-entry" "$ksy_index"
# 同期が読むのは knowledge/ と review/criteria.md だけ。README・LICENSE は導入先へ来ない。
file_isnt "同期: README.md は導入先へ写らない(.claude 直下)" "$ksy_proj/.claude/README.md"
file_isnt "同期: LICENSE は導入先へ写らない(.claude 直下)"   "$ksy_proj/.claude/LICENSE"
file_isnt "同期: README.md は global/ へ写らない"             "$ksy_proj/.claude/knowledge/global/README.md"
file_isnt "同期: LICENSE は global/ へ写らない"               "$ksy_proj/.claude/knowledge/global/LICENSE"
# 同期後の導入先の知見を、導入先側の検査(構造監査)にかけても、雛形の写しは欠陥を出さない。
ksy_audit="$(bash "$H/lib/knowledge-audit.sh" "$ksy_proj/.claude" 2>/dev/null)"
out_is_empty "同期した写しは構造監査でも欠陥を出さない" "$ksy_audit"
rm -rf "$ksy"

echo "== 知識ストアの雛形: 出荷する形そのもの(空の knowledge/・.gitkeep だけ)を source にしても同期できる =="
kse="$(mktemp -d)"; kse_src="$kse/store"; kse_proj="$kse/proj"; kse_cache="$kse/cache/yosage-dev-harness/knowledge"
cp -R "$TPL" "$kse_src"
( cd "$kse_src" && git init -q && git checkout -q -b main && gitc add -A && gitc commit -qm init )
kse_n="$(find "$kse_src/knowledge" -type f ! -name .gitkeep | wc -l | tr -d ' ')"
if [ "$kse_n" = 0 ]; then ok "対照: source の knowledge/ に .gitkeep 以外のファイルが無い"; else ng "対照: source の knowledge/ に .gitkeep 以外のファイルが無い (got $kse_n)"; fi
mk_consumer "$kse_proj"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$kse_src" > "$kse_proj/.claude/yosage-dev-harness.local.json"
for kse_round in 1 2; do
  bash "$H/lib/knowledge-sync.sh" "$kse_proj" "$kse_cache" >/dev/null 2>&1
  exit_is "空の雛形を source にした同期($kse_round 回目)は exit 0" 0 "$?"
  file_is "空の雛形の同期($kse_round 回目): knowledge/global/ ができる" "$kse_proj/.claude/knowledge/global"
  file_is "空の雛形の同期($kse_round 回目): 索引 INDEX.md ができる" "$kse_proj/.claude/knowledge/global/INDEX.md"
  file_is "空の雛形の同期($kse_round 回目): review/criteria.md ができる" "$kse_proj/.claude/review/criteria.md"
done
kse_list="$(bash "$H/lib/knowledge-index.sh" "$kse_proj/.claude/knowledge/global" --list 2>&1)"; kse_rc=$?
exit_is "空の雛形の同期後: --list は exit 0" 0 "$kse_rc"
out_is_empty "空の雛形の同期後: --list は空(エントリ0件)" "$kse_list"
out_hasnt "空の雛形の同期後: 索引にエントリの行が無い" "| process |" "$(cat "$kse_proj/.claude/knowledge/global/INDEX.md")"
kse_log="$(cat "$kse_proj/.claude/knowledge/.sync-log" 2>/dev/null)"
out_hasnt "空の雛形の同期: .sync-log に失敗の記録が無い" "failed" "$kse_log"
rm -rf "$kse"

echo "== 知識ストアの形の検査: 使い方の誤りは exit 2 =="
bash "$KSC" >/dev/null 2>&1;                       exit_is "引数なしは exit 2" 2 "$?"
bash "$KSC" "$TPL" extra >/dev/null 2>&1;          exit_is "引数が2つは exit 2" 2 "$?"
bash "$KSC" "$TPL/does-not-exist" >/dev/null 2>&1; exit_is "存在しないディレクトリは exit 2" 2 "$?"

echo "== 知識ストアの形の検査: 壊した見本は落ちる(落ちる見本) =="
# 雛形(にテストで正しいエントリを足した KSBASE)を一時ディレクトリへ写して一部を壊す。壊す編集が実際に効いたこと(写しと元に差があること)と、
# 落ちたのが形の検査の違反(exit 1・期待した検査コードだけ。クラッシュの exit 2 ではない)であることを確かめる。
# 壊す前の写しが先に通ること(対照)も毎回確かめ、写しそのものが原因で落ちていないことを示す。
ksb_rm_knowledge()   { rm -rf "$1/knowledge"; }
ksb_rm_criteria()    { rm -f "$1/review/criteria.md"; }
ksb_rm_review()      { rm -rf "$1/review"; }
ksb_rm_readme()      { rm -f "$1/README.md"; }
ksb_stray_root()     { printf 'x\n' > "$1/notes.txt"; }
ksb_stray_in_knowledge() { printf 'x\n' > "$1/knowledge/INDEX.md"; }
ksb_bad_filename()   { mv "$1/$ksb_E1" "$1/knowledge/process/Entry One.md"; }
ksb_broken_summary() { sed -i.orig 's/^summary: .*/summary: >/' "$1/$ksb_E1" && rm -f "$1/$ksb_E1.orig"; }
ksb_drop_status()    { sed -i.orig '/^status:/d' "$1/$ksb_E1" && rm -f "$1/$ksb_E1.orig"; }
ksb_scope_local()    { sed -i.orig 's/^scope: global/scope: local/' "$1/$ksb_E1" && rm -f "$1/$ksb_E1.orig"; }
ksb_no_frontmatter() { printf '本文だけ\n' > "$1/$ksb_E1"; }
ksb_issue_ref()      { printf '\n詳細は #%s を参照。\n' 123 >> "$1/$ksb_E1"; }
ksb_sub()            { python3 - "$1" "$2" "$3" <<'PY'
import re, sys
p, pat, rep = sys.argv[1:4]
t = open(p, encoding='utf-8').read()
open(p, 'w', encoding='utf-8').write(re.sub(pat, rep, t, count=1, flags=re.M))
PY
}
ksb_date_mismatch()  { ksb_sub "$1/$ksb_E1" '^date: .*' 'date: 2026-10-17'; }
ksb_domain_mismatch(){ ksb_sub "$1/$ksb_E1" '^domain: .*' 'domain: api'; }
ksb_bad_date()       { ksb_sub "$1/$ksb_E1" '^date: .*' 'date: 2026-13-45'; }
ksb_bad_tags()       { ksb_sub "$1/$ksb_E1" '^tags: .*' 'tags: knowledge'; }
ksb_bad_status()     { ksb_sub "$1/$ksb_E1" '^status: .*' 'status: done'; }
ksb_archived_nodate(){ ksb_sub "$1/$ksb_E1" '^status: .*' 'status: archived'; }
ksb_source_nochecked(){ ksb_sub "$1/$ksb_E1" '^status: (.*)' 'status: \1\nsource: https://example.test/doc'; }
ksb_unexpected_dir() { mkdir -p "$1/knowledge/process/sub"; }
ksb_bad_domain_name(){ mkdir -p "$1/knowledge/Bad_Domain"; }
ksb_reserved_domain(){ mkdir -p "$1/knowledge/global"; cp "$1/$ksb_E1" "$1/knowledge/global/2026-10-16-x.md"; }
ksb_empty_criteria() { : > "$1/review/criteria.md"; }
ksb_review_stray()   { printf 'x\n' > "$1/review/notes.md"; }
ksb_not_indexed()    { cp "$1/$ksb_E1" "$1/knowledge/process/.hidden.md"; ksb_sub "$1/knowledge/process/.hidden.md" '^id: .*\n' ''; }
ksb_duplicate_id()   { cp "$1/$ksb_E1" "$1/knowledge/process/2026-10-16-copy.md"; }
ksb_bad_supersedes() { ksb_sub "$1/$ksb_E1" '^status: (.*)' 'status: \1\nsupersedes: no-such-id'; }
ksb_trailing_status(){ ksb_sub "$1/$ksb_E1" '^status: .*' 'status: archived   # 退役'; }
ksb_trailing_tags()  { ksb_sub "$1/$ksb_E1" '^tags: .*' 'tags: [a]   # 検索用'; }
ksb_drop_summary()   { ksb_sub "$1/$ksb_E1" '^summary: .*\n' ''; }
# 壊し方の一覧: 名前 | 期待する検査コード | 壊す編集の関数。
# 各行で、雛形を一時ディレクトリへ写して一部を壊す。次の3点を確かめる:
#   (1) 壊す前の写しが検査を通る(対照。写しそのものが原因で落ちていないことを示す)
#   (2) 壊す編集が実際に効いた(写しが元と差を持つ。対象が実在しない・置換が空振りした編集を見逃さない)
#   (3) 落ちたのが形の検査の違反(exit 1・期待した検査コードだけ。クラッシュの exit 2 ではない)
ksb_table='knowledge/ が無い|missing-knowledge-dir|ksb_rm_knowledge
review/criteria.md が無い|missing-criteria|ksb_rm_criteria
review/ ごと無い|missing-review-dir|ksb_rm_review
README.md が無い|missing-readme|ksb_rm_readme
ルート直下に置けないファイル|unexpected-root-entry|ksb_stray_root
knowledge/ 直下に索引を置く|unexpected-file|ksb_stray_in_knowledge
ファイル名が規約に合わない|bad-filename|ksb_bad_filename
summary が複数行指示子(>)|broken-summary|ksb_broken_summary
frontmatter の status が無い|missing-field|ksb_drop_status
scope が local|bad-scope|ksb_scope_local
frontmatter が無い|bad-frontmatter|ksb_no_frontmatter
持ち運べない参照(issue 番号)が残る|audit:travel-issue-ref|ksb_issue_ref
date がファイル名の日付と違う|date-mismatch|ksb_date_mismatch
domain がディレクトリ名と違う|domain-mismatch|ksb_domain_mismatch
date が実在しない日付|bad-date|ksb_bad_date
tags が [] の形でない|bad-tags|ksb_bad_tags
status が未知の値|bad-status|ksb_bad_status
archived なのに退役日が無い|missing-field|ksb_archived_nodate
source があるのに checked が無い|missing-field|ksb_source_nochecked
ドメインの下にディレクトリ|unexpected-dir|ksb_unexpected_dir
ドメイン名が規約に合わない|bad-domain-name|ksb_bad_domain_name
ドメイン名が予約名 global|reserved-domain-name|ksb_reserved_domain
review/criteria.md が空|empty-criteria|ksb_empty_criteria
review/ に余計なファイル|unexpected-file|ksb_review_stray
索引に載らないエントリ(先頭がドットのファイル名)|bad-filename not-indexed|ksb_not_indexed
id が重複している|duplicate-id|ksb_duplicate_id
supersedes がストアの中に無い id|bad-supersedes|ksb_bad_supersedes
値の後ろにコメント(status)|trailing-comment|ksb_trailing_status
値の後ろにコメント(tags)|trailing-comment|ksb_trailing_tags
summary 項目が無い(違反は1本だけ)|missing-field|ksb_drop_summary'

while IFS='|' read -r ksb_name ksb_expect ksb_fn; do
  ksb_d="$(mktemp -d)" || { ng "$ksb_name: 一時ディレクトリを作れない"; continue; }
  cp -R "$KSBASE" "$ksb_d/store"
  bash "$KSC" "$ksb_d/store" >/dev/null 2>&1; ksb_ctl=$?
  if [ "$ksb_ctl" != 0 ]; then ng "$ksb_name: 壊す前の写しが検査を通らない(対照が成り立たない)"; rm -rf "$ksb_d"; continue; fi
  "$ksb_fn" "$ksb_d/store"
  if diff -rq "$KSBASE" "$ksb_d/store" >/dev/null 2>&1; then
    ng "$ksb_name: 壊す編集が効いていない(写しが元と同じ)"; rm -rf "$ksb_d"; continue
  fi
  ksb_out="$(bash "$KSC" "$ksb_d/store" 2>/dev/null)"; ksb_rc=$?
  exit_is "$ksb_name: 検査は違反を見つけて exit 1" 1 "$ksb_rc"
  ksb_codes="$(printf '%s\n' "$ksb_out" | awk -F'\t' 'NF>=2{print $2}' | sort -u | tr '\n' ' ')"
  if [ "$ksb_codes" = "$ksb_expect " ]; then ok "$ksb_name: 違反は期待した検査コードだけ ($ksb_codes)"
  else ng "$ksb_name: 検査コードが期待と違う (expected: $ksb_expect / got: $ksb_codes)"; fi
  rm -rf "$ksb_d"
done <<< "$ksb_table"

echo "== 知識ストアの形の検査: 通してよい形は通る(厳しすぎない) =="
# 厳しさの判断を固定する。壊す見本と同じ手順で雛形を写して「許す側」に編集し、編集が効いた上で exit 0・違反0件。
ksp_pass_dotclaude()   { mkdir -p "$1/.claude" && printf '{}\n' > "$1/.claude/yosage-dev-harness.local.json"; }
ksp_pass_gitkeep()     { : > "$1/knowledge/.gitkeep"; : > "$1/review/.gitkeep"; mkdir -p "$1/knowledge/ops" && : > "$1/knowledge/ops/.gitkeep"; }
ksp_pass_underscore()  { printf 'x\n' > "$1/knowledge/process/_notes.md"; }
ksp_pass_superseded()  { ksb_sub "$1/$ksb_E1" '^status: .*' 'status: superseded'; }
ksp_pass_archived()    { ksb_sub "$1/$ksb_E1" '^status: (.*)' 'status: archived\narchived: 2026-10-17'; }
ksp_pass_supersedes()  { ksb_sub "$1/$ksb_E1" '^status: (.*)' 'status: \1\nsupersedes: review-promotion-prs-before-merge'; }
ksp_pass_source()      { ksb_sub "$1/$ksb_E1" '^status: (.*)' 'status: \1\nsource: https://example.test/doc#frag\nchecked: 2026-10-16'; }
ksp_pass_empty_opt()   { ksb_sub "$1/$ksb_E1" '^status: (.*)' 'status: \1\nsupersedes:\narchived:'; }
ksp_pass_hash_summary(){ ksb_sub "$1/$ksb_E1" '^summary: .*' 'summary: C# の # は要約に書いてよい'; }
ksp_pass_empty_kdir()  { rm -rf "$1/knowledge/process" && mkdir -p "$1/knowledge"; }
ksp_table='ルート直下の .claude(手元のハーネス導入)|ksp_pass_dotclaude
.gitkeep(knowledge/・review/・ドメイン)|ksp_pass_gitkeep
ドメインの下の _ 始まりの .md|ksp_pass_underscore
status: superseded のエントリ|ksp_pass_superseded
status: archived と archived の退役日|ksp_pass_archived
supersedes がストアの中の id を指す|ksp_pass_supersedes
source と checked が揃う(URL に # を含む)|ksp_pass_source
supersedes・archived が空の項目|ksp_pass_empty_opt
summary の本文に # を含む|ksp_pass_hash_summary
エントリが1件も無い knowledge/|ksp_pass_empty_kdir'
while IFS='|' read -r ksp_name ksp_fn; do
  ksp_d="$(mktemp -d)" || { ng "$ksp_name: 一時ディレクトリを作れない"; continue; }
  cp -R "$KSBASE" "$ksp_d/store"
  "$ksp_fn" "$ksp_d/store"
  if diff -rq "$KSBASE" "$ksp_d/store" >/dev/null 2>&1; then
    ng "$ksp_name: 編集が効いていない(写しが元と同じ)"; rm -rf "$ksp_d"; continue
  fi
  ksp_out="$(bash "$KSC" "$ksp_d/store" 2>/dev/null)"; ksp_rc=$?
  exit_is "$ksp_name: 検査を通る(exit 0)" 0 "$ksp_rc"
  out_is_empty "$ksp_name: 違反を1件も出さない" "$ksp_out"
  rm -rf "$ksp_d"
done <<< "$ksp_table"

echo "== 知識ストアの形の検査: 部品が想定外に失敗したら合格に見せず exit 2 =="
# 部品(索引生成器・構造監査)を常に失敗する偽物に差し替えた lib の写しで走らせる。差し替えが効いたこと
# (写しの部品が元と違う)と、雛形を通常どおり通せる対照(差し替え前の写しは exit 0)も確かめる。
for ksf_part in knowledge-audit knowledge-index; do
  ksf_d="$(mktemp -d)"; cp -R "$H/lib" "$ksf_d/lib"
  bash "$ksf_d/lib/knowledge-store-check.sh" "$KSBASE" >/dev/null 2>&1; ksf_ctl=$?
  exit_is "$ksf_part を差し替える前の写しは雛形を通す(対照)" 0 "$ksf_ctl"
  printf '#!/usr/bin/env bash\necho boom >&2\nexit 3\n' > "$ksf_d/lib/$ksf_part.sh"
  if cmp -s "$H/lib/$ksf_part.sh" "$ksf_d/lib/$ksf_part.sh"; then ng "$ksf_part: 差し替えが効いていない"; else ok "$ksf_part: 差し替えが効いた"; fi
  ksf_out="$(bash "$ksf_d/lib/knowledge-store-check.sh" "$KSBASE" 2>"$ksf_d/err")"; ksf_rc=$?
  exit_is "$ksf_part が失敗したら検査コマンドは exit 2(合格の exit 0 にしない)" 2 "$ksf_rc"
  out_is_empty "$ksf_part が失敗したら違反の一覧は出さない" "$ksf_out"
  out_has "$ksf_part が失敗したら原因を標準エラー出力へ出す" "想定外に失敗した" "$(cat "$ksf_d/err")"
  out_has "$ksf_part の標準エラー出力(boom)も伝える" "boom" "$(cat "$ksf_d/err")"
  rm -rf "$ksf_d"
done

echo "== 知識ストアの形の検査: Python の想定外の例外・python3 が無いときも exit 2(違反ありの exit 1 に見せない) =="
ksx_d="$(mktemp -d)"; cp -R "$H/lib" "$ksx_d/lib"
bash "$ksx_d/lib/knowledge-store-check.sh" "$KSBASE" >/dev/null 2>&1; exit_is "例外を仕込む前の写しは雛形を通す(対照)" 0 "$?"
ksb_sub "$ksx_d/lib/knowledge-store-check.sh" '^sys\.excepthook = _crash$' 'sys.excepthook = _crash\nraise RuntimeError("boom")'
if cmp -s "$H/lib/knowledge-store-check.sh" "$ksx_d/lib/knowledge-store-check.sh"; then ng "例外の仕込みが効いていない"; else ok "例外の仕込みが効いた"; fi
ksx_out="$(bash "$ksx_d/lib/knowledge-store-check.sh" "$KSBASE" 2>"$ksx_d/err")"; ksx_rc=$?
exit_is "Python が想定外の例外を起こしたら exit 2" 2 "$ksx_rc"
out_is_empty "例外のときは違反の一覧を出さない" "$ksx_out"
out_has "例外のときは原因を標準エラー出力へ出す" "検査中に想定外の例外" "$(cat "$ksx_d/err")"
ksx_empty="$ksx_d/emptybin"; mkdir -p "$ksx_empty"
ksx_bash="$(command -v bash)"
PATH="$ksx_empty" "$ksx_bash" "$H/lib/knowledge-store-check.sh" "$KSBASE" >/dev/null 2>"$ksx_d/err2"; ksx_rc2=$?
exit_is "python3 が無いと exit 2(何も検査せずに合格にしない)" 2 "$ksx_rc2"
out_has "python3 が無いときは理由を標準エラー出力へ出す" "python3 が無い" "$(cat "$ksx_d/err2")"
if ( PATH="$ksx_empty"; command -v python3 >/dev/null 2>&1 ); then ng "PATH から python3 を外せていない"; else ok "PATH から python3 を外せた(操作が効いた)"; fi
rm -rf "$ksx_d"

echo "== 知識ストアの形の検査: 検査は読むだけ(ストアに何も書かない) =="
ksr="$(mktemp -d)"; cp -R "$KSBASE" "$ksr/store"
ksr_before="$(cd "$ksr/store" && find . -type f -exec shasum {} + | sort; find . | sort)"
bash "$KSC" "$ksr/store" >/dev/null 2>&1
ksr_after="$(cd "$ksr/store" && find . -type f -exec shasum {} + | sort; find . | sort)"
if [ "$ksr_before" = "$ksr_after" ]; then ok "検査の前後でストアのファイルと構成が同じ"; else ng "検査の前後でストアが変わった"; fi
rm -rf "$ksr"

echo "== 知識ストアの形の検査: 実行ファイル名が bin/ にあり、ドキュメントが参照する =="
file_is "bin/yosage-dev-harness-knowledge-store-check が実在する" "$KSC"
if [ -x "$KSC" ]; then ok "実行ビットが立っている"; else ng "実行ビットが立っている"; fi
out_has "docs/knowledge.md が検査コマンドの使い方を書く" "yosage-dev-harness-knowledge-store-check" "$(cat "$ROOT/docs/knowledge.md")"
rm -rf "$KSBASE_ROOT"
