#!/usr/bin/env bash
# harness/lib/branch-protection.sh — 保護すべきブランチ集合の単一ホーム。
#
# 背景: ブランチの一括掃除(epic-cleanup.sh の「merge 済み集合」を求める際の除外リスト等)は、
# 保護すべきブランチ名を呼び出し側ごとに個別で持つと二重管理になり、取りこぼしが起きる
# (実例: 除外リストが `main` は挙げていたが `master` を挙げておらず、リリース専用ブランチが
# 巻き込まれかけた)。ここへ集約する。
#
# 保護対象そのものの意味論(何を保護するか)はここでは変えない。列挙を1箇所にまとめるだけ。
set -uo pipefail

# 常に保護する固定名(リポジトリのリリース専用ブランチとして扱われる慣例名)。
# 呼び出し側(base ブランチ・epic ブランチ等、状況依存の保護対象)はここに含めない
# (固定名と可変引数を混ぜると、可変引数側の欠落がこの配列の中に紛れて見えなくなるため)。
BP_ALWAYS_PROTECTED=(main master)

# 保護すべきブランチ集合を改行区切りで標準出力へ返す。
#   $1: base_branch (必須。epic 系の分岐元・掃除の除外基準)
#   $2..: 追加で保護するブランチ(epic ブランチ本体等。0個以上)
# 呼び出し側は `grep -vFxf <(bp_protected_branches ...)` のように除外フィルタへ渡す想定。
bp_protected_branches() {
  local base_branch="${1:?base_branch is required}"
  shift || true
  printf '%s\n' "$base_branch" "${BP_ALWAYS_PROTECTED[@]}" "$@"
}
