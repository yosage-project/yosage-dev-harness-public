---
name: recall-knowledge
description: 作業・設計・レビューの前に、蓄積された知識ベースから「今の作業に関連するものだけ」を選り分けて読み込むスキル(司書役)。膨大な知識を全部読まず、project-local はエントリを直接列挙(索引には依存しない)、global は索引で domain/tags を絞って必要なエントリだけ貸し出す。設計判断を固める前、ドメイン固有の判断が必要なとき、レビュー観点を揃えるときに使う。蓄積側は capture-learning。
---

# recall-knowledge — 必要な知識だけ選り分けて貸し出す（司書）

知識は膨大になる前提。**全部は読まない**。今の作業に関連するエントリだけを選んで読む（just-in-time）。
knowledge loop（recall は前半・capture は後半）は ルール `knowledge`、蓄積は [[capture-learning]]。

## 既定: 司書 subagent (`yosage-dev-harness:librarian`) に委譲
知識はすぐ膨大になるので、**既定では `yosage-dev-harness:librarian` サブエージェントに頼む**:
- worker は「**domain ＋ 問い（何を判断したいか）**」を渡す。
- yosage-dev-harness:librarian が隔離文脈でエントリを選り分け、**digest（要約）＋ references（id/パス一覧）** を返す。project-local は索引ファイルを介さず `knowledge-index.sh --list`（索引を持たない理由は ルール `knowledge` の「ローカル索引は任意のキャッシュ」節）で直接列挙、global は sync 済み索引を引く。範囲は**方向つき**（workspace/orchestrator セッションは自ストア＋global＋各 member repo でも同じ直接列挙／member セッションは自ストア＋global のみ。判定・詳細は `yosage-dev-harness:librarian` 手順1）。
- worker は digest を判断に反映し、必要なら references のパスを**自分で読む**（大量の本文を自分の文脈に載せない）。
- digest の各項目には**鮮度判定（`✓接地確認` / `⚠要確認` / `✗陳腐化`）**が付く。`⚠/✗` は鵜呑みにせず、付帯の `修正案` を使って **fix-on-recall**（[[capture-learning]]）で直す（軽い=その場で supersede／重い=follow-up issue）。
- digest に `⇧昇格候補` が付いた項目があれば、**promote-on-recall**（[[capture-learning]]）に従い `scope: global` マークを実行する（ストアへの昇格は既定でここでは行わない。明示実行の `promote-knowledge`（別スキル）を別途使う）。`⇧staging未PR` が付いた項目（既に `scope: global` の staging 済み entry）は、[[capture-learning]] の staging drain 規律に従い `promote-knowledge` でストアへ PR する。

## 軽量: 自分で直接列挙する（単発・ごく小規模のとき）
1件だけ確認したい等の軽い用途は inline で:
1. domain/tags を決める。
2. project-local は索引を読まず `yosage-dev-harness-knowledge-index ".claude/knowledge" --list` で直接列挙し、返った行を `rg`/`grep` で絞る（識別子＋1行要約＋path で当たり。退役分も要るなら `--list-archive`。置き場は `.claude/knowledge` に固定（置き場を変える機能は撤去済み））。**コマンドの終了コードを確認する**: 非ゼロ終了は「関連知見なし」と誤認せず、その場で停止して報告する（同ルール「列挙の失敗を『0件』と誤認しない」節）。global は同期された `.claude/knowledge/global/INDEX.md`（あれば）を `rg`/`grep` で絞る。**workspace（複数 repo 同居の親ディレクトリ）で動いているときだけ**、各 member repo でも同じ直接列挙を行う（member セッション＝子 repo に `cd` して作業中は自ストア＋global のみで member への列挙を行わない。方向つきスコープの詳細は `yosage-dev-harness:librarian` 手順1）。
3. 当たったエントリのみ Read（`--list`/`global/INDEX.md` は `status: superseded`/`archived` を除外済み。新しい date 優先）。
4. 蒸留層 `review/criteria.md` ＋ `.claude/yosage-dev-harness-review-criteria.md` も確認。
5. 引いたエントリの根拠ハンドルを `rg --no-ignore`/`command grep` で軽く再解決し、在/不在を確認する（グローバルミラーやローカル索引は gitignore 対象で、既定の `rg`/`grep` は gitignore を尊重して黙って除外するため、gitignore された領域も対象に含める。構造的確認のみ。意味的な陳腐化を疑うなら `yosage-dev-harness:librarian` に委譲。腐っていれば fix-on-recall ＝ [[capture-learning]]）。

## 外部知識を just-in-time に引く（言語定石・アーキ・原理原則）
内部知見だけで足りないとき、外部（言語の定石・公式 doc・原理原則）を `yosage-dev-harness:researcher` で引くのも recall の一形態。**引くのは次の3条件が揃ったときだけ**＝「内部知見が薄い × 判断の要 × 一般定石で自信がない」。モデルが既に持っている一般論は引かない（**反射的検索の禁止**。引くほど過信 recall を量で再発させる）。

積極性は「確立済みか / 新規か」で変える:
- **確立済みアーキへの変更**（先例がプロジェクトに在る）→ 内部先行（`yosage-dev-harness:librarian`）。外部は踏襲中に出た新しい枝問だけ。**保守的**。
- **新規 / greenfield / 新サブシステム**（これから規約を据える）→ 外部を厚めに引く。**積極的**。設計フェーズ（`yosage-dev-harness:architect`）では外部定石の**要否を明示的に判断**する（引く/引かないを決め、素通ししない）。
- 引いた結果のうち**残す価値のある差分だけ**を知見化する（何を残すかは [[capture-learning]] の価値ゲート）。外部エントリの出所・鮮度は `source:`＋`checked:`（`yosage-dev-harness:librarian` が recall 時に経過で鮮度判定）。

## 原則
- **全部読まない**: 直接列挙/索引 → 関連のみ。コンテキストは有限資源。
- **既定は委譲**: 膨大化に備え、基本は `yosage-dev-harness:librarian` に digest＋references を作らせ、worker の文脈を守る。軽量 inline は単発のみ。
- **新しい・有効を優先**: `status: active` かつ date の新しいものを優先、`superseded`/`archived` は無視。
- **取り寄せたら使う**: recall して終わりにせず、判断に反映する。
