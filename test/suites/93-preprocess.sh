# test/suites/93-preprocess.sh — スキルの前処理(SKILL.md の !`...` 行)がハーネスの実行ファイル
# だけを呼び、そのスキル自身の frontmatter の allowed-tools がその実行ファイルだけを許可している
# ことの静的テスト。判定ロジックは test/lib/preprocess-checks.py に切り出し、実物(harness/)と
# negative control(一時コピー + 意図的な壊し)の両方から同じコードで呼ぶ(判定を2箇所に書かない)。
PREPROCESS_CHECKS="$ROOT/test/lib/preprocess-checks.py"

echo "== check1: 前処理の先頭コマンドが yosage-dev-harness- で始まり bin/ に実在し、他のコマンドが繋がっていない =="
_p1_out="$(python3 "$PREPROCESS_CHECKS" check1 "$H")"
if [ -z "$_p1_out" ]; then
  ok "check1: 前処理はすべてハーネスの実行ファイル単体の呼び出し"
else
  ng "check1: 前処理に問題あり: $_p1_out"
fi

echo "== check2: 前処理を持つスキルの allowed-tools が Bash(<name> *) を過不足なく含む =="
_p2_out="$(python3 "$PREPROCESS_CHECKS" check2 "$H")"
if [ -z "$_p2_out" ]; then
  ok "check2: allowed-tools は前処理が使う実行ファイルだけを過不足なく許可している"
else
  ng "check2: allowed-tools に問題あり: $_p2_out"
fi

echo "== check3: 前処理を持たないスキルに allowed-tools が無い =="
_p3_out="$(python3 "$PREPROCESS_CHECKS" check3 "$H")"
if [ -z "$_p3_out" ]; then
  ok "check3: 前処理を持たないスキルに allowed-tools は無い(allow を配らない)"
else
  ng "check3: 前処理を持たないスキルに allowed-tools がある: $_p3_out"
fi

echo "== check4: 前処理を持つスキルがちょうど6つ =="
_p4_out="$(python3 "$PREPROCESS_CHECKS" check4 "$H")"
if [ -z "$_p4_out" ]; then
  ok "check4: 前処理を持つスキルは epic-implement / epic-implement-subissue / epic-review / issue-implement / promote-knowledge / status の6つ"
else
  ng "check4: 前処理を持つスキルの集合が期待と異なる: $_p4_out"
fi

echo "== negative control: 前処理に | cat を足すと check1 が赤くなる =="
_nc_pipe_dir="$(mktemp -d)"
cp -R "$H" "$_nc_pipe_dir/harness"
python3 - "$_nc_pipe_dir/harness/skills/issue-implement/SKILL.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    '!`yosage-dev-harness-gh-issue-resolve "$ARGUMENTS"`',
    '!`yosage-dev-harness-gh-issue-resolve "$ARGUMENTS" | cat`',
    1,
)
open(path, "w", encoding="utf-8").write(text)
PY
_nc_pipe_out="$(python3 "$PREPROCESS_CHECKS" check1 "$_nc_pipe_dir/harness")"
if [ -n "$_nc_pipe_out" ]; then
  ok "negative control: 前処理に \`| cat\` を足すと check1 が検出する"
else
  ng "negative control: check1 が \`| cat\` の混入を検出しなかった"
fi
rm -rf "$_nc_pipe_dir"

echo "== negative control: allowed-tools から1つ消すと check2 が赤くなる =="
_nc_missing_dir="$(mktemp -d)"
cp -R "$H" "$_nc_missing_dir/harness"
python3 - "$_nc_missing_dir/harness/skills/issue-implement/SKILL.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "allowed-tools: Bash(yosage-dev-harness-gh-issue-resolve *)\n",
    "",
    1,
)
open(path, "w", encoding="utf-8").write(text)
PY
_nc_missing_out="$(python3 "$PREPROCESS_CHECKS" check2 "$_nc_missing_dir/harness")"
if [ -n "$_nc_missing_out" ]; then
  ok "negative control: allowed-tools を消すと check2 が検出する"
else
  ng "negative control: check2 が allowed-tools の欠落を検出しなかった"
fi
rm -rf "$_nc_missing_dir"

echo "== negative control: 前処理の無いスキルに allowed-tools を足すと check3 が赤くなる =="
_nc_extra_dir="$(mktemp -d)"
cp -R "$H" "$_nc_extra_dir/harness"
python3 - "$_nc_extra_dir/harness/skills/glossary/SKILL.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
assert text.startswith("---\n"), "unexpected frontmatter shape"
text = text.replace("---\n", "---\nallowed-tools: Bash(gh *)\n", 1)
open(path, "w", encoding="utf-8").write(text)
PY
_nc_extra_out="$(python3 "$PREPROCESS_CHECKS" check3 "$_nc_extra_dir/harness")"
if [ -n "$_nc_extra_out" ]; then
  ok "negative control: 前処理の無いスキルに allowed-tools を足すと check3 が検出する"
else
  ng "negative control: check3 が余分な allowed-tools を検出しなかった"
fi
rm -rf "$_nc_extra_dir"
