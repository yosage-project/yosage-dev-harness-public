# test/suites/92-bin.sh — 補助スクリプトの実行ファイル化・エージェント名前空間化・旧製品名置換の
# 静的テスト。判定ロジックは test/lib/bin-checks.py に切り出し、実物(harness/)と
# negative control(一時コピー + 意図的な壊し)の両方から同じコードで呼ぶ(判定を2箇所に書かない)。
BIN_CHECKS="$ROOT/test/lib/bin-checks.py"

echo "== check1: 実行ファイル名の実在(bin/ に実在・実行ビット・lib/<name>.sh が実在) =="
_c1_out="$(python3 "$BIN_CHECKS" check1 "$H")"
if [ -z "$_c1_out" ]; then
  ok "check1: skills/agents/rules/hooks が参照する yosage-dev-harness-<name> はすべて bin/ に実在する"
else
  ng "check1: 実行ファイル名の実在に問題あり: $_c1_out"
fi

echo "== check2: パスでの呼び出しが残っていない(harness 配下に .claude/(lib|hooks)/ 参照が無い) =="
# harness/lib/knowledge-convert-paths.sh の4箇所(使い方コメント2行・対応表の正規表現2行)は、
# 変換元(導入先のパス .claude/lib/…・.claude/hooks/…)自体を文字列として扱う変換スクリプトの
# 本質的な内容であり、呼び出し(path での実行)ではない(意図的に残す。除外は file:line 単位)。
_c2_out="$(python3 "$BIN_CHECKS" check2 "$H" --exclude "$H/lib/knowledge-convert-paths.sh:12" \
  "$H/lib/knowledge-convert-paths.sh:13" "$H/lib/knowledge-convert-paths.sh:64" \
  "$H/lib/knowledge-convert-paths.sh:65")"
if [ -z "$_c2_out" ]; then
  ok "check2: harness 配下に .claude/(lib|hooks)/ 参照は無い(個別判断で残した変換元の4箇所を除く)"
else
  ng "check2: パスでの呼び出しが残っている: $_c2_out"
fi

echo "== check3: エージェント参照がすべて名前空間つき =="
_c3_out="$(python3 "$BIN_CHECKS" check3 "$H")"
if [ -z "$_c3_out" ]; then
  ok "check3: 10エージェント名は yosage-dev-harness: の直後以外で単語として現れない"
else
  ng "check3: 名前空間なしのエージェント参照が残っている: $_c3_out"
fi

echo "== check3-agents-exist: yosage-dev-harness:<x> の <x> が agents/<x>.md に実在し name: と一致 =="
_c3e_out="$(python3 "$BIN_CHECKS" check3-agents-exist "$H")"
if [ -z "$_c3e_out" ]; then
  ok "check3-agents-exist: 名前空間つき参照の <x> はすべて agents/<x>.md に実在し name: と一致する"
else
  ng "check3-agents-exist: 不整合あり: $_c3e_out"
fi

echo "== check3: 除外規則(パスの一部は数えない)自体の検査 =="
_c3s_out="$(python3 "$BIN_CHECKS" regex-selftest)"
if [ -z "$_c3s_out" ]; then
  ok "regex-selftest: agents/implementer.md・yosage-dev-harness:agents/implementer.md は通り、裸の \`implementer\` は検出される"
else
  ng "regex-selftest: 除外規則の自己検査に失敗: $_c3s_out"
fi

echo "== check4: 旧製品名(harness/scripts/test) =="
_c4_out="$(python3 "$BIN_CHECKS" check4 "$H" "$ROOT/scripts" "$ROOT/test")"
if [ -z "$_c4_out" ]; then
  ok "check4: harness/scripts/test に旧製品名の残留は無い"
else
  ng "check4: 旧製品名が残っている: $_c4_out"
fi

echo "== negative control: check2 の --exclude は指定した file:line だけに効く(全体を素通りさせない) =="
_nc_c2_dir="$(mktemp -d)"
cp -R "$H" "$_nc_c2_dir/harness"
mkdir -p "$_nc_c2_dir/harness/skills/nope-test3"
printf -- '---\nname: nope-test3\ndescription: negative control\n---\n呼び出し: `bash .claude/lib/foo.sh`\n' \
  > "$_nc_c2_dir/harness/skills/nope-test3/SKILL.md"
_nc_c2_exclude="$_nc_c2_dir/harness/lib/knowledge-convert-paths.sh:12"
_nc_c2_out="$(python3 "$BIN_CHECKS" check2 "$_nc_c2_dir/harness" --exclude "$_nc_c2_exclude")"
case "$_nc_c2_out" in
  *"nope-test3/SKILL.md"*)
    case "$_nc_c2_out" in
      *"knowledge-convert-paths.sh:12"*) ng "negative control: --exclude が除外対象(knowledge-convert-paths.sh:12)まで通してしまっている" ;;
      *) ok "negative control: --exclude は指定した1行だけを除外し、無関係な新規違反(nope-test3)は検出される" ;;
    esac
    ;;
  *) ng "negative control: check2 が無関係な新規違反(nope-test3)を検出しなかった" ;;
esac
rm -rf "$_nc_c2_dir"

echo "== negative control: 実行ファイルが実在しない参照を書くと check1 が赤くなる =="
_nc_bin_dir="$(mktemp -d)"
cp -R "$H" "$_nc_bin_dir/harness"
mkdir -p "$_nc_bin_dir/harness/skills/nope-test"
printf -- '---\nname: nope-test\ndescription: negative control\n---\n呼び出し: `yosage-dev-harness-nope --foo`\n' \
  > "$_nc_bin_dir/harness/skills/nope-test/SKILL.md"
_nc_bin_out="$(python3 "$BIN_CHECKS" check1 "$_nc_bin_dir/harness")"
if [ -n "$_nc_bin_out" ]; then
  ok "negative control: 実在しない yosage-dev-harness-nope を書くと check1 が赤くなる"
else
  ng "negative control: check1 が実在しない実行ファイル参照を検出しなかった"
fi
rm -rf "$_nc_bin_dir"

echo "== negative control: 名前空間なしのエージェント参照を書くと check3 が赤くなる =="
_nc_ns_dir="$(mktemp -d)"
cp -R "$H" "$_nc_ns_dir/harness"
mkdir -p "$_nc_ns_dir/harness/skills/nope-test2"
printf -- '---\nname: nope-test2\ndescription: negative control\n---\nこれは `implementer` に回す。\n' \
  > "$_nc_ns_dir/harness/skills/nope-test2/SKILL.md"
_nc_ns_out="$(python3 "$BIN_CHECKS" check3 "$_nc_ns_dir/harness")"
if [ -n "$_nc_ns_out" ]; then
  ok "negative control: 名前空間なしの \`implementer\` を書くと check3 が赤くなる"
else
  ng "negative control: check3 が名前空間なしの参照を検出しなかった"
fi
rm -rf "$_nc_ns_dir"
