#!/usr/bin/env bash
# doc-drift-check.sh — 「.docs 取りこぼし」検知(Sensor)。
#   ブランチの差分に設計影響のあるコード変更があるのに .docs/ が未更新なら警告する。
#   sub-issue 単位ではなく **Epic 全体が固まった段階(Epic PR の前)** で回すのが既定
#   (途中で docs を更新すると後続で覆って手戻りになりやすいため、docs は Epic 完了後にまとめて更新)。
#   使い方: yosage-dev-harness-doc-drift-check [base-ref] [head-ref]
#     base 既定: lib/base-branch.sh の解決(導入先の既定ブランチ＝origin/HEAD)で決め、origin/<base> と比べる。
#       決まらなければ SKIP(Sensor なので exit 0 のまま)。
#   出力: 先頭に "RESULT: OK|FINDINGS|SKIP"。常に exit 0(壊さない/Sensorは報告に徹する)。
set -uo pipefail

head_ref="${2:-HEAD}"
base="${1:-}"
if [ -z "$base" ]; then
  # shellcheck source=./base-branch.sh
  source "$(dirname "${BASH_SOURCE[0]}")/base-branch.sh"
  _bb_name="$(bb_resolve "$PWD" 2>/dev/null)"
  _bb_rc=$?
  case "$_bb_rc" in
    0) base="origin/$_bb_name"
       git rev-parse --verify -q "$base" >/dev/null 2>&1 \
         || { echo "RESULT: SKIP (base を決められない: $base が実在しない)"; exit 0; } ;;
    2) echo "RESULT: SKIP (base を決められない: git リポジトリの外)"; exit 0 ;;
    *) echo "RESULT: SKIP (base を決められない: origin/HEAD が未設定。引数で base を渡すか git remote set-head origin --auto を実行する)"; exit 0 ;;
  esac
fi

files="$(git diff --name-only "$base...$head_ref" 2>/dev/null)"
[ -n "$files" ] || { echo "RESULT: OK (差分なし vs $base)"; exit 0; }

docs_changed=0; code_changed=0; areas=""
add_area() { case "|$areas|" in *"|$1|"*) ;; *) areas="$areas|$1" ;; esac; }

while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    .docs/*|*/.docs/*) docs_changed=1; continue ;;
    # 設計影響なしとみなす(テスト/設定/ロック/CI/コンテナ)はスキップ
    *_test.*|*.test.*|*.spec.*|*/tests/*|*/test/*|*/spec/*) continue ;;
    *.lock|*-lock.json|*.sum|*.toml|*.yaml|*.yml|*.json|*.md|*.txt|*.cfg|*.ini) continue ;;
    .github/*|.claude/*|Dockerfile*|*/Dockerfile*|*compose*|Makefile|.gitignore) continue ;;
  esac
  code_changed=1
  case "$f" in
    *router*|*route*|*endpoint*|*controller*|*/api/*) add_area "api → .docs/api" ;;
    *model*|*migration*|*schema*)                     add_area "data model → .docs/architecture" ;;
    *screen*|*widget*|*component*|*page*|*/ui/*)       add_area "ui → .docs/ui" ;;
    *)                                                add_area "logic/structure → .docs/architecture or .docs/detail" ;;
  esac
done <<EOF
$files
EOF

if [ "$code_changed" = "1" ] && [ "$docs_changed" = "0" ]; then
  echo "RESULT: FINDINGS"
  echo "設計影響のあるコード変更があるのに .docs/ が未更新です(取りこぼしの疑い)。"
  echo "Epic 完了の段階なら sync-design-docs で .docs/ を実装に合わせて更新してから PR を作ってください。"
  echo "影響しうる doc 領域:"
  printf '%s\n' "$areas" | tr '|' '\n' | sed '/^$/d;s/^/  - /'
  exit 0
fi
echo "RESULT: OK (.docs更新=$docs_changed / 設計影響コード変更=$code_changed, vs $base)"
exit 0
