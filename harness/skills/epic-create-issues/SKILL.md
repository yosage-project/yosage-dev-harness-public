---
name: epic-create-issues
description: Epic Issue と Sub-issues を一括作成し、GitHub でリンクする。
argument-hint: "[epic-title]"
disable-model-invocation: true
---

# Create Epic Skill

Epic Issue と Sub-issues を一括作成するスキル。

## 使い方

ユーザーが Epic の概要と Sub-issues のリストを提供したら、以下の手順で GitHub Issues を作成する。

**対象リポジトリが cwd と異なる場合**（複数リポジトリが同居するワークスペースで、Epic/Sub-issue を
実装先リポジトリに立てる運用）は、ユーザーから対象リポジトリを `<owner>/<repo>` 形式で確認し、
以下の `gh issue create` / `gh issue view` / `gh-subissue-link.sh` の呼び出しすべてに
`--repo <owner>/<repo>`（gh CLI 標準のオプション。`gh-subissue-link.sh` もこの型で受け取る）を付ける。
新しい記法・設定は導入しない（`yosage-dev-harness-gh-issue-resolve` が使う `<owner>/<repo>#<N>` 形式・
`--repo` オプションの型に揃える）。

## 手順

### 1. Epic Issue の作成

```bash
gh issue create \
  [--repo <owner>/<repo>] \
  --title "Epic: <タイトル>" \
  --label "epic" \
  --body "<Epic の本文（目的・背景・スコープ・Sub-issues 一覧）>"
```

作成された Issue 番号を控える。

### 2. Sub-issues の作成

各 Sub-issue について、`gh issue create` を打つ**前**に、ルール `issue-discipline` の「文脈的自己完結（セッション内符牒の禁止）」節に従い、計画会話から転記する本文にセッション内符牒が残っていないか自問する:

```bash
gh issue create \
  [--repo <owner>/<repo>] \
  --title "<Sub-issue タイトル>" \
  --label "<種別>" \
  --body "<Sub-issue の本文>"
```

`<種別>` は Sub-issue のブランチ/コミット接頭辞に一致させる（`feat`/`fix`/`refactor`/`chore`/`docs`/`test`/`perf`）。
親への紐付けは次ステップの**ネイティブ sub-issue リンク**で行う（ラベルではなく関係で表す）。

**重要**: Sub-issue の本文には計画内容を**網羅的に記載**すること。
`.epic_docs/` 等のドキュメントへの参照リンクは記載しない（できるだけ詳細に issue に書く）。

### 3. Sub-issues を Epic に「確実に」リンク（sub-issue 化）

**全 Sub-issue が Epic のネイティブ sub-issue として紐づくまで、このスキルを完了としない。**
Sub-issue リンクの mutation ＋ 検証クエリでの欠け再リンクループは `harness/lib/gh-subissue-link.sh`
ラッパーに封じ込めてある（settings の Bash 許可はこのラッパー呼び出しだけに絞られており、
生の GitHub API への広い許可を持たない）。**リンク → 検証 → 欠けを再リンク**をラッパー内部で
行い、揃わなければ非ゼロ終了で報告する（黙って進めない）。

```bash
yosage-dev-harness-gh-subissue-link link <epic_number> [--repo <owner>/<repo>] <sub_number_1> <sub_number_2> <...>
```

**非ゼロ終了は停止条件**: 非ゼロ終了した場合、stderr のメッセージ（どの Sub-issue が紐づかなかったか）を
ユーザーに報告し、**そのまま手順4（Epic 本文更新）以降へ進まない**。後続の手順は、この手順で
全 Sub-issue が確実にネイティブ sub-issue としてリンクされていることに依存している（`epic-implement`
は Epic 本文から抽出した番号一覧を、ここで作るネイティブ sub-issue の集合と突き合わせて完全性を
確認するため、ここでリンクされなかった Sub-issue は突き合わせの正本から欠けたまま扱われる）。
ユーザーへ報告した後、原因を解消してから本手順を再実行し、全件のリンクが確認できてから手順4へ進む。

### 4. Epic 本文の Sub-issues リスト更新

Sub-issues 作成後、Epic 本文のチェックリストを実際の Issue 番号で更新する。本文は一旦ファイルに
書き出してから渡す（同じラッパーの `update-body` サブコマンドを使う。任意 issue への任意
フィールド編集は許さず、Epic 本文更新だけに絞ってある）。

```bash
yosage-dev-harness-gh-subissue-link update-body <epic_number> [--repo <owner>/<repo>] --body-file <更新された本文のファイルパス>
```

### 5. Epic ブランチ作成・`.epic_docs/` の反映・Epic の PR（draft）

**先に、Epic ブランチを作るかを決める**（正本は `epic-create-docs` 手順6の「Epic ブランチを作る条件」。計画の「取り込み先」から読む）:

- 取り込み先が Epic ブランチの Sub-issue が1つでもあれば作る。
- **ワークスペース**（実装先リポジトリが最も外側のリポジトリと異なる）で、全件の取り込み先が既定ブランチなら**作らない**。
  この手順の残り（ブランチ作成・push・Epic の PR）をすべて飛ばし、手順6へ進む（`.epic_docs/` の反映だけは下の
  「ワークスペース構成」の文に従って別リポジトリへ行う）。
- **単一リポジトリ**は、全件が既定ブランチ向けでも作る（計画の置き場）。

Epic ブランチは**実装先リポジトリ**（Epic/Sub-issue を作成したリポジトリ）で、**解決したベースから**作成する
（ブランチ名を決め打ちしない）。cwd がそのリポジトリと異なる場合は先にそこへ移動する。**push はここではまだ行わない**
（下記の分岐後、それぞれ1回だけ push する。既定の単一リポジトリ経路を2回 push にしないため）:

**`$base` は別の Bash 呼び出しには残らない**ため、`$base` を使うブロックは、毎回その冒頭で同じ呼び方で解決し直す
（`exit` でシェルを閉じず、`if` で分け、`$base` を使う処理は `then` 側に入れる。空の `$base` で進まない）。
投入時に明示されたベース、または導入先の profile の宣言があれば `--declared` に渡す（無ければ `--declared` を省く）:

```bash
git fetch origin
if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
  git checkout -b epic/<epic-name> "origin/$base"
else
  rc=$?
  case "$rc" in
    1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
    3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
    *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
  esac
fi
```

解決の順と終了コードの扱いは ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節に従う（決まらなければ止めて人に聞く。宣言したブランチが origin に無ければ宣言の誤りとして止める）。

`.epic_docs/<epic-name>/` は `epic-create-docs` が用意した置き場（「cwd から上へ辿って見つかる
最も外側の git リポジトリ」＝`yosage-dev-harness-epic-scope-resolve outermost-root` の出力配下）にある。

- **実装先リポジトリが最も外側のリポジトリと同じ場合**（単一リポジトリの導入先。既定）:
  このタイミングで Epic ブランチへ一緒にコミットしてから push する（**push は1回**）。続けて、**その場で既定ブランチへの
  Epic の PR を draft で作る**（Epic の間の取り込み漏れの受け皿。途中で流れが止まっても、開いたままの PR として見える。
  完了時は `epic-implement` が、この PR を ready にして人がマージする）。

  ```bash
  git add .epic_docs/<epic-name>/
  git commit -m "docs: Epic 計画ドキュメントを追加 (<epic-name>)"
  git push -u origin epic/<epic-name>
  ```

  続く draft の PR 作成は別のブロック（別の Bash 呼び出し）なので、冒頭でベースを解決し直し、作成後の確認も同じブロックで行う:

  ```bash
  if base="$(yosage-dev-harness-base-branch --declared <明示か profile の宣言> <リポジトリのルート>)"; then
    if pr_url="$(gh pr create --draft \
        --base "$base" \
        --head epic/<epic-name> \
        --assignee @me \
        --title "Epic: <タイトル>" \
        --body "## Summary

  Epic #<epic_number> の全実装を取り込む。計画は .epic_docs/<epic-name>/ にある（このブランチの上）。

  Part of #<epic_number>

  🤖 Generated with [Claude Code](https://claude.com/claude-code)")"; then
      # 作成直後に base を確認する（$base と一致すること）
      [ "$(gh pr view "$pr_url" --json baseRefName -q .baseRefName)" = "$base" ] \
        || echo "Epic の PR の base が $base と一致しない: 修正する" >&2
    else
      echo "Epic の PR を作れなかった: 原因を確認する" >&2
    fi
  else
    rc=$?
    case "$rc" in
      1) echo "ベースが決まらない: 止めて人に聞く（投入時に明示 / profile に宣言 / git remote set-head origin --auto）" >&2 ;;
      3) echo "宣言したブランチが origin に無い: 宣言（明示か profile）を直すよう止めて知らせる" >&2 ;;
      *) echo "ベースの解決に失敗（終了コード $rc）: 止めて報告する" >&2 ;;
    esac
  fi
  ```

- **実装先リポジトリが最も外側のリポジトリと異なる場合**（ワークスペース構成）:
  `.epic_docs/` は実装先リポジトリの管理下に無いため、実装先の Epic ブランチにはコミットしない。
  Sub-issue 実装がこのブランチから枝分かれできるよう、ブランチ自体は push する（**push は1回**）。

  ```bash
  git push -u origin epic/<epic-name>
  ```

  **Epic の PR はここでは作らない**: 計画をコミットしていない Epic ブランチは既定ブランチと同じで、GitHub は差分の無い PR を
  作れない（空のコミットを入れて作る形は、意味の無いコミットが既定ブランチの履歴に残るので採らない）。取り漏れが起きるのは
  「Epic ブランチに中身があるのに Epic の PR が無い」ときだけなので、`epic-implement` が**最初の Sub-issue を Epic ブランチへ
  取り込んだ時点**で draft の Epic PR を作る。

  最も外側のリポジトリ（ワークスペース側）が git 管理下なら、`.epic_docs/` はそのリポジトリ自身の
  運用（コミット規約・ブランチ）に従って**別リポジトリへの別コミットとして**反映する（実装先
  リポジトリの push 回数には数えない）。git 管理下でなければコミット不要（ファイルとして存在すれば
  `epic-implement` 側の解決ロジックが参照できる）。

### 6. 完了確認・次の一手

```bash
gh issue view <epic_number> [--repo <owner>/<repo>]
```

Sub-issues が揃ったら、**次に人間が引くべきトリガを正確なコマンドで提案**する（実装は人間トリガ＝正本 ルール `implement-routing`）: 「次は実装フェーズ。`/yosage-dev-harness:epic-implement <epic_number>`（途中で止めるなら `phase1` 等のスコープ可）」。実装先リポジトリが cwd と異なる場合は `/yosage-dev-harness:epic-implement <owner>/<repo>#<epic_number>` の形で提案する。あわせて Epic の PR について案内する: 単一リポジトリなら手順5で作った draft の PR の URL を、ワークスペースなら「最初の Sub-issue の取り込みで `epic-implement` が draft の Epic PR を作る（Epic ブランチを作らない場合は PR も作らない）」旨を添える。

## テンプレート

### Epic 本文テンプレート

```markdown
## 目的

<何を達成するか>

## 背景

<なぜこの変更が必要か>

## スコープ

<含まれるもの・含まれないもの>

## Sub-issues

- [ ] #<number> <タイトル>
- [ ] #<number> <タイトル>
...

## 検証項目

- [ ] <検証内容>
```

### Sub-issue 本文テンプレート

計画内容が漏れないよう、以下の構成で**網羅的に**記載する。
セクションは Sub-issue の内容に応じて取捨選択する。

```markdown
## 概要

<何をするか。スコープ表があれば記載>

## 実装内容

<具体的な作業内容。コード例・ディレクトリ構造・クラス定義等を含む>

## 移行後のディレクトリ構造

<変更後の構造をツリー図で記載>

## 対象ファイル

- `<ファイルパス>`

## 取り込み先

<Epic ブランチ ／ 既定ブランチ（理由）。計画の取り込み先を写す>

## 依存関係

- 依存先: #<number>（<理由>）
- 直列実行: <理由>（任意。データ依存は無いがリスク等で並列に入れたくない時。並列ウェーブに入れず直列化する）
- 検証時排他: <資源名>: <理由>（任意。`直列実行:` とは別フィールド——実装全体ではなく検証ステップだけが
  project-profile 正本の「検証時排他資源」項目に該当する場合に書く。実装先 repo 自身の
  `.claude/rules/<名前>/profile.md`、ワークスペースの member repo 運用では実装先 repo の外
  （ワークスペース側の `.claude/rules/<repo 名>/profile.md`）にある profile と照らして判定する）

## 検証方法

- <検証コマンド・確認手順>
```

## 注意事項

- **ラベル規約**: Epic には `epic`、Sub-issue には種別ラベル（`feat`/`fix`/`refactor`/`chore`/`docs`/`test`/`perf`）を付与（正本は配布の `github/labels.json`、フラット命名）。
  事前にリポジトリへ標準ラベルが無ければ `yosage-dev-harness-sync-labels "$(git rev-parse --show-toplevel)"` で作成しておく。
- **Sub-issue は必ずネイティブ sub-issue としてリンクし、検証で漏れが無いことを確認する**（手順3）。
- Sub-issue 間の依存関係は本文に明記する。
- **検証時排他:** フィールドは、対象 Sub-issue の検証が `project-profile` 正本の「検証時排他資源」項目に
  該当するかを profile.md と照らして判定してから書く。参照先は実装先 repo 自身の
  `.claude/rules/<名前>/profile.md`（単一 repo）、またはワークスペースの member repo 運用では実装先 repo
  の外（ワークスペース側の `.claude/rules/<repo 名>/profile.md`）にある——実装先 repo 内だけを探して
  「無い」と誤判定しない。宣言した Sub-issue の PR は `gh pr ready` 前にメインが直列で該当検証を行う
  （PR 単位ゲート。詳細は `.claude/skills/epic-implement-subissue/SKILL.md` / `.claude/skills/issue-implement/SKILL.md`）。
- Sub-issue 本文は **issue 本文で完結**させる。`.epic_docs/` や **repo 外（横断/一時）ドキュメント**への参照を含めない（内容は**インライン展開**、リンクが要るなら耐久 URL）。`../`・ワークスペース絶対パスは GitHub 上で壊れるため禁止
- ブランチ命名: `epic/<epic名>` → `feat/<sub-issue名>`, `fix/<sub-issue名>`, `chore/<sub-issue名>`
- PR の取り込み先は、Sub-issue 本文の `## 取り込み先` に従う（既定は Epic ブランチ。独立に取り込めて先に出す事情がある例外だけ既定ブランチ。
  規則の詳細は ルール `pr-loop` の「ベースブランチ / クローズ / マージ」節。再記述しない）
