#!/usr/bin/env bash
# harness/lib/secret-patterns.sh — 認証 secret の共有パターン定義と秘密ファイルの一覧。
#
# このファイルは harness/hooks/guard.sh から source して使用する
# (gh pr/issue body への secret 混入防止・commit 時点のセッション内 secret スキャン・
# 秘密ファイルの一覧と判定 sf_is_secret_path/sf_deny_rules)。
#
# 重複定義を避けるための単一の正本。変更する場合はここを編集する。
# ✓外部: gitleaks v8 (https://github.com/gitleaks/gitleaks) 由来パターンを grep -E 化。
#        macOS BSD grep 互換（ERE {n} 量指定子をサポート）。

# === Secret パターン（block 対象）===
# SECRET_PATTERNS: grep -E パターン（インデックスは SECRET_LABELS と 1:1 対応）
# PEM は別変数（先頭の - を grep がオプションと誤解釈しないよう grep -- で使う）。
SECRET_PATTERNS=(
  'ghp_[0-9a-zA-Z]{36}'
  'github_pat_[A-Za-z0-9_]{82}'
  '(A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}'
  'xox[baprs]-[A-Za-z0-9-]+'
  'AIza[A-Za-z0-9_-]{35}'
  'sk-[A-Za-z0-9_-]*T3BlbkFJ[A-Za-z0-9_-]*'
  'sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{40,}'
  '(sk|rk)_(test|live)_[0-9a-zA-Z]{10,}'
)

SECRET_LABELS=(
  'GitHub PAT (ghp_)'
  'GitHub PAT (github_pat_)'
  'AWS Access Key ID'
  'Slack token'
  'Google API key'
  'OpenAI API key (legacy: T3BlbkFJ marker)'
  'OpenAI API key (new format: sk-proj-/sk-svcacct-/sk-admin-)'
  'Stripe key'
)

# PEM プライベートキーヘッダー
# 使用時は `grep -E -- "$SECRET_PEM_PATTERN"` と -- を付けて先頭の - をオプションと誤解釈しないようにする。
SECRET_PEM_PATTERN='-----BEGIN [A-Z0-9 _-]*PRIVATE KEY'
SECRET_PEM_LABEL='PEM private key'

# === 秘密ファイルの一覧（唯一の置き場） ===
# guard.sh の Bash 読み取り判定(sf_is_secret_path)と、推奨設定の見本(setup の段で作る。
# sf_deny_rules が出力する "Read(<glob>)" 群)の両方が、ここから作られる。
# テンプレートの接尾辞(.example / .sample / .template)は対象外(sf_is_secret_path 側で除外)。
# ここに列挙する38件は推奨設定の見本(setup の段で作る)の Read 拒否38件とそのまま対応させる
# 想定(.env とその既知の変種34件・*.pem・*.key・id_rsa・secrets/**)。
SECRET_FILE_DENY_GLOBS=(
  ".env" "**/.env"
  ".env.local" "**/.env.local"
  ".env.development" "**/.env.development"
  ".env.dev" "**/.env.dev"
  ".env.test" "**/.env.test"
  ".env.staging" "**/.env.staging"
  ".env.stage" "**/.env.stage"
  ".env.production" "**/.env.production"
  ".env.prod" "**/.env.prod"
  ".env.ci" "**/.env.ci"
  ".env.development.local" "**/.env.development.local"
  ".env.dev.local" "**/.env.dev.local"
  ".env.test.local" "**/.env.test.local"
  ".env.staging.local" "**/.env.staging.local"
  ".env.stage.local" "**/.env.stage.local"
  ".env.production.local" "**/.env.production.local"
  ".env.prod.local" "**/.env.prod.local"
  "**/*.pem"
  "**/*.key"
  "**/id_rsa"
  "**/secrets/**"
)

# _sf_is_template_ext: $1(.env の拡張子チェーン部分を含むマッチ全体、先頭/末尾の境界文字を
# 含みうる)の末尾が .example/.sample/.template そのもの(直後に境界文字1つか文字列終端)であれば真。
# 実値を含まないテンプレート(.env.example 等)を編集・閲覧する日常作業まで秘密ファイルと同じ
# 扱いでブロックしない(guard.sh (E) 節の背景コメントを参照)。
_sf_is_template_ext() {
  printf '%s' "${1:-}" | grep -Eq '\.(example|sample|template)[^A-Za-z0-9_.]?$'
}

# _sf_env_hit: $1(スキャン対象テキスト)に、テンプレート接尾辞ではない .env 系の一致が
# 1件でもあれば真(exit 0)を返す。同じテキストに .env.example と .env.production のような
# 複数の一致が混在する場合、テンプレートでない一致が1つでもあれば対象とする。
_sf_env_hit() {
  local _t="${1:-}"
  local _re='(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_.-]*)?([^A-Za-z0-9_.]|$)'
  printf '%s' "$_t" | grep -Eq "$_re" || return 1
  local _occ _real=""
  while IFS= read -r _occ; do
    [ -n "${_occ:-}" ] || continue
    _sf_is_template_ext "$_occ" || _real=1
  done <<< "$(printf '%s' "$_t" | grep -oE "$_re" 2>/dev/null)"
  [ -n "${_real:-}" ]
}

# sf_is_secret_path: $1(ファイルパス・トークン・Grep の path/glob 値など)が秘密ファイルの
# 一覧(SECRET_FILE_DENY_GLOBS)のいずれかに該当するかを判定する。真なら exit 0、偽なら exit 1。
# 判定は SECRET_FILE_DENY_GLOBS の各 glob そのものをパターンマッチするのではなく、既存の
# guard.sh (E) 節が使っていた判定(_sf_env_hit・.pem・.key・id_rsa・secrets/)をそのまま使う
# (この判定のほうが広い: 一覧に無い .env の変種(.env.qa 等)も捕まえる。これは意図的な差
# (推奨設定の見本は Claude Code の書式の制約で列挙しかできないため)。
sf_is_secret_path() {
  local _t="${1:-}"
  [ -n "$_t" ] || return 1
  _sf_env_hit "$_t" && return 0
  printf '%s' "$_t" | grep -Eq '\.pem([^A-Za-z0-9_.]|$)' && return 0
  printf '%s' "$_t" | grep -Eq '\.key([^A-Za-z0-9_.]|$)' && return 0
  printf '%s' "$_t" | grep -Eq '(^|[^A-Za-z0-9_])id_rsa([^A-Za-z0-9_.]|$)' && return 0
  printf '%s' "$_t" | grep -Eq "(^|[[:space:]/'\"])secrets/" && return 0
  return 1
}

# sf_deny_rules: SECRET_FILE_DENY_GLOBS の各要素を "Read(<glob>)" として1行ずつ出力する
# (推奨設定の見本(setup の段)を作る側が使う)。
sf_deny_rules() {
  local _g
  for _g in "${SECRET_FILE_DENY_GLOBS[@]}"; do
    printf 'Read(%s)\n' "$_g"
  done
}
