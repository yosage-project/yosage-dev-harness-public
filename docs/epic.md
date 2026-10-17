# Epic の進め方

大きな変更を、計画・起票・実装・レビュー・完了の順に進める。Epic は、計画をリポジトリ内の
ドキュメントにまとめ、GitHub 上に Epic の issue と Sub-issue（分割した作業単位）を作り、
Sub-issue ごとに PR を出して取り込む進め方。

```
計画 → 起票 → 実装 → レビュー → 完了
```

「Epic を使うか」の判断は [変更の規模ごとの流れ](workflows.md) を見る。大きい・多面的・並列に
進められる変更が対象。

## 全体像と、人がやること

| 段階 | コマンド | 人がやること |
|---|---|---|
| 計画 | `/yosage-dev-harness:epic-create-docs <epic-name> <概要>` | **計画（分割と取り込み先）を読んでレビューする** |
| 起票 | `/yosage-dev-harness:epic-create-issues [epic-title]` | **このコマンドを自分で打つ**（人だけが起動できる） |
| 実装 | `/yosage-dev-harness:epic-implement <owner>/<repo>#<N>` | **このコマンドを自分で打つ**（人だけが起動できる）。**PR をマージする** |
| レビュー | `/yosage-dev-harness:epic-review <owner>/<repo>#<N>` | **PR を読んでマージする** |
| 完了 | Sub-issue の PR と Epic の PR をマージしたあと、`/yosage-dev-harness:epic-implement <owner>/<repo>#<N>` をもう一度実行する | **Epic の PR をマージする** |

`epic-create-issues` と `epic-implement` は、人が打ったときだけ動く。Claude が自分から始めることは
ない（実装を着火する遷移は重いため、人が引く。単発の issue の実装を profile の宣言でメインへ委譲していても、Epic は委譲の対象外で人が引く）。次に打つコマンドは、前の段階の終わりに Claude が
示す。

単一リポジトリでは `<N>` だけでもよい。

## 1. 計画: epic-create-docs

```
/yosage-dev-harness:epic-create-docs <epic-name> <概要>
```

Claude が（必要ならアーキテクト役 `yosage-dev-harness:architect` に調べさせながら）コードベースを
調べ、計画を `.epic_docs/<epic-name>/` に書く。

```
.epic_docs/<epic-name>/
├── 00_overview.md      目的・現状の問題・スコープ・Sub-issue 一覧・実施順序・スコープ外
├── phase0/             基盤整備の Sub-issue ごとの文書
├── phase1/             メイン作業
└── phase2/             クリーンアップ
```

小さい Epic は phase に分けなくてよい。各 Sub-issue の文書には、概要・対象ファイル・実装内容・
依存関係・取り込み先・検証方法を書く。

**分け方**: 1つの Sub-issue は「それだけで動作を確かめられる」かつ「取り込んでも他を壊さず、
半端な状態を残さない」ものにする。どちらかを満たさない候補は、分けずに1つにまとめる。

**取り込み先**: 既定は Epic ブランチ（`epic/<epic-name>`）。Epic の完了時に、Epic の PR で
既定ブランチへ入る。独立に取り込めて、かつ先に出したい事情があるものだけは、既定ブランチへ
直接入れる。Sub-issue ごとの判断と理由は、計画に書かれる。

**人がやること: 計画を読んでレビューする。** 特に Sub-issue の分け方と取り込み先を見る。この
スキルはコミットしない。レビューが終わるまで、起票には進まない。

## 2. 起票: epic-create-issues

```
/yosage-dev-harness:epic-create-issues [epic-title]
```

計画をもとに、次を作る。

1. Epic の issue（タイトル `Epic: <タイトル>`、ラベル `epic`）。
2. Sub-issue（種別ラベルつき）。本文には計画の内容を網羅して書く（`.epic_docs/` を参照させない）。
3. Sub-issue を Epic のネイティブな sub-issue として紐づける。紐づかないものがあれば、そこで
   止まって報告する。
4. Epic 本文の Sub-issue 一覧を、実際の issue 番号に更新する。
5. Epic ブランチ `epic/<epic-name>` を作る。単一リポジトリでは、計画ドキュメントをこのブランチに
   コミットして push し、既定ブランチ向けの **draft の Epic PR** を作る（取り込み漏れの受け皿）。

終わりに、次に打つコマンド（`/yosage-dev-harness:epic-implement <N>`）が示される。

## 3. 実装: epic-implement

```
/yosage-dev-harness:epic-implement <owner>/<repo>#<N>
/yosage-dev-harness:epic-implement <owner>/<repo>#<N> phase1
/yosage-dev-harness:epic-implement <owner>/<repo>#<N> #<a>,#<b>
```

- **スコープなし**: 全フェーズを、人の追加の操作なしに完走する。
- **`phase1` や Sub-issue の番号を指定**: そのスコープだけ実行して止まる。次のフェーズは、
  止まったあとに案内されるコマンドで人が続ける。

着手の前に、Claude は次を行う。

- 計画ドキュメントが見つかるか確かめる。**見つからなければ止まって人に確認する**（小さな Epic
  では計画なしで進めてもよいが、それを決めるのは人）。
- Sub-issue の一覧を、GitHub のネイティブな紐づけと突き合わせる。食い違いがあれば止まる。
- 対象 Sub-issue・依存関係・実行の順序・取り込み先を示してから着手する。
- Epic 全体にかかわる未解決の問いがあれば、実装前に整理する（実装する物が変わるものは人に確認）。

実装の進め方は次のとおり。

- **依存のない Sub-issue** は並列に実装役へ任せる。同じファイルを触る Sub-issue は並列にしない。
  各実装役は隔離した作業ツリーで動き、Claude が進捗を監視する（進捗が無い実装役には状況を
  問い合わせ、返らなければ止めて原因を記録し、1回だけやり直す。それでも進まなければ人に上げる）。
- **依存のある Sub-issue** は、先行 Sub-issue の PR がマージされるのを待たずに、先行のブランチを
  土台に積んで進める。この PR の base は先行ブランチになる。
- 各 Sub-issue の PR は draft で作り、取り込み先（Epic ブランチ、または例外の既定ブランチ）へ向ける。
  Epic ブランチ向けの PR 本文には、`Closes #` ではなく `Part of #<Epic>` を書く（`Closes #` は
  既定ブランチ向けの PR でしか効かないため）。
- 実装中にエラーが出た Sub-issue は、飛ばさずに人へ報告する。判断待ちや価値の判断が出たら、
  完走を止めて人に確認する。

全 PR が出そろうと、Claude は一覧と**マージ順序**（積んだ PR は Epic ブランチに近い側から）を
報告して止まる。

## 4. レビュー: epic-review

```
/yosage-dev-harness:epic-review <owner>/<repo>#<N>
```

Epic ブランチ向けの open な PR を、1件ずつレビューする。`epic-implement` が PR を出している
最中に並行して使える。問題がなければ draft を ready にし、マージ推奨・要確認・未レビューに分けて
報告する。**マージはしない。**

**人がやること: ready になった PR を読んで、順にマージする。** 積んだ PR は、次の PR をマージ
する前に、base が正しい向き先に付け替わっているかを確かめる（リポジトリの設定によっては自動で
付け替わらない）。

## 5. 完了

`epic-implement` は、全 PR を報告した時点で止まる（3節）。**人が Sub-issue の PR をマージし終えたら、
もう一度 `/yosage-dev-harness:epic-implement <owner>/<repo>#<N>` を実行する**と、完了の手順に進む。
同じコマンドは、途中で原因を直したあとの再実行にも使え、すでに閉じた Epic の issue に対して
繰り返しても安全。完了の手順は次のとおり。

1. 各 Sub-issue の変更が Epic ブランチの履歴に入っていることを確かめ、**マージされた PR への
   リンクを添えて Sub-issue を閉じる**（Epic ブランチ向けの PR は自動では閉じないため）。
2. 設計ドキュメント（`.docs/`）を、ドキュメント担当のサブエージェント
   `yosage-dev-harness:doc-writer` が Epic 全体の差分に合わせて更新する。
3. draft の Epic PR の本文を現在の状態に更新し、`yosage-dev-harness:code-reviewer` で一次レビューして
   から ready にする。

**人がやること: Epic の PR を読んで、マージする。**

Epic の PR をマージしたら、**もう一度同じコマンドを実行する**。Epic の PR がマージされたと確認できた
時点から、Claude は次を確かめる。満たさないものがあれば案内して止まる。

- Epic の PR がマージ済みである。
- 計画ドキュメントが既定ブランチに合流している（ワークスペースでは、実装との差分を計画に追記
  してある）。
- Epic ブランチが既定ブランチへ入り、リモートとローカルから消えている。
- Sub-issue がすべて閉じている。

そのうえで、手元の base ブランチを先に origin へ追いつかせ（`yosage-dev-harness-update-base`。進められなければ
理由を人へ知らせる）、この Epic が作ったブランチと作業ツリーだけを掃除し（他の作業のものは触らない）、
Epic の issue を閉じる。

## 途中で止まったとき

- 計画が見つからない・Sub-issue の一覧に `(要確認)` が付いた・ベースのブランチが決まらない、
  などで止まったときは [よくある詰まり](troubleshooting.md) を見る。
- 複数のリポジトリにまたがる Epic は [ワークスペース](workspace.md) を見る。
