#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit) フック:
#   編集されたファイルを言語に応じて自動整形する。
#   方針: best-effort。フォーマッタ未導入や失敗でもセッションは止めない(常に exit 0)。
set -uo pipefail

input="$(cat)"

# tool_input.file_path を取り出す (jq 優先、無ければ python3、どちらも無ければ何もしない)
get_path() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.file_path // .tool_input.path // empty'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import sys,json;ti=json.load(sys.stdin).get("tool_input",{});print(ti.get("file_path") or ti.get("path") or "")'
  fi
}

file="$(get_path "$input")"
[ -n "$file" ] && [ -f "$file" ] || exit 0

run() { command -v "$1" >/dev/null 2>&1 && "$@" >/dev/null 2>&1 || true; }

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.html|*.md|*.yml|*.yaml|*.astro|*.svelte|*.vue)
    [ -f package.json ] && run npx --no-install prettier --write "$file" ;;
  *.dart)
    if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc -o -d .fvm ]; then run fvm dart format "$file"
    elif command -v dart >/dev/null 2>&1; then run dart format "$file"; fi ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      run ruff format "$file"; run ruff check --fix "$file"
    elif command -v black >/dev/null 2>&1; then
      run black -q "$file"
    fi ;;
  *.rb)
    if [ -x bin/rubocop ]; then run bin/rubocop -A "$file"
    elif command -v rubocop >/dev/null 2>&1; then run rubocop -A "$file"; fi ;;
  *.php)
    if [ -x vendor/bin/pint ]; then run vendor/bin/pint "$file"
    elif [ -x vendor/bin/php-cs-fixer ]; then run vendor/bin/php-cs-fixer fix "$file"
    elif command -v php-cs-fixer >/dev/null 2>&1; then run php-cs-fixer fix "$file"; fi ;;
  *.cs)
    command -v dotnet >/dev/null 2>&1 && run dotnet format --include "$file" ;;
esac
exit 0
