---
name: update
description: 導入先の .gitignore の不足行・.claude/worktrees/.gitignore・推奨設定の見本を今のプラグインの版に合わせて更新する(設定ファイルの項目は書き足さない)。`/yosage-dev-harness:update` の明示実行でのみ動く。
disable-model-invocation: true
---

# update — 導入先の守りをプラグインの今の版に合わせる(明示実行)

**`/yosage-dev-harness:update` の明示実行でのみ動く**（`disable-model-invocation: true`）。書き込みを伴うため前処理
（`allowed-tools` での事前許可）は持たない。

## 手順

1. `yosage-dev-harness-update` を実行し、出力をそのまま示す。
2. 出力に「利用者が明示的に外している」行が含まれる場合は、その行を強調して利用者に伝える。
3. 出力に「追跡されている .claude/worktrees/.gitignore」の報告が含まれる場合は、移行が必要な
   旨をそのまま伝える。
4. 出力に「スキーマに無い項目」の一覧が含まれる場合は、そのまま示す（消さない・判断は利用者に委ねる）。

## setup との違い
- **設定ファイル（`.claude/yosage-dev-harness.local.json`）は触らない**（無くても作らない・
  既存の項目も書き足さない）。初回導入は `setup` を使う。
- それ以外（`.gitignore` の不足行・`.claude/worktrees/.gitignore`・推奨設定の見本・使われなくなった
  項目の一覧）は `setup` と同じ判定・同じ実行ファイル群（`harness/lib/setup.sh`）を使う。

## 知見を残す(knowledge loop)
- **前**: 着手前に [[recall-knowledge]] で関連ドメイン（`harness-dev`）の過去の判断・落とし穴を recall する。
- **後**: 動かしてみて分かった挙動・判断は [[capture-learning]] で蓄積する（作業した本人が回す）。
