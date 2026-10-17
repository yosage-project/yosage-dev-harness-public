---
name: epic-review
description: Epic ブランチ向けの PR をレビューする（マージは実行しない。人間にマージを促す）。epic-implement と並行して使用可能。
argument-hint: "<epic-issue-number> | <owner>/<repo>#<epic-issue-number>"
allowed-tools: Bash(yosage-dev-harness-gh-issue-resolve *)
---

# Review Epic PRs Skill

Epic ブランチ向けの open PR をレビューし、`gh pr ready` 済みの PR URL と確認すべき点を人間に提示する（マージは実行しない。マージは人間が自分の手で行う）。
`epic-implement` が PR を作成している間に並行してレビュー作業を進める用途。

## 動的コンテキスト

Epic Issue の内容:

!`yosage-dev-harness-gh-issue-resolve "$ARGUMENTS"`

## 手順

### 1. Epic 情報の確認

動的コンテキストから以下を把握する:

- Epic ブランチ名（本文や既存ブランチから特定）
- Sub-issues の一覧とスコープ

Epic ブランチ名が不明な場合:

```bash
git branch -r | grep 'epic/'
```

### 2. Open PR の一覧取得（Epic の Sub-issue の一覧から引く）

`gh pr list --base epic/<epic-name>` だけでは、直列に積んだ PR（base が先行 Sub-issue のブランチ）や、既定ブランチへ
直接入れる例外の PR を取りこぼす。**Epic の Sub-issue の一覧**（`gh issue view <Epic>` のチェックリスト、または
ネイティブ sub-issue の紐づけ）から、各 Sub-issue の open PR を引く:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  # <sub> は Sub-issue の番号。本文に Sub-issue への参照を持つ open PR のうち、
  # Epic の PR（head が epic/<epic-name>）と同期の PR（head が既定ブランチ）を除く
  gh pr list --state open --limit 200 --json number,title,baseRefName,headRefName,isDraft,body \
    | jq --arg epic "epic/<epic-name>" --arg base "$base" '
        .[] | select(.headRefName != $epic and .headRefName != $base)
            | select(.body | test("#<sub>([^0-9]|$)"))'
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

- 引けた PR の base（Epic ブランチ・先行 Sub-issue のブランチ・既定ブランチ）はそのまま記録し、報告に添える。
- Epic の PR（head が `epic/<epic-name>`、起票時または最初の取り込み時に draft で作られるもの）は Sub-issue の PR ではない。
  この手順の対象にせず、手順 5 の報告に Epic の PR の URL を添えて、完了の確認（`epic-implement` 手順7・8）へつなぐ。
- 全 Sub-issue について open PR がなければ完了を報告して終了。

### 3. 各 PR のレビュー

各 PR について以下を確認する:

#### 3a. コンフリクトチェック

```bash
gh pr view <pr_number> --json mergeable -q '.mergeable'
```

- **CONFLICTING** → コンフリクト解消を実施（手順 4）→ 解消後に再レビュー
- **MERGEABLE** → レビューに進む

#### 3b. diff の確認

```bash
gh pr diff <pr_number>
```

#### 3c. 対応する Issue の要件を確認

PR 本文の「Part of #<Epic>」と Sub-issue への参照（Epic ブランチ向け。既定ブランチへ直接入れる例外の PR は
`Closes #<number>`。コミット末尾の `Closes #<number>` も手がかり）から Issue 番号を特定し、要件と照合:

```bash
gh issue view <issue_number>
```

#### 3d. レビュー判定

以下の基準で判定する:

**マージ推奨（全て満たす場合）:**
- Issue の実装内容と diff が一致している
- 機械的な変更が中心（import 追加、定数参照化、リネーム等）
- 予期しないファイルの変更がない
- ロジック変更を含まない

**要確認（いずれかに該当）:**
- Issue の要件と diff に乖離がある
- 予期しないファイルが変更されている
- ロジック変更を含む
- 判断に迷う点がある

#### 3e. ドキュメント影響の記録確認（実更新は Epic 完了時）
- PR 本文に **`Docs-impact:`** 行があるか確認（無ければ記載を求める）。
- sub-issue PR では `.docs/` の実体更新は**求めない**（途中更新は後続で覆って手戻りになりやすい）。
  実更新と取りこぼし検知は **Epic 完了時（既定ブランチへの Epic PR の前）** に `doc-drift-check.sh` ＋ `sync-design-docs` でまとめて行う。

### 4. コンフリクト解消

コンフリクトがある PR は以下の手順で解消する:

```bash
git fetch origin
git checkout <pr-branch>
git merge origin/epic/<epic-name>
# コンフリクトを解消
git add <resolved-files>
git commit -m "merge: epic/<epic-name> とのコンフリクトを解消"
git push origin <pr-branch>
```

解消後、手順 3 に戻って再レビュー。

### 5. レビュー結果の報告

全 PR のレビューが完了したら、判定結果を人間に提示して終了する（**マージは実行しない**）。
「マージ推奨」と判定した PR がまだ draft のままなら `gh pr ready <pr_number>` で draft を解除してから提示する。
Epic の PR（head が `epic/<epic-name>`、draft）があれば、その URL を報告に添え、Sub-issue の PR がすべて取り込まれた後の完了の確認は `epic-implement` 手順7・8で行う旨を案内する（本 skill では Epic の PR を ready にもマージにもしない）。

```
## レビュー結果

### マージ推奨（ready 済み・人間の確認待ち）
- [ ] #<pr_number> <タイトル> — <PR URL>

### 要確認
- [ ] #<pr_number> <タイトル> — <確認が必要な理由>

### 未レビュー（open PR なし）
<該当なしの場合>
```

## 注意事項

- `epic-implement` と並行して実行することを想定。実装中の PR（まだ push されていない）はレビュー対象外
- コンフリクト解消は自動で行うが、解消内容が複雑な場合はユーザーに確認する
- **本 skill はレビュー・報告までで終了する**。マージは人間が自分の手で行う（正本: ルール `pr-loop`）。マージ戦略・コミット規約の正本はルール `pr-loop` / `commit`。
- 設計変更を含む PR は `.docs/` の同期（手順 3e）を確認してから提示する
- マージ順序に依存する Sub-issue がある場合は、報告にその旨を明記する
- 判断に迷ったら安全側に倒してユーザーに確認する
- **レビューの学びを capture**: 繰り返し出る指摘・「やってみて判明した」観点は、レビュー実施者が [[capture-learning]] で蓄積する（繰り返す指摘は `review/criteria` 観点へ。グローバル昇格の既定・経路は [[capture-learning]]、誰が回すかは ルール `knowledge`）。
