#!/usr/bin/env bash
# detect-stack.sh — 対象ディレクトリのマーカーファイルから技術スタックを推定する。
# 使い方: yosage-dev-harness-detect-stack [dir]   (省略時はカレント)
# 出力  : 検出したスタックを空白区切りで1行 (例: "node python unity")
set -uo pipefail
root="${1:-.}"
out=""
add() { case " $out " in *" $1 "*) ;; *) out="$out $1" ;; esac; }

[ -f "$root/package.json" ] || [ -f "$root/tsconfig.json" ]              && add node
[ -f "$root/pyproject.toml" ] || [ -f "$root/requirements.txt" ] \
  || [ -f "$root/setup.py" ] || [ -f "$root/uv.lock" ]                   && add python
[ -f "$root/pubspec.yaml" ]                                             && add flutter
[ -f "$root/Gemfile" ]                                                   && add ruby
[ -f "$root/composer.json" ]                                            && add php
[ -f "$root/ProjectSettings/ProjectVersion.txt" ] \
  || ls "$root"/*.sln >/dev/null 2>&1                                    && add unity
[ -f "$root/astro.config.mjs" ] || [ -f "$root/astro.config.ts" ]        && add astro

echo "${out# }"
