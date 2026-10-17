#!/usr/bin/env bash
# sync-labels.sh — 標準 GitHub ラベルを対象リポジトリへ適用する(冪等)。
#   読込: <script>/../github/labels.json (+ あれば <repo-root>/.claude/yosage-dev-harness-labels.json を上書き/追加マージ)
#   gh label create --force で upsert する。要 gh 認証 + リポジトリ context。
#   使い方:
#     yosage-dev-harness-sync-labels <repo-root>            # 適用
#     yosage-dev-harness-sync-labels --dry-run <repo-root>  # 適用せず一覧表示
#   プロジェクト固有ラベル(scope:api など)は <repo-root>/.claude/yosage-dev-harness-labels.json に同じ形式で置く。
#   書き込む先のリポジトリは <repo-root> の GitHub リポジトリ(gh repo view)を明示的に使う(cwd の gh context に頼らない)。
set -euo pipefail

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi

ROOT_ARG="${1:-}"
[ -n "$ROOT_ARG" ] && [ -d "$ROOT_ARG" ] || { echo "usage: sync-labels.sh [--dry-run] <repo-root>" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base="$SCRIPT_DIR/../github/labels.json"
proj="$ROOT_ARG/.claude/yosage-dev-harness-labels.json"

[ -f "$base" ] || { echo "labels.json が見つかりません ($base)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq が必要です" >&2; exit 1; }

files=("$base")
[ -f "$proj" ] && files+=("$proj")

# ローカルの JSON 検査はネットワークに依存する NWO 解決(gh repo view)より前に行う(fail-fast)。
# jq empty は構文しか見ない(単一オブジェクト・数値等も構文的には正しい)ため、後段の
# `jq -s 'add | ...'` が期待する「トップレベルが配列」であることも別途検査する。
# 要素ごとの .name/.color の妥当性(欠落・型違い)まではここでは検査しない(スコープ外)。
for f in "${files[@]}"; do
  syntax_err="$(jq empty "$f" 2>&1 >/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ラベル定義の JSON が不正です ($f): $syntax_err" >&2
    exit 1
  fi
  jq -e 'type == "array"' "$f" >/dev/null 2>&1 || {
    echo "ラベル定義の JSON はトップレベルが配列である必要があります ($f)" >&2
    exit 1
  }
done

NWO="$(cd "$ROOT_ARG" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$NWO" ] || { echo "<repo-root> の GitHub リポジトリを特定できません ($ROOT_ARG)" >&2; exit 1; }

# base + proj を結合し、同名は後勝ち(= proj 優先)でユニーク化
merged="$(jq -s 'add | group_by(.name) | map(last)' "${files[@]}")"

# @tsv(1行1レコードの TSV)ではなく jq の @sh で bash 配列リテラルを直接組み立てて
# eval する。理由:
# - @tsv はフィールド内の実タブ/改行/バックスラッシュを `\t`/`\n`/`\\` という2文字の
#   エスケープ列に変換するが、read -r 側はそれを実バイトへ戻さない(read に unescape
#   機能は無い)。結果、description が変わったまま gh へ渡ってしまう。@sh はシェルの
#   引用符そのものを組み立てるため、eval を経由すれば値がそのまま往復する。
# - `while ... done < <(jq ...)` のプロセス置換は、bash 3.2 ではプロセス置換内コマンド
#   (jq)の終了状態を親シェルが拾えない。壊れた要素(.name がオブジェクト等)があっても
#   jq が黙って一部だけ出力し、ループは rc=0 のまま抜けてしまう。`code="$(jq ...)"` の
#   単純代入なら、jq の失敗はその代入コマンド自体の終了状態になり、set -e で即座に
#   スクリプトが止まる。
# - IFS=$'\t' の実タブは IFS のデフォルト空白文字集合に含まれる文字であり、空フィールド
#   が連続すると read 側でフィールドがずれる。@sh + eval は配列要素の区切りをシェルの
#   引用符で決めるため、空文字列の description でもずれない。
code="$(printf '%s' "$merged" | jq -r \
  '"names=(\(map(.name|@sh)|join(" "))); colors=(\(map(.color|@sh)|join(" "))); descs=(\(map(.description // ""|@sh)|join(" ")))"')"
eval "$code"

failed=()
i=0
while [ "$i" -lt "${#names[@]}" ]; do
  name="${names[$i]}"
  color="${colors[$i]}"
  desc="${descs[$i]}"
  if [ "$DRY" = "1" ]; then
    printf 'would upsert (%s): %-22s #%-6s %s\n' "$NWO" "$name" "$color" "$desc"
  else
    if err="$(gh label create -R "$NWO" "$name" --color "$color" --description "$desc" --force 2>&1 >/dev/null)"; then
      printf 'ok: %s\n' "$name"
    else
      printf 'FAILED: %s: %s\n' "$name" "$err" >&2
      failed+=("$name")
    fi
  fi
  i=$((i+1))
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "ラベル適用に失敗しました: ${failed[*]}" >&2
  exit 1
fi
