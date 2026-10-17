---
name: scratch-run
description: ローカル(Windows/Mac)に uv/python/node 等が無い、またはグローバルを汚したくない時に、使い捨て Docker コンテナで一時コマンドを実行するスキル。ad-hoc なデータ解析・doc一致チェック・ワンオフのツール実行に使う。Docker を基本ランタイムとし、ホストには何も入れない。lib/scratch.sh を使う。
---

# scratch-run — 使い捨てコンテナで一時実行（ホストを汚さない）

ローカル環境(Windows/Mac を行き来)に uv/python/node 等が無いことがある。
**Docker を基本ランタイム**にし、ad-hoc な実行は **使い捨てコンテナ**で行う。ホストにツールを入れない。

## 判断（何で動かすか）
- **アプリのコード/テスト** → `make` / `docker compose exec`（プロジェクトの compose）。
- **ad-hoc（解析 / doc一致チェック / ワンオフのツール）**:
  - uv がローカルにある → 速い道: `uv run --with <pkg> script.py`。
  - uv が無い / 完全分離したい / 非Python → **使い捨てコンテナ**: `yosage-dev-harness-scratch`。
- **ホストにグローバル install しない**（`pip install` / `npm -g` / `gem install` は guard が止める）。

## 使い方
```bash
# Python で解析(コンテナ内で一時 pip、終了で破棄)
yosage-dev-harness-scratch --image python:3.12-slim -- sh -lc "pip install -q pandas && python analyze.py"
# Node ツール
yosage-dev-harness-scratch --image node:24-alpine -- npx prettier --check .
# ネットワーク遮断(信頼できない処理)
yosage-dev-harness-scratch --image python:3.12-slim --net none -- python untrusted.py
```
- `--rm` で実行後に破棄、カレントを `/work` に rw マウント、ホストに痕跡を残さない。
- 残したい成果物はカレント(マウント先)に書けば手元に残る。

## 原則
- **Docker が基本**: ローカルにツールを入れない（クロスプラットフォーム汚染を避ける）。
- **使い捨て**: `--rm`。コンテナ内 install は破棄されるので OK（guard も `yosage-dev-harness-scratch` 経由の呼び出しは許可）。
- **速い道は uv**: uv があれば `uv run --with` でも可。無ければ scratch。
