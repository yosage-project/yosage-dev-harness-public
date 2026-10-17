---
name: document-architecture
description: プロジェクトのアーキテクチャを確立し `.docs/architecture/` に正本化するスキル。新規プロジェクトはスタックに応じたベースケースを提案し、既存プロジェクトはコードから実際のアーキを抽出して記述する。設計を始める前、ハーネス導入時、「アーキテクチャを決めたい/書き出したい」場面で使う。ここで作る doc が grounded-design・yosage-dev-harness:consistency-reviewer・.claude/rules の参照先になる。
---

# document-architecture — アーキテクチャを「起こして・記述して・参照する」

ハーネスは唯一のアーキテクチャを押し付けない。**各プロジェクトの `.docs/architecture/` を正本**とし、
このスキルはそれを **新規=提案 / 既存=抽出** の2モードで確立する。
出来た doc は [[grounded-design]] / yosage-dev-harness:consistency-reviewer / `.claude/rules` の参照先になる。

## 大原則（過剰拘束を避ける）
- **既存は「現実」を書く**。理想形を上書きしない。改善提案は別セクション/別 Issue に分ける。
- **新規は「提案」に留める**。ベースケースは出発点であって強制ではない。プロジェクトが採否を決める。
- **小さく始める**。最初から全レイヤーを設計しない。必要になった分だけ記述する。

## モード判定
- `yosage-dev-harness-detect-stack` でスタックを把握。
- 実装コードが既にある → **既存モード**。空/雛形のみ → **新規モード**。

## 既存モード（コードからアーキを抽出）
1. **探索**（接地）: ディレクトリ構成、レイヤー分け、命名、依存の向き、代表モジュールを `Glob`/`Grep`/Explore で調べる。
2. **代表例を引用**: 各レイヤー/パターンの実例を `path:line` で 2〜3 件挙げる（`✓内部 path:line` で。根拠ラベルは ルール `grounding-labels`）。
3. **記述**: 「今こうなっている」を `.docs/architecture/` に書く。未接地で埋めた点は `+補完(要確認)`。
4. **不整合の指摘**: 規約から外れている箇所を見つけたら、正本には現実を書きつつ別途「逸脱/改善候補」として列挙（勝手に直さない）。

## 新規モード（ベースケースを提案）
1. `.docs/proposal.md`（[[proposal]]）があれば読み、それを満たす前提で、スタックを検出し下のカタログから**出発点**を提示。
2. プロジェクトの要件に合わせて削る/足す（YAGNI）。採用した理由・捨てた案を残す。
3. `.docs/architecture/` に「採用アーキテクチャ」として記述。

## ベースケース・カタログ（出発点。強制ではない）
既存プロジェクト群で実際に確立されているパターンを出発点として提示する:
- **Python / FastAPI**: バーティカルスライス寄り。`usecases`(1操作=1クラス) + `repositories` + `schemas` + `validators`、router は薄く。domain は純粋関数。
- **TS / Next.js(App Router)**: feature-based。`features/<feature>/{components,hooks,api}` + 共有 `components/ui`(shadcn) + `lib`。
- **Flutter**: feature-first + Riverpod。`lib/features/<feature>/{screen,widget,provider,service,model}` + `router` + `shared`。
- **TS / Phaser(ゲーム)**: scene と domain(ゲームロジック) を分離。
- **Unity / C#**: `Assets/Scripts` を domain / usecases / interface-adapter / infrastructure に層分け。

## 出力構造（`.docs/` 設計ステージのレール）
設計には段階がある。`.docs/` を次の標準で構成する（必要な段階だけ作る）:
```
.docs/
├── proposal.md          # 企画の起点(実装開始で凍結。proposal スキル)
├── glossary.md          # ユビキタス言語・命名の正本(glossary スキル)
├── architecture/        # アーキの正本(本スキルの成果)
│   ├── 01_overview.md       # 全体像・データフロー・ディレクトリ構成
│   ├── 02_layers.md         # レイヤーと責務、依存の向き
│   ├── 03_patterns.md       # 採用パターンと代表例(path:line)
│   └── 04_data_model.md     # データモデル(あれば)
├── api/                 # API 設計(エンドポイント/契約)
├── detail/              # 詳細設計(機能単位)
└── ui/                  # UI 設計
```
各段階の詳細設計は、必ず `architecture/` を参照し整合させる。

## 参照のつなぎ込み
- `.docs/architecture/` ができたら、`.claude/rules/<該当パス>/coding.md` から要点を参照させる。
- 設計時は [[grounded-design]] が、この doc を「規約の正本」として確認する。
- 実装で設計が変わったら、放置せず [[sync-design-docs]] で同じ PR 内で更新する。

## 知見を残す（knowledge loop）
- **前**: アーキを起こす前に [[recall-knowledge]] / [[grounded-design]] で過去の判断・既存実装・パターンを recall（接地）する（特に既存モードは実装からの抽出なので [[grounded-design]] による探索が肝）。
- **後**: アーキが確立したら、その過程で得た**再利用可能な知見**（採用したパターン・トレードオフ・制約）を [[capture-learning]] で蓄積する。**作業した本人**が回す（誰が回すかは ルール `knowledge`）。

## 原則
- **記述 > 規定**: まず現実を書く。規定したいなら提案として分けて出す。
- **正本は1つ**: アーキの真実は `.docs/architecture/`。rules も詳細設計もそこを向く。
- **生かし続ける**: 古くなった doc は害。ドリフトは PR 単位で吸収する。
