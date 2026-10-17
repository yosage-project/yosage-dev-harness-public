---
name: sync-design-docs
description: 実装中/PR時に設計ドキュメント(.docs)を実装と同期させるスキル。設計が実装で変わった・やってみて判明したケースを取りこぼさず吸収する。実装からドキュメントを起こし(derive)、docの主張をコードと照合(verify)し、PR・Epic-PRの段階でdoc更新を必須化する。「設計が変わった」「docの更新漏れ」「実装に合わせてドキュメント直す」場面で使う。
---

# sync-design-docs — 実装と設計ドキュメントを同期する

設計は実装中に変わる（当初は問題なしと判断 / 技術的にやってみて判明）。
**その変更を取りこぼさず `.docs/` に反映**する。アーキの正本は [[document-architecture]] が作る `.docs/architecture/`。

## いつ使うか（既定は Epic 完了時にまとめて）
- **既定: Epic 完了時に一括更新**。Epic 全体が固まってから `.docs/` を実装に合わせる。
  途中の sub-issue 単位で更新すると、後続の sub-issue で覆って**手戻り**になりやすいため。
- Sub-issue PR 時: **doc 影響の有無を記録するだけ**（`Docs-impact:` 行）。実体の更新はしない。
- 例外: 実装が設計から**大きく**逸れたとその場で気づいたとき（重要なものは早めに反映）。

## 3つの動作

### 1. 影響範囲の特定
```bash
git diff --name-only <base>...HEAD
```
- 変更コード領域に対応する `.docs/` を特定する。目安:
  - ルーター/エンドポイント → `.docs/api`
  - レイヤー構成・依存の変更 → `.docs/architecture`
  - 機能の挙動・仕様 → `.docs/detail`
  - 画面 → `.docs/ui`

### 2. 実装から起こす（derive）
**実装が正、doc が追従**。コードから事実を抜き出して doc を更新する:
- API: ルート一覧・リクエスト/レスポンス契約を実装（または OpenAPI/スキーマ）から再生成。
- 構成: 新規ディレクトリ/レイヤー/モジュールを architecture に反映。
- データモデル: モデル/マイグレーションから data_model を更新。
- 推測で書かない。`path:line` で接地（[[grounded-design]] の規律）。

### 3. 検証する（verify）
doc の主張がコードと一致するか照合する:
- doc が参照するパス/シンボルが実在するか（grounding-check.sh と同系）。
- doc に書かれた構造・エンドポイント・モデルが現状と一致するか。
- 不一致は「doc を実装に合わせる」か「実装側の想定外/バグ」かを切り分け、後者はユーザー確認。
- 重要な設計は `yosage-dev-harness:consistency-reviewer` に doc↔コードのドリフト点検を依頼。

## ゲート（取りこぼし防止）
- **Sub-issue PR**: 実体の `.docs/` 更新はしない。PR 本文に **`Docs-impact: <api|architecture|detail|ui> / none(理由)`** を必ず記録（Epic 完了時に反映するため）。
- **Epic 完了時（既定ブランチへの Epic PR の前）= docs 更新の本番**（通常は `yosage-dev-harness:doc-writer` サブエージェントが隔離文脈で実施し digest を返す＝管理者は大きな差分を抱えない）:
  1. `yosage-dev-harness-doc-drift-check` を実行（設計影響コード変更があるのに `.docs/` 未更新＝取りこぼしを検知）。
  2. FINDINGS なら本スキルで `.docs/` を実装に合わせて**まとめて更新**（derive → verify）。各 sub-issue の `Docs-impact:` も突き合わせる。
  3. Epic PR 本文に `Docs: 更新あり <対象> / 更新不要 <理由>` を明記。

## 原則
- **proposal は凍結**: 設計変化は `.docs/architecture`/`detail`/`api`/`ui`（生きた doc）に反映する。`.docs/proposal.md` は書き換えない（よほどの方針転換のみ Amended、[[proposal]]）。
- **実装が正、doc が追従**: 乖離は doc を実装へ合わせる（設計意図の変更なら理由も残す）。
- **Epic 完了でまとめて ＋ Sensor で取りこぼし検知**: docs は Epic が固まってから一括更新し、`doc-drift-check.sh` で漏れを機械的に潰す（per-sub-issue の逐次更新は手戻りの元）。
- **記録は都度、更新はまとめて**: sub-issue では `Docs-impact:` を必ず残し、忘却を防ぐ。
- **沈黙で済ませない**: 「doc 更新不要」も理由付きで明示する（黙ってスキップしない）。
