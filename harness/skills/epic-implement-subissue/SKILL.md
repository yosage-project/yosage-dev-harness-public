---
name: epic-implement-subissue
description: Epic 配下の Sub-issue を実装するレーン。PR の取り込み先は Sub-issue の本文の「取り込み先」（既定は Epic ブランチ、例外は導入先の既定ブランチ。pr-loop.md の規則）。名指し1件なら yosage-dev-harness:implementer に dispatch して1件だけ実装→コミット→draft PR。単発(非Epic)は issue-implement。epic-implement 経由では yosage-dev-harness:implementer がこの手順を踏む。
argument-hint: "<issue-number> | <owner>/<repo>#<issue-number>"
allowed-tools: Bash(yosage-dev-harness-gh-issue-resolve *)
---

# Implement Sub-issue Skill

Epic 配下の Sub-issue を実装するレーン（[[issue-implement]] の epic 版）。**PR の取り込み先（ベースブランチ）は
Sub-issue の本文の `## 取り込み先`**（既定は Epic ブランチ。独立に取り込めて先に出す事情がある例外だけ、導入先の既定ブランチ）——
規則はルール `pr-loop` の「ベースブランチ / クローズ / マージ」節に従う（本 skill では再記述しない）。
取り込み先は計画の時点でハーネスが判断して本文に記録済み。実装投入を差配する側が dispatch 時に base を明示して渡す
（直列に積むときは先行 Sub-issue のブランチ）。
レーンの選び方と「メインは実装せず dispatch」の正本は **ルール `implement-routing`**（常時オン）。

**名指し1件は1件だけ**（指した粒度がレーンの粒度）。Sub-issue #M を「実装して」と言われても**親 Epic 全体を勝手に一括起動しない**（全体オーケストレーションは `/yosage-dev-harness:epic-implement <N>` の人間トリガ＝[[epic-implement]]）。**未マージの兄弟依存**があれば、黙って進めず・一括起動もせず surface して確認する。

実装は `yosage-dev-harness:implementer` に dispatch（メインは統制・監視は agent-watchdog）。下の手順は dispatch された yosage-dev-harness:implementer が worktree で踏む（`epic-implement` 経由でも同じ手順）。

## 動的コンテキスト

Issue の内容:

!`yosage-dev-harness-gh-issue-resolve "$ARGUMENTS"`

## 手順

### 1. Issue 内容の解析

上記の Issue 内容から以下を特定する:

- **Epic 番号**: 本文の「依存関係」セクションや親 Issue のリンクから特定
- **Epic ブランチ名**: `epic/<epic名>` 形式
- **実装内容**: 本文の「実装内容」セクション
- **検証方法**: 本文の「検証方法」セクション（あれば）

Epic ブランチ名が不明な場合は、以下で確認する:

```bash
gh issue view <epic_number> --json body -q '.body'
```

または既存ブランチから推測:

```bash
git branch -r | grep 'epic/'
```

次に**実装入口 OQ ゲートを踏む**（ルール `implement-routing` 「実装入口 OQ ゲート」節）。

### 2. ブランチ作成

**ベースブランチ**は Sub-issue の本文の `## 取り込み先` に従う（dispatch 時に明示された base があればそれを優先する）:

- **Epic ブランチ向け**: `origin/epic/<epic名>`（直列に積むときは dispatch 時に指示された先行 Sub-issue のブランチ）。
- **既定ブランチ向け（例外）**: 解決した既定ブランチ。投入側が渡した値を使い、渡されていなければ
  `yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>` で解決する
  （解決の順と終了コードの扱いは ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節）。

```bash
git fetch origin
git checkout origin/<ベースブランチ> -b <sub-issue-branch>
```

**取り込み先を途中で変えたくなったら、自分では変えない**。統制側へ「変更の提案（理由つき）」を返して止まる。統制側が
理由とともに Sub-issue に記録してから従う（黙って変えない）。

**ブランチ命名規則**: Issue タイトルから適切なプレフィックスを選択（type と一致）
- `feat/` — 新機能 / `fix/` — バグ修正 / `refactor/` — リファクタリング
- `chore/` — 設定・CI・依存関係等 / `docs/` — ドキュメント / `test/` — テスト / `perf/` — 性能改善

例: Issue タイトルが「ユーザー API のバリデーション追加」→ `feat/user-api-validation`

### 3. 接地（recall）→ 実装

書き始める前に [[grounded-design]]（既定。単発の知識照会だけなら [[recall-knowledge]] 単独）で**このドメインの過去の判断・落とし穴を recall**（接地）してから、Issue 本文の「実装内容」セクションに従って実装する。

- CLAUDE.md のコーディング規約に従う
- 既存コードのパターンを踏襲する
- 必要に応じて対象ファイル以外も修正する
- **knowledge loop に従う**（ルール `knowledge`）: 実装は `epic-implement` 経由でも名指し1件でも `yosage-dev-harness:implementer` に dispatch され、その `yosage-dev-harness:implementer` が recall→capture を内包する。

### 4. 検証

Issue 本文に「検証方法」が記載されていれば実行する。

```bash
# 例: テスト実行
# 例: 型チェック
# 例: lint
```

### 5. コミット

commit 前に **`sensitive-data` ルール**（ルール `sensitive-data`）の secret/PII チェックを踏む。

コミットは **commit 規約に従う**（ルール `commit` — 常時オンの正本）。

`Closes #` には**常に bare な issue 番号のみ**を書く（GitHub の自動クローズ構文は `Closes #<数字>` のみを認識する）。
`$ARGUMENTS` が `<owner>/<repo>#<N>` 形式(ワークスペースでは必須)のときは、末尾の `#` の後ろの `<N>` 部分
だけを取り出して使う（`<owner>/<repo>#<N>` を丸ごと `Closes #` の後ろに貼らない）。以下の 5・6 で同様。

```bash
git add <変更ファイル>
git commit -m "<type>(<scope>): <要約>

Closes #<issue番号>"
```
**`Co-Authored-By` 署名トレーラの要否**は ルール `commit` の「Co-Authored-By 署名トレーラ」節に従う（本 skill では再記述しない）。付ける場合は上のコミットメッセージ末尾に空行を挟んで `Co-Authored-By: <実行モデルの署名（例: Claude Opus 4.8 (1M context) <noreply@anthropic.com>）>` を追記する。

### 6. Push & PR 作成

```bash
git push -u origin <sub-issue-branch>
# worktree 隔離運用では --head 省略で head 誤推定→ "No commits between X and X" で失敗しうるため明示
gh pr create --draft \
  --base <ベースブランチ（取り込み先。直列に積むときは先行 Sub-issue のブランチ）> \
  --head <sub-issue-branch> \
  --assignee @me \
  --title "<type>: <要約>" \
  --body "## Summary

<変更内容の要約>

Docs-impact: <api|architecture|detail|ui / none(理由)>

未実行の検証: <コマンド> / 理由: <資源名>（Issue 本文に `検証時排他:` が宣言されている場合、または
実装中にその検証をスキップした場合に必須。該当が無ければこの行自体を省略してよい——テンプレート化は
しない。宣言の不在を「検証済み」と読まない fail-safe のため、該当する場合に書き漏らさない）

<取り込み先で分ける: 下記>

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

**PR 本文の書き方は取り込み先で分ける**（PR 本文の `Closes #` は既定ブランチ向けの PR でしか解釈されないため）:

- **Epic ブランチ向け（直列に積んだ先行ブランチ向けを含む）**: `Closes #` ではなく「Part of #<Epic番号>」と
  Sub-issue への参照（`Sub-issue: #<issue番号>`）を書く。Sub-issue は取り込みの確認後に統制側が明示的に閉じる。
  **コミット末尾の `Closes #<issue番号>` は残す**（`epic-implement` が取り込みの確認に使う）。
- **既定ブランチへ直接入れる例外**: 従来どおり PR 本文に `Closes #<issue番号>` を書く。

**doc は同じ PR では更新しない**（[[sync-design-docs]] の方針）。設計影響の有無だけ `Docs-impact:` 行に**記録**し、`.docs/` の実体更新は **Epic 完了時にまとめて**行う（途中更新は後続で覆って手戻りになりやすい）。

### 7. 一次レビュー → PR単位ゲート → ready 化 → 報告
**標準PRループに従う**（ルール `pr-loop` — 常時オンの正本）。Epic Sub-issue 固有の点だけ:
- レビューは **PR コメント上**で（記録を GitHub に資産化）。並列配下なら `orchestrate-parallel` の管理者が、名指し1件ならメインが `yosage-dev-harness:code-reviewer` を dispatch。
- 指摘は yosage-dev-harness:implementer に対応させ（`SendMessage`）→ resolve、**スコープ外/follow-up は `issue-create` で issue 化**。
- **PR単位ゲート**: Issue 本文に `検証時排他:` が宣言されている、または PR 本文に「未実行の検証」が記載されている場合、**`gh pr ready` の前に**メインがそのブランチ単体（`git fetch` してブランチをチェックアウト、または既存の割り当て worktree）で**直列に**該当検証を実行する。実装（worktree 並列）は妨げない——ゲートは検証ステップだけに掛かる。成功したら PR 本文の「未実行の検証」行を検証済みへ更新（または削除）する。失敗したら yosage-dev-harness:implementer へ差し戻す。
- ゲートを通ったら **`gh pr ready`** → PR URL を報告。

## 注意事項

- PR のベースブランチは Sub-issue の本文の取り込み先（既定は Epic ブランチ `epic/<name>`、例外は解決した既定ブランチ）。
  規則の詳細は ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節（再記述しない）。取り込み先は自分では変えず統制側へ提案する。
- コミット/PR タイトル・マージ戦略・`Closes #`・PR 本文の repo 内自己完結は **横断ルール**（ルール `commit` / `pr-loop` / `issue-discipline`）に従う。
- 実装が Issue の記載内容と矛盾する場合はユーザーに確認する
- レビュー対応・ユーザー指摘・「やってみて判明した」学びは **`capture-learning`** で蓄積する（本人の文脈で。ローカル/グローバルの振り分け・昇格は同 skill）
