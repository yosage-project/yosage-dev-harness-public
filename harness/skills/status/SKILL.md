---
name: status
description: 導入先の設定(既定値と今の値)・.gitignore の不足/打ち消し・.claude/worktrees/.gitignore の状態・推奨設定の見本がプラグインの版と一致するか・使われなくなった項目を表で見せる(書き込まない)。設定を確認したいとき・導入状態を把握したいときに使う。
allowed-tools: Bash(yosage-dev-harness-status *)
---

# status — 導入先の状態を表で見せる(読み取り専用)

## 動的コンテキスト

!`yosage-dev-harness-status`

## 示し方

上記の出力をそのまま示す（要約・言い換えをしない）。**設定ファイル
（`.claude/yosage-dev-harness.local.json`）を Read・cat で直接開かない**（秘密の値
——今は `notify.url`——が入りうるため。writeOnly の項目は出力側で「設定あり／設定なし」だけに
既に丸めてある）。1項目だけ値が要る場合は `yosage-dev-harness-config-get <dotted.key>` を使う
（`writeOnly` の項目は秘密として拒否される）。

- **設定**: 項目・既定値・今の値の表。`writeOnly` の項目は今の値が「設定あり／設定なし」だけ。
- **`.gitignore`**: 不足している行・利用者が明示的に外している（打ち消しの）行。
- **`.claude/worktrees/.gitignore`**: OK / 無い / 中身が `*` でない / 追跡されている（移行が必要）。
- **推奨設定の見本**: プラグインの今の版と一致しているか。
- **スキーマに無い項目**: あれば一覧（消さない・判断は利用者に委ねる）。

## 知見を残す(knowledge loop)
- **前**: 着手前に [[recall-knowledge]] で関連ドメイン（`harness-dev`）の過去の判断・落とし穴を recall する。
- **後**: 動かしてみて分かった挙動・判断は [[capture-learning]] で蓄積する（作業した本人が回す）。
