---
name: setup
description: 導入先に守りに必要な最小のものだけを書き込む(.gitignore の不足行・.claude/worktrees/.gitignore・設定ファイル・推奨設定の見本)。`/yosage-dev-harness:setup` の明示実行でのみ動く。
disable-model-invocation: true
---

# setup — 導入先に守りに必要な最小のものだけを書き込む(明示実行)

**`/yosage-dev-harness:setup` の明示実行でのみ動く**（`disable-model-invocation: true`）。書き込みを伴うため前処理
（`allowed-tools` での事前許可）は持たない——実行の都度、通常の Bash ツール呼び出しとして
利用者の許可を通す。

## 手順

1. **ワークスペースの推定を示して利用者に `workspace` を決めてもらう**: まず
   `yosage-dev-harness-setup`（`--workspace` 無し）を一度実行し、末尾の「ワークスペースの推定」
   提案（直下に git リポジトリが複数あるとき）が出るかを見る。提案が出た場合は、利用者に
   `workspace: true` にするかを尋ねる。提案が出なかった場合は `workspace: false` として進めて
   よい（迷わせない）。
   - 既に設定ファイルがあり `workspace` が設定済みの場合は、この確認をせず次へ進む。
2. **`yosage-dev-harness-setup --workspace <true|false>` を実行し、出力をそのまま示す**（要約・
   言い換えをしない。導入先に何を書いた／書かなかったかがそのまま利用者に伝わる形を保つ）。
3. 出力に「利用者が明示的に外している」行が含まれる場合は、その行を強調して利用者に伝える
   （意図的な除外を上書きしていないことの確認）。
4. 出力に「追跡されている .claude/worktrees/.gitignore」の報告が含まれる場合は、移行が必要な
   旨をそのまま伝える（このスキルは書き換えない）。
5. 出力に「知見の共有(案内)」が含まれる場合は、その案内もそのまま伝える（知識の同期が有効な導入先では
   出ない。案内だけで、このスキルはストアの作成も設定の書き換えもしない）。

## 知見を残す(knowledge loop)
- **前**: 着手前に [[recall-knowledge]] で関連ドメイン（`harness-dev`）の過去の判断・落とし穴を recall する。
- **後**: 動かしてみて分かった挙動・判断は [[capture-learning]] で蓄積する（作業した本人が回す）。

## 原則
- **書き込みは実行ファイルに一本化**: このスキル自身はファイルを直接編集しない。すべて
  `yosage-dev-harness-setup` を通す（判定ロジックの単一ホームは `harness/lib/setup.sh`）。
- **既定値は消さない**: このスキルはスキーマに無くなった項目やユーザーの `.gitignore` の打ち消しを
  上書きしない（実行ファイル側の不変）。
