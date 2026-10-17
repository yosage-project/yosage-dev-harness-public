---
name: issue-create
description: Epic に属さない単発の GitHub issue を self-contained に作成するスキル。follow-up・レビューで出たスコープ外・別セッション跨ぎ・Epic 後に対応すべき発覚事項を「issue を見れば対応できる」形で起票する。Epic 一括作成は epic-create-issues。
argument-hint: "[title]"
---

# issue-create — 単発 issue を self-contained に起票する

actionable な作業を doc に埋めず **issue に出す**ための基本スキル。1件の issue を、
**それだけ見れば対応できる**形（背景・受け入れ条件をインライン）で作る。
これはプリミティブ。Epic の一括分割・ネイティブリンクは [[epic-create-issues]]（このスキルの規律を Epic に適用したスケール版）。

## いつ使うか
- レビューで出た**スコープ外 / follow-up**（落とさず追跡）。
- **Epic 途中で発覚した「Epic 後に対応すべき」事項**（doc に埋めず issue 化）。
- 別セッション跨ぎ・引き継ぎが要る単発作業。
- 自明で同セッションにマージし切る変更は省略可（self-contained な PR が記録になる）。

## issue 規律（必ず守る）
- **self-contained**: 背景・再現・受け入れ条件を**本文にインライン**。
- **耐久リンクのみ**: repo 外（横断/一時）doc を参照しない。内容はインライン展開、リンクが要るなら耐久 URL（共有 issue/wiki/drive）。上位ディレクトリ参照（`../`）やワークスペース絶対パスは GitHub 上で壊れるため使わない（`guard.sh` は `gh issue create`/`edit` 本文の **`../` 参照のみ**ブロックする。絶対パスは検知しないので運用で避ける）。
- **種別ラベル**: `feat`/`fix`/`refactor`/`chore`/`docs`/`test`/`perf` を1つ付与（ブランチ/コミット接頭辞と一致。正本は配布の `github/labels.json`）。

## 手順
1. **種別を決める**（タイトル接頭辞＝ラベルに一致）。
2. **ラベルの存在を担保**（無ければ作る）:
   ```bash
   gh label list --json name --jq '.[].name' | grep -qx "<type>" || yosage-dev-harness-sync-labels "$(git rev-parse --show-toplevel)"
   ```
3. **重複確認**: 起票前に ルール `issue-discipline` の「起票前の重複確認」節に従い、
   open/closed 両方を対象に既存 issue を検索する。同一の問題が見つかったら新規に起票せず既存へ追記する。
4. **起票**（本文は下テンプレで self-contained に）。`gh issue create` を打つ**前**に、ルール `issue-discipline` の「文脈的自己完結（セッション内符牒の禁止）」節に従い、本文にセッション内符牒が残っていないか自問する:
   ```bash
   gh issue create --title "<type>: <要約>" --label "<type>" --body "<本文>"
   ```
5. **番号を控えてユーザーへ報告**。Epic 由来なら Epic に言及/リンクする。

## 本文テンプレート
```markdown
## 背景 / 課題
<なぜ要るか。どのレビュー/Epic/PR で出たか（耐久リンク or インライン）>

## ゴール
<何が出来れば良いか>

## 受け入れ条件
- [ ] <検証可能な条件>
- [ ] <…>

## 補足（任意）
<実装方針の案・対象ファイル・依存・参考（インライン）>
```

## 完了の合図
- issue 番号が発行され、**本文だけで着手できる**状態（外部参照に依存しない）。
- 実装は [[issue-implement]]（導入先の既定ブランチ基点）。
