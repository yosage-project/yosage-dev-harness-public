echo "== 横断ルール: ポリシー指紋が skills/agents に restate されていない(単一ホーム) =="
# rules の正本にのみ存在すべき“ポリシー指紋”。skill/agent に現れたら restate=drift。
# 汎用語は対象にしない。指紋は正本の文言に追従させる(乖離させない)。これは regression ラチェット
# (意味的 drift の完全オラクルではない。例: 指紋3は禁止プロンプト「実行してはならない/しない」のみ対象で、
#  正当な「gh pr merge は ask」名指しは拾わない=保証の本体は移行時の物理削除)。
# 開発上の約束(配布物向けの冒頭注記に以前は明記していたが、受け取る側には意味を持たないため撤去した):
# rules/*.md は harness 横断ルールの正本であり、paths: フロントマター無し＝全セッション・
# 全 subagent へ常時オンでロードされる。skill/agent はこのルールを名前参照するに留め、ポリシーの
# 内容そのものを再記述しない(再記述＝drift)。ここの指紋チェックは、その再記述が実際に起きていない
# ことを機械的に確かめる仕組みである。
fp_fail=0
while IFS= read -r fp; do
  [ -n "$fp" ] || continue
  hits="$(grep -rlE "$fp" "$H/skills" "$H/agents" 2>/dev/null || true)"
  if [ -n "$hits" ]; then ng "指紋が skills/agents に混入: [$fp] → $(echo "$hits" | tr '\n' ' ')"; fp_fail=1; fi
done <<'FP'
標準ループ: draft
自己判断.{0,2}素通し
gh pr merge.*(実行してはならない|実行しない)
責務の所在
主体が.*(担う|回す)
メイン直
Conventional Commits
ストール一本
メインは実装しない
commit 前の自己チェック
staged diff.*スイープ
設計ルーティング.*討議着火ゲート
外部参照を開かずに成立
home repo の外で読まれるか
行にひもづけられる指摘をサマリ本文に丸めない
着火は常に人間トリガ
自社所有のリポジトリ
宣言が無ければ付けない
片方だけを変えると発火・掃除のどちらかが揃わなくなる
この不変条件は規律で受ける
FP
# 注: grounding-labels / issue-discipline / doc-placement は指紋を置かない。
#   接地ラベル記号(✓内部 等)・repo 外参照・正本/検討中 等の語は home/detector スキル
#   (grounded-design・issue-create・consistency-reviewer・design-doc)が正当に使うため誤検知する。
#   これらは移行時の物理削除で単一ホーム化し、指紋は付けない(保証の本体は物理削除)。
# 注: design-routing の「Direct は討議しない」「自己着火」等の語は deliberate-design skill が
#   正当に「討議するかの入口判定は design-routing が担う」と名前参照するため指紋対象にしない。
#   指紋は正本の unique な文言（見出し+文脈が一意のもの）を選ぶ。
# 注: 「自社所有のリポジトリ」「宣言が無ければ付けない」は commit.md の Co-Authored-By 署名トレーラ節が
#   持つ判断軸そのものの文言(見出しではなく判断基準の中身)。正当な名前参照(「commit.md の『Co-Authored-By
#   署名トレーラ』節に従う」)はこれらの語を含まないため誤検知しない(実装時に grep で現状無混入を確認済み)。
#   壊れたときの帰結が不可逆(未開示の相手方リポジトリへ署名入りコミットが入り、squash しない運用では
#   後から消せない)であるため、対象を2ファイルに絞った下の targeted assertion(名指し out_hasnt)に加えて
#   ここでも拾う: 広域側=未知の第三のファイルが同種の判断基準を再記述したときの検知、
#   targeted assertion=既知の2ファイルに対する具体的な失敗メッセージ、と役割を分けて両方残す。
[ "$fp_fail" = "0" ] && ok "横断ルール指紋は skills/agents に無し(正本 rules のみ)"
out_has "正本 pr-loop.md が存在"          "PR 標準ループ"   "$(cat "$H/rules/pr-loop.md" 2>/dev/null)"
out_has "pr-loop.md: レビュー投稿形式節を明記" "レビュー投稿形式" "$(cat "$H/rules/pr-loop.md" 2>/dev/null)"
out_has "pr-loop.md: 行アンカー有無での振り分けを明記" "行にひもづく指摘 → インライン" "$(cat "$H/rules/pr-loop.md" 2>/dev/null)"
out_has "pr-loop.md: 1回の review 送信を明記" "1回の review 送信" "$(cat "$H/rules/pr-loop.md" 2>/dev/null)"
out_has "pr-loop.md: APPROVE しない旨を明記" "APPROVE はしない" "$(cat "$H/rules/pr-loop.md" 2>/dev/null | tr -d '\`')"
# レビュー投稿形式: 4箇所のコピーは pr-loop への名前参照に統一し、投稿メカニズムの再記述をやめる。
for _rf in code-reviewer consistency-reviewer best-practice-reviewer; do
  _rf_body="$(cat "$H/agents/$_rf.md" 2>/dev/null)"
  out_has  "$_rf.md: pr-loop の「レビュー投稿形式」への名前参照" "pr-loop の「レビュー投稿形式」" "$_rf_body"
  out_hasnt "$_rf.md: 投稿メカニズムの再記述(gh api pulls/.../reviews)が残っていない" "gh api" "$_rf_body"
  out_hasnt "$_rf.md: 投稿メカニズムの再記述(gh pr review)が残っていない" "gh pr review" "$_rf_body"
done
_op_body="$(cat "$H/skills/orchestrate-parallel/SKILL.md" 2>/dev/null)"
out_has  "orchestrate-parallel/SKILL.md: pr-loop の「レビュー投稿形式」への名前参照" "pr-loop の「レビュー投稿形式」" "$_op_body"
out_hasnt "orchestrate-parallel/SKILL.md: 投稿メカニズムの再記述(gh api pulls/.../reviews)が残っていない" "gh api" "$_op_body"
out_hasnt "orchestrate-parallel/SKILL.md: 投稿メカニズムの再記述(gh pr review)が残っていない" "gh pr review" "$_op_body"
out_has "正本 knowledge.md が存在"        "knowledge loop" "$(cat "$H/rules/knowledge.md" 2>/dev/null)"
out_has "knowledge.md: グローバル既定はローカル staging(反転済み)を明記" "既定はまずローカルに \`scope: global\` で staging" "$(cat "$H/rules/knowledge.md" 2>/dev/null)"
out_has "knowledge.md: travel 面の自己完結不変を明記" "書き方不変: travel 面の自己完結" "$(cat "$H/rules/knowledge.md" 2>/dev/null)"
out_has "capture-learning: 反転を反映し正本を名前参照(再記述しない)" "書き方不変: travel 面の自己完結" "$(cat "$H/skills/capture-learning/SKILL.md" 2>/dev/null)"

echo "== change-lanes.md: 変更レーン定義の単一ホーム化 =="
# レーン語彙(Direct/Tracked single/Design-first single/Epic)の定義正本は、以前は非配布の開発文書に
# あり、配布 rule(pr-loop/design-routing)がそれを参照していた=consumer で解決不能な dangling reference
# だった(配布物の .docs/ 参照の検査は、下の「許す一覧」のラチェットが受ける)。定義正本を配布側の change-lanes.md へ完全移動し、各 rule は名前参照に統一する。
file_is "rule: change-lanes.md が存在" "$H/rules/change-lanes.md"
_cl_body="$(cat "$H/rules/change-lanes.md" 2>/dev/null)"
out_hasnt "change-lanes.md: ルール管理についての冒頭の注記(常時オン等)は受け取る側には出さない(撤去済み)" "常時オン" "$_cl_body"
out_has "change-lanes.md: 4レーン定義表(Design-first single を含む)を持つ" "Design-first single" "$_cl_body"
out_has "change-lanes.md: Tracked single の定義を持つ" "Tracked single" "$_cl_body"
out_has "change-lanes.md: 追跡の要否/設計判断の要否が独立2軸である旨を明記" "独立した2軸" "$_cl_body"
out_has "change-lanes.md: 過去方針(distributed-gate-inlines-own-criteria)を反転した理由を明記" "過去方針の反転" "$_cl_body"

_dr_body="$(cat "$H/rules/design-routing.md" 2>/dev/null)"
out_has "design-routing: change-lanes への名前参照" "change-lanes" "$_dr_body"

_il_body="$(cat "$H/rules/implement-routing.md" 2>/dev/null)"
out_has "implement-routing: change-lanes への名前参照" "change-lanes" "$_il_body"
out_has "implement-routing: 委譲の例外(profile の宣言した範囲でメインが着火してよい)が書かれている" "例外: 人が profile で委譲を宣言した範囲では、メイン（オーケストレーター）が実装 dispatch を着火してよい" "$_il_body"
out_has "implement-routing: 委譲の対象は Epic に属さない単発の issue に限る" "Epic に属さない単発の issue の実装 dispatch の着火" "$_il_body"
out_has "implement-routing: 未宣言は委譲していない側に倒す" "未宣言は委譲していない側に倒す" "$_il_body"
out_has "implement-routing: 書式どおりでなければ未宣言として扱う" "この書式どおりでなければ未宣言として扱う" "$_il_body"
out_has "implement-routing: 対象外に Epic の Sub-issue(1件ずつでも)を明記" "Epic の Sub-issue（1件ずつであっても" "$_il_body"
out_has "implement-routing: 対象外に Epic 全体の実装を明記" "Epic 全体の実装（\`epic-implement\`）" "$_il_body"
out_has "implement-routing: 対象外に PR のマージを明記" "PR のマージ（[[pr-loop]]）" "$_il_body"
out_has "implement-routing: 委譲下でも implementer への dispatch を維持" "メインは自分で実装せず" "$_il_body"
out_hasnt "implement-routing: 新語「統制役」を持ち込まない" "統制役" "$_il_body"
_pp_body="$(cat "$H/rules/project-profile.md" 2>/dev/null)"
out_has "project-profile: 委譲の宣言の固定書式を定める" '- **実装の着火の委譲: `単発 issue`**' "$_pp_body"
out_has "project-profile: 書式どおりでなければ宣言なし扱い" "書式どおりでなければ" "$_pp_body"

_pl_body2="$(cat "$H/rules/pr-loop.md" 2>/dev/null)"
out_has "pr-loop.md: change-lanes への名前参照" "change-lanes" "$_pl_body2"
out_has "pr-loop.md: Tracked single/Design-first/Epic の code-reviewer 必須(帰結)を維持" "Epic** → \`yosage-dev-harness:code-reviewer\` 必須" "$_pl_body2"
out_has "pr-loop.md: Direct の自己レビュー可(帰結)を維持" "自己レビューで代替可" "$_pl_body2"
out_has "pr-loop.md: ベースは導入先の既定ブランチ(単発・Epic PR の向け先)" "ベース＝導入先の既定ブランチ" "$_pl_body2"
out_has "pr-loop.md: 単発・Epic PR の向け先が既定ブランチに従う旨を維持" "単発（Direct・Tracked single）・Epic PR" "$_pl_body2"
out_has "pr-loop.md: ベース解決の順(明示→profile の宣言→origin/HEAD→止めて聞く)を明記" "投入時に明示されたもの → 導入先の profile" "$_pl_body2"
out_has "pr-loop.md: ベース解決の実行ファイル名を明記" "yosage-dev-harness-base-branch" "$_pl_body2"
out_has "pr-loop.md: 決まらない(終了コード 1)は止めて人に聞く旨を明記" "終了コード 1（決まらない）は止めて人に聞き" "$_pl_body2"
out_has "pr-loop.md: 宣言が origin に無い(終了コード 3)は宣言の誤りとして止める旨を明記" "宣言の誤りとして止める" "$_pl_body2"
out_hasnt "pr-loop.md: 単発・Epic PR の向け先を develop に決め打ちした旧文言が残っていない" "Epic PR → **develop**" "$_pl_body2"

echo "== ベースの宣言の書式(project-profile)と、単発レーンがベースを実行ファイルで解決すること =="
_pp_body3="$(cat "$H/rules/project-profile.md" 2>/dev/null)"
out_has "project-profile: base ブランチの宣言の書式(1行)を明記" '- **base ブランチ: `<名前>`**' "$_pp_body3"
out_has "project-profile: 食い違う導入先でだけ書けばよい旨を明記" "食い違う導入先でだけ書けばよい" "$_pp_body3"
out_has "project-profile: スクリプトが profile の文章を解析しない旨を明記" "文章を解析しない" "$_pp_body3"
_ii_body3="$(cat "$H/skills/issue-implement/SKILL.md" 2>/dev/null)"
out_has   "issue-implement: ブランチ作成がベースの解決を実行ファイル経由で行う" 'base="$(yosage-dev-harness-base-branch' "$_ii_body3"
out_has   "issue-implement: 作業ブランチの起点が origin/\$base" 'git checkout -b <type>/<name> "origin/$base"' "$_ii_body3"
out_has   "issue-implement: draft PR の向け先が --base \$base" 'gh pr create --draft --base "$base"' "$_ii_body3"
out_hasnt "issue-implement: origin/develop を直書きしていない" "origin/develop" "$_ii_body3"
out_hasnt "issue-implement: --base develop を直書きしていない" "--base develop" "$_ii_body3"
out_hasnt "issue-implement: origin/main を直書きしていない" "origin/main" "$_ii_body3"
out_hasnt "issue-implement: description に develop 基点の旧文言が残っていない" "単発 issue を develop 基点" "$_ii_body3"
out_hasnt "issue-implement: 対話のシェルを閉じる || exit 1 が戻っていない" "|| exit 1" "$_ii_body3"
out_has   "issue-implement: 終了コード別に止める案内(1=聞く・3=宣言を直す)を if/case で分ける" 'case "$rc" in' "$_ii_body3"
out_has   "issue-implement: step 2 の \$base は別の Bash 呼び出しに残らない前提を明記" "別の Bash 呼び出しには残らない前提" "$_ii_body3"
out_has   "issue-implement: step 6 の直前でベースを解決し直す" "ここで同じ呼び方で解決し直す" "$_ii_body3"
out_has   "issue-implement: dispatch の投入指示にベースを明示して渡す" "投入指示に明示して渡す" "$_ii_body3"
out_has   "issue-implement: implementer は渡されたベースを --declared に使う" "渡されたベースを \`--declared\` に渡して解決する" "$_ii_body3"
out_has   "issue-create: ベースは導入先の既定ブランチ基点" "導入先の既定ブランチ基点" "$(cat "$H/skills/issue-create/SKILL.md" 2>/dev/null)"
out_hasnt "issue-create: develop 基点の旧文言が戻っていない" "（develop 基点）" "$(cat "$H/skills/issue-create/SKILL.md" 2>/dev/null)"
out_has   "document-profile: base ブランチの宣言の書式を project-profile 正本と同じ形で固定" '- **base ブランチ: `<名前>`**' "$(cat "$H/skills/document-profile/SKILL.md" 2>/dev/null)"
out_has   "code-reviewer: PR の向け先(gh pr view の baseRefName)を最優先にする" "gh pr view <番号> --json baseRefName -q .baseRefName" "$(cat "$H/agents/code-reviewer.md" 2>/dev/null)"
out_has   "code-reviewer: 次に dispatch で渡された base、最後に実行ファイルで解決する順" "どちらも無いときだけ" "$(cat "$H/agents/code-reviewer.md" 2>/dev/null)"
out_has   "issue-implement: step 6 のベース再解決が if の条件(コードの行)で、then 側が gh pr create" 'if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  # worktree' "$_ii_body3"
out_has   "issue-implement: step 6 の then 側の gh pr create が --base \$base" '  gh pr create --draft --base "$base" \' "$_ii_body3"
out_has   "issue-implement: step 6 の else 側で PR を作らず止める" "（PR は作らない）" "$_ii_body3"
out_hasnt "issue-implement: step 6 の失敗の扱い無しの裸の base= 代入が戻っていない" '
base="$(yosage-dev-harness-base-branch' "$_ii_body3"
out_has   "issue-implement: step 2 の git checkout -b 失敗時に止めて案内する" "ブランチ作成に失敗（同名のブランチが既にある等）" "$_ii_body3"
out_hasnt "change-lanes: Direct のブランチ起点が develop 決め打ちの旧文言が残っていない" "を develop から" "$(cat "$H/rules/change-lanes.md" 2>/dev/null)"
out_hasnt "implement-routing: 非 Epic の単発が develop 基点の旧文言が残っていない" "**develop 基点**で実装" "$(cat "$H/rules/implement-routing.md" 2>/dev/null)"
out_hasnt "code-reviewer: 差分の基準を origin/main に決め打ちしていない" "--merge-base origin/main" "$(cat "$H/agents/code-reviewer.md" 2>/dev/null)"
out_has   "code-reviewer: 差分の基準は dispatch で渡された base か実行ファイルで解決" "yosage-dev-harness-base-branch" "$(cat "$H/agents/code-reviewer.md" 2>/dev/null)"
out_has   "code-reviewer: ベースを決められないまま全体の差分で見たときは報告に明記する" "ベースを決められず、作業ツリー全体の差分でレビューした" "$(cat "$H/agents/code-reviewer.md" 2>/dev/null)"
out_has   "document-profile: GitHub の既定ブランチと PR の向け先・宣言の比較を調査に含める" "origin/HEAD" "$(cat "$H/skills/document-profile/SKILL.md" 2>/dev/null)"
_pk_body3="$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has   "promote-knowledge: ストアのブランチは設定 knowledge.ref に従う旨を明記" "ストアのブランチは設定 \`knowledge.ref\`（既定は \`main\`" "$_pk_body3"
out_hasnt "promote-knowledge: 特定ストアの事情に読める旧文言(develop を持たない)が残っていない" "develop\` ブランチを持たない" "$_pk_body3"

# 意味の単位(Sub-issue)と統合の単位を分け、Sub-issue PR の既定を develop(独立に取り込める形)にする。
# まとめて取り込む形(Epic ブランチ)は選択肢として残す。既定は導入先 profile で上書きできる。
# Closes # は既定ブランチへのマージでのみ発火する旨も明示する。
out_has "pr-loop.md: Sub-issue PR の取り込み先の既定は Epic ブランチと明記" "Sub-issue PR の取り込み先の既定は Epic ブランチ" "$_pl_body2"
out_has "pr-loop.md: 既定ブランチへ直接入れる例外は計画でハーネスが Sub-issue ごとに判断する旨を明記" "ハーネスが Sub-issue ごとに判断" "$_pl_body2"
out_has "pr-loop.md: 取り込み先は本文の「取り込み先: <どちらか>（理由）」に書く旨を明記" "取り込み先: <どちらか>（理由）" "$_pl_body2"
out_has "pr-loop.md: 実装の途中で変えるときは提案して Sub-issue に記録してから従う旨を明記" "理由とともに Sub-issue に記録してから従う。黙って変えない" "$_pl_body2"
out_hasnt "pr-loop.md: Sub-issue PR の既定を既定ブランチとする旧文言が残っていない" "Sub-issue PR の既定は develop" "$_pl_body2"
out_has "pr-loop.md: epic ブランチが選択肢として残っている(既存運用が失われていない)" "epic/<name>" "$_pl_body2"
out_has "pr-loop.md: repo ごとの既定を project-profile で上書きできる旨を明記" "project-profile" "$_pl_body2"
out_has "pr-loop.md: PR 本文の Closes # は既定ブランチ向けの PR でしか解釈されない旨を明記" "既定ブランチ向けの PR でしか解釈されない" "$_pl_body2"
out_has "pr-loop.md: Epic ブランチ向けの PR 本文は「Part of #<Epic>」を書く旨を明記" "「Part of #<Epic>」と Sub-issue への参照" "$_pl_body2"
out_has "pr-loop.md: Sub-issue は取り込みを確かめた時点で統制側が PR リンク付きで明示的に閉じる旨を明記" "マージされた PR へのリンクを添えて明示的に閉じる" "$_pl_body2"
out_has "pr-loop.md: コミット末尾の Closes # は残す旨を明記" "コミット末尾の \`Closes #<Sub-issue>\` は残す" "$_pl_body2"
out_has "pr-loop.md: Epic の PR は draft で作る旨を明記" "Epic の PR は draft で作る" "$_pl_body2"
out_has "pr-loop.md: Epic の完了時の状態は epic-implement 手順8を名前参照する(再記述しない)" "正本は \`epic-implement\` 手順8" "$_pl_body2"
out_hasnt "pr-loop.md: Sub-issue PR が epic ブランチ固定だった旧文言が残っていない" " / Sub-issue PR → " "$_pl_body2"

_cl_body2="$(cat "$H/rules/change-lanes.md" 2>/dev/null)"
out_has "change-lanes.md: レーン定義に「独立に取り込めるか」の軸を明記" "独立に取り込めるか" "$_cl_body2"
out_has "change-lanes.md: 分割基準の実体は epic-create-docs への名前参照に留める" "epic-create-docs" "$_cl_body2"
out_hasnt "change-lanes.md: epic-create-docs の分割基準の実体(独立に検証できるか)を再記述していない" "独立に検証できるか" "$_cl_body2"

_eci_body="$(cat "$H/skills/epic-create-issues/SKILL.md" 2>/dev/null)"
out_has "epic-create-issues: ラベル正本(配布の github/labels.json)を参照" "github/labels.json" "$_eci_body"

_ic_body="$(cat "$H/skills/issue-create/SKILL.md" 2>/dev/null)"
out_has "issue-create: ラベル正本(配布の github/labels.json)を参照" "github/labels.json" "$_ic_body"

# 配布物(harness/ 配下すべて)の `.docs/` への参照が、導入先の側にある文書(配布物が導入先に作らせる・
# 読ませる文書)だけであることを、許す側の一覧で確かめる regression ラチェット。一覧に無い名前
# (=このリポジトリの外にある非公開の開発文書を指す参照)が1つでも出れば落ちる。落とす側の名前を
# 並べない形にして、非公開の文書の名前が公開面に残らないようにしている。
# 許す一覧は `.docs/` 直下の最初の要素(ファイル名は拡張子まで、ディレクトリは名前だけ):
#   architecture / detail / api / ui = 生きた設計文書の置き場(sync-design-docs・document-architecture が案内)
#   glossary.md / proposal.md = 導入先が持つ語彙・提案書
# この一覧の名前は、非公開の開発文書の置き場の名前と重ならないこと(重なると、その置き場への参照を見逃す)。
hod_allow='^(architecture|detail|api|ui|glossary\.md|proposal\.md)$'
hod_fail=0
while IFS= read -r hod_hit; do
  [ -n "$hod_hit" ] || continue
  hod_file="${hod_hit%%:*}"; hod_ref="${hod_hit#*:}"; hod_name="${hod_ref#.docs/}"
  if ! printf '%s' "$hod_name" | grep -qE "$hod_allow"; then
    ng "配布物が許す一覧に無い .docs/ 配下の参照を持つ: [.docs/${hod_name}] in ${hod_file#$H/}"; hod_fail=1
  fi
done < <(grep -rnoE '\.docs/[A-Za-z0-9_-]+(\.md)?' "$H" 2>/dev/null | sed -E 's/^([^:]+):[0-9]+:/\1:/' | sort -u)
[ "$hod_fail" = "0" ] && ok "配布物の .docs/ への参照は、導入先の側の文書(許す一覧)だけ"

echo "== visual-design skill / visual-design-routing rule =="
file_is "skill: visual-design が存在" "$H/skills/visual-design/SKILL.md"
_vd_body="$(cat "$H/skills/visual-design/SKILL.md" 2>/dev/null)"
out_has "visual-design: 視覚デザインの二義性の正本を visual-design-routing へ名前参照" "visual-design-routing" "$_vd_body"
out_has "visual-design: トークン系(色/書体/レイアウト/signature)を先に立てる工程を明記" "トークン系を先に立てる" "$_vd_body"
out_has "visual-design: 色は4-6個のnamed hexで記述する旨を明記" "4〜6個の named hex" "$_vd_body"
out_has "visual-design: 書体は最低2ロール(display/body)を明記" "最低2ロール" "$_vd_body"
out_has "visual-design: 既定解批評ゲートを明記" "既定解に一致し" "$_vd_body"
out_has "visual-design: 品質フロア(モバイルレスポンシブ)を明記" "モバイルまでレスポンシブ" "$_vd_body"
out_has "visual-design: 品質フロア(prefers-reduced-motion)を明記" "prefers-reduced-motion" "$_vd_body"
out_has "visual-design: layered recall で recall-knowledge を名前参照" "recall-knowledge" "$_vd_body"
out_has "visual-design: capture-learning を名前参照" "capture-learning" "$_vd_body"
out_has "visual-design: ui/ domain へ capture する旨を明記" "\`ui/\` domain" "$_vd_body"
out_has "visual-design: 討議儀式を踏まない旨を明記" "討議儀式を踏まない" "$_vd_body"
out_has "visual-design: WCAG コントラスト比を✓外部で一次出典つき引用" "w3.org/WAI/WCAG22" "$_vd_body"
out_has "visual-design: DTCG デザイントークン3層を✓外部で一次出典つき引用" "designtokens.org/tr/2025.10/format" "$_vd_body"
out_has "visual-design: frontend-design プラグインへの帰属を明記" "frontend-design" "$_vd_body"
out_has "visual-design: 逐語コピーでない旨を明記" "逐語コピーではない" "$_vd_body"
out_has "visual-design: 正本確定前に人間の視覚確認を得る必須ステップを明記" "人間へ提示して明示的な確認を得てから" "$_vd_body"
out_has "visual-design: 過剰適用を防ぐ限定条件(正本として確定させる場面に限る)を明記" "正本として確定させる場面に限定する" "$_vd_body"
out_hasnt "visual-design: home repo 固有の issue 番号を含まない(travel面の自己完結)" "yosage-dev-harness#" "$_vd_body"
out_hasnt "visual-design: 非配布パス(.docs/)を参照しない(travel面の自己完結)" ".docs/" "$_vd_body"

# follow-up: レンダリング手段が無い consumer 向けの任意化条件を、委譲先ワーカー個体が
# 手段を持たないだけの場合(dispatch元は持つ)に誤って適用しない旨を明記する。
out_has "visual-design: 任意化条件を委譲先ワーカー個体の手段欠如に誤適用しない旨を明記" "誤って適用しない" "$_vd_body"
out_has "visual-design: 委譲先ワーカーが満たせない場合の扱いを implementer へ名前参照(裸の名前・パス無し)" "扱いは \`yosage-dev-harness:implementer\`（正本へ確定する前に停止し" "$_vd_body"
out_hasnt "visual-design: implementer 参照にパス付き括弧書きが残っていない" "\`implementer\`（\`.claude/agents/implementer.md\`" "$_vd_body"

file_is "rule: visual-design-routing.md が存在" "$H/rules/visual-design-routing.md"
_vdr_body="$(cat "$H/rules/visual-design-routing.md" 2>/dev/null)"
out_has "正本 visual-design-routing.md が存在" "visual-design-routing（不変条件）" "$_vdr_body"
out_hasnt "visual-design-routing: ルール管理についての冒頭の注記(常時オン等)は受け取る側には出さない(撤去済み)" "常時オン" "$_vdr_body"
out_has "visual-design-routing: designの二義性(ソフトウェア設計/視覚デザイン)を明記" "ソフトウェア設計" "$_vdr_body"
out_has "visual-design-routing: 視覚デザインの定義を明記" "視覚デザイン" "$_vdr_body"
out_has "visual-design-routing: 境界のグレーゾーン切り分け例を明記" "境界のグレーゾーン" "$_vdr_body"
out_has "visual-design-routing: deliberate-designの討議儀式を踏まない旨を明記" "討議儀式を踏まない" "$_vdr_body"
out_has "visual-design-routing: knowledge フック(recall/capture)を名前参照" "recall-knowledge" "$_vdr_body"

out_has "design-routing: visual-design-routing へのフォークポインタを明記" "visual-design-routing" "$(cat "$H/rules/design-routing.md" 2>/dev/null)"

echo "== project-profile rule: 導入先固有座標(利用者所有) と harness 由来ルール(harness所有)の所有権境界 =="
file_is "rule: project-profile.md が存在" "$H/rules/project-profile.md"
_pp_body="$(cat "$H/rules/project-profile.md" 2>/dev/null)"
out_has "正本 project-profile.md が存在"                 "project-profile（不変条件）"                     "$_pp_body"
out_has "project-profile: 利用者所有の profile 置き場を明記" ".claude/rules/<名前>/profile.md"                "$_pp_body"
out_has "project-profile: harness 由来ルールはプラグインの中で注入される旨を明記" "SessionStart" "$_pp_body"
out_has "project-profile: install/updateが自動生成・上書きしない旨を明記" "自動生成・上書きすることはない"       "$_pp_body"
out_has "project-profile: 明示起動のdocument-profile skillが下書きする旨を明記(名前参照)" "document-profile\` skill" "$_pp_body"
out_has "project-profile: 着火は常に人間トリガである旨を明記" "着火は常に人間トリガ"                            "$_pp_body"
out_has "project-profile: document-profileへ名前参照(再記述しない)" "[[document-profile]]" "$_pp_body"

# 一次レビュー Must 回帰防止: profile の例示にドメイン語彙/ディレクトリ構成を含めない
# (それぞれ glossary skill / document-architecture skill が正本を .docs/ に持つため、常時オン rule 側で
# 「profile に置け」と言うと既存 skill の「.docs/ に正本化しろ」と意味的に衝突する)。
out_hasnt "project-profile: 導入先固有座標の例示にドメイン語彙/ディレクトリ構成を含めない(既存正本skillとの衝突回避)" "ディレクトリ構成・ドメイン語彙" "$_pp_body"
out_has "project-profile: .docs/ に正本がある事項は profile に重複させない旨を明記" "profile に重複させない" "$_pp_body"
out_has "project-profile: ドメイン語彙は glossary skill が正本と明記" "glossary\` skill" "$_pp_body"
out_has "project-profile: ディレクトリ構成/アーキテクチャは document-architecture skill が正本と明記" "document-architecture\` skill" "$_pp_body"

# librarian.md の引用先が project-profile ではなく issue-discipline の「repo 外参照を禁止」節を指すことを確認
# (本 rule 自体は所有権の境界だけを扱い、repo 外参照の是非には触れないため引用先はこちらではない)。
_lib_body="$(cat "$H/agents/librarian.md" 2>/dev/null)"
out_has   "librarian: issue-discipline の「repo 外参照を禁止」節への引用に差し替え済み" "issue-discipline\` の「repo 外参照を禁止」節" "$_lib_body"
out_hasnt "librarian: CLAUDE.md への旧引用が残っていない" "CLAUDE.md の「repo 成果物は repo 外パスを参照しない」" "$_lib_body"

# README: profile の書き方の詳細(差分だけを持つ・ワークフローは汎用skill/agentへ流す)を明記
_readme_body="$(cat "$ROOT/README.md" 2>/dev/null)"
out_has "README: profile は差分だけを持つ旨を明記"                 "profile は差分だけを持つ"                     "$_readme_body"
out_has "README: ワークフローは汎用skill/agentへ流す旨を明記"       "harness の汎用 skill / agent に流す"          "$_readme_body"
out_has "README: project-profile.md への所有権境界の正本ポインタ"  "project-profile\`（常時オン）が正本"       "$_readme_body"
out_hasnt "README: profile の例示にドメイン語彙/ディレクトリ構成を含めない(既存正本skillとの衝突回避)" "ディレクトリ構成・ドメイン語彙" "$_readme_body"
out_has "README: profile の書き方に .docs/ 正本との重複回避を明記" "重複させない" "$_readme_body"

echo "== document-profile skill (profile.md を起こす/鮮度チェックする明示実行スキル) =="
file_is "skill: document-profile が存在" "$H/skills/document-profile/SKILL.md"
_dp_body="$(cat "$H/skills/document-profile/SKILL.md" 2>/dev/null)"
out_has "document-profile: 明示実行のみ(disable-model-invocation)" "disable-model-invocation: true" "$_dp_body"
out_has "document-profile: argument-hintにrefreshを持つ" 'argument-hint: "[refresh]"' "$_dp_body"
out_has "document-profile: モード1(新規作成)の見出しを持つ" "## モード1: 新規作成" "$_dp_body"
out_has "document-profile: モード2(鮮度チェック)の見出しを持つ" "## モード2: 鮮度チェック" "$_dp_body"
out_has "document-profile: 新規作成モードは利用者確認を経ずに書き出さない" "利用者の確認を経ずにファイルを書き出さない" "$_dp_body"
out_has "document-profile: 鮮度チェックはズレを列挙するだけで自動修正しない" "自動では直さない" "$_dp_body"
out_has "document-profile: .docs/正本(glossary)との重複除外を明記" "glossary\`（ドメイン語彙の正本）" "$_dp_body"
out_has "document-profile: .docs/正本(document-architecture)との重複除外を明記" "document-architecture\`（ディレクトリ構成/アーキテクチャの正本）" "$_dp_body"
out_has "document-profile: profileの置き場はワークスペース側に限る(メンバーrepo自身には置かない)" "メンバー repo 自身の \`.claude/rules/\` には置かない" "$_dp_body"
out_has "document-profile: 生成するprofileにpaths: frontmatterを付けない(常時オン)" "\`paths:\` frontmatter は付けない" "$_dp_body"
out_has "document-profile: workspace/member判定はconfig-get.shの値で行う" "yosage-dev-harness-config-get workspace\` の値" "$_dp_body"
out_has "document-profile: project-profile正本への名前参照" "project-profile\` 正本" "$_dp_body"
# 正本一元化: project-profile.md が持つ重複除外の具体的な括弧書き例示(例: ドメイン語彙は…)を
# skill 側が逐語コピーしていないこと(fp-fingerprint-test-misses-verbatim-enumeration-drift 回帰対策)。
out_hasnt "document-profile: project-profileの括弧書き例示(例: ドメイン語彙は…)を逐語コピーしていない" "例: ドメイン語彙は \`glossary\` skill、" "$_dp_body"

echo "== harness-help skill: travel 面の自己完結(home-repo固有のパス参照を持ち込まない) =="
hh="$H/skills/harness-help/SKILL.md"
file_is "harness-help skill が存在" "$hh"
out_has "harness-help: description に frontmatter あり" "name: harness-help" "$(cat "$hh" 2>/dev/null)"
# catalog-gen.sh はプラグイン化で harness/lib/ から撤去済み(消費側に生成手段が無い)。
# harness-help はその古い手順を案内していた(死んだ参照)ため、案内先を次節のルーティング表へ
# 差し替えた。この節はその案内が実在することだけを確認する(死んだコマンド例を復活させない)。
out_has   "harness-help: 今何が使えるかの案内を含む(ライブ生成コマンドの死んだ案内を持たない)" "今何が使えるか" "$(cat "$hh" 2>/dev/null)"
out_hasnt "harness-help: 撤去済みの .claude/lib/catalog-gen.sh 呼び出しを再掲していない" "catalog-gen.sh" "$(cat "$hh" 2>/dev/null)"
out_has   "harness-help: タスク→skill ルーティング表を含む" "issue-implement" "$(cat "$hh" 2>/dev/null)"
# follow-up: ルーティング表の epic-implement-subissue 行が既定(develop)/選択(まとめる場合のみ epic)を明記
out_has   "harness-help: epic-implement-subissue 行に取り込み先は Sub-issue 本文に従う(既定は epic ブランチ)を明記" "既定は epic ブランチ、例外は導入先の既定ブランチ" "$(cat "$hh" 2>/dev/null)"
out_hasnt "harness-help: epic-implement-subissue 行が epic ブランチ基点固定という旧文言のみに戻っていない" "\`epic-implement-subissue\` | epic ブランチ基点で実装する" "$(cat "$hh" 2>/dev/null)"


echo "== 人間に打たせる案内: スラッシュコマンドに名前空間(/yosage-dev-harness:)が付いている =="
# スキル名の一覧は harness/skills/ から導く(手書きの一覧を持たない)。payload(harness/)と README の
# どこにも、名前空間の無い /<スキル名>(前が英数字・: ・/ ・. ・- 以外)が無いこと。
# ファイルパスの一部(例 skills/<名前>/)は直前が英数字・/ なので一致しない。
# 判定関数 _ns_scan <パターン> <走査対象...>: 一致あり=0(出力に一致行)・一致なし=1・grep の失敗=2 を返す。
# 走査対象が実在しない場合も失敗(2)にする(失敗を「一致なし」と取り違えない)。
_ns_scan() {
  local pat="$1" t; shift
  for t in "$@"; do [ -e "$t" ] || { echo "走査対象が無い: $t"; return 2; }; done
  local out rc=0
  out="$(grep -rnE "$pat" "$@" | cut -c1-160; exit "${PIPESTATUS[0]}")" || rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac
}
_ns_names="$(ls "$H/skills" | paste -sd'|' -)"
_ns_pat="(^|[^[:alnum:]_:/.-])/($_ns_names)([^[:alnum:]_-]|\$)"
_ns_out="$(_ns_scan "$_ns_pat" "$H" "$ROOT/README.md")"; _ns_rc=$?
if [ -z "$_ns_names" ]; then
  ng "スキル名の一覧が空(harness/skills/ が読めない)"
elif [ "$_ns_rc" = 1 ]; then
  ok "名前空間の無い /<スキル名> の案内が payload・README に無い"
elif [ "$_ns_rc" = 0 ]; then
  ng "名前空間の無い /<スキル名> の案内が残っている: $(echo "$_ns_out" | tr '\n' ' ')"
else
  ng "名前空間の検査が実行できない(grep の失敗・走査対象なし): $_ns_out"
fi
# 正の対照: 同じ判定関数が、名前空間なしだけを検出し、ありは検出しないこと(常に「なし」を返す空振りの防止)。
_ns_tmp="$(mktemp -d "$ROOT/test/scratch.XXXXXXXX")"
printf '%s\n' '打たせる案内: `/setup` を実行' > "$_ns_tmp/bad.md"
printf '%s\n' '打たせる案内: `/yosage-dev-harness:setup` を実行' > "$_ns_tmp/good.md"
_ns_scan "$_ns_pat" "$_ns_tmp/bad.md" >/dev/null; _ns_bad_rc=$?
_ns_scan "$_ns_pat" "$_ns_tmp/good.md" >/dev/null; _ns_good_rc=$?
rm -rf "$_ns_tmp"
[ "$_ns_bad_rc" = 0 ] && ok "名前空間検査の対照: 名前空間なしの /setup を検出する" || ng "名前空間検査の対照: /setup を検出できない(rc=$_ns_bad_rc)"
[ "$_ns_good_rc" = 1 ] && ok "名前空間検査の対照: 名前空間つきは検出しない" || ng "名前空間検査の対照: 名前空間つきを誤検出(rc=$_ns_good_rc)"
