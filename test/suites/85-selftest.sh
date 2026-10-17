echo "== 後始末漏れ検知: 判定ロジック(開始時スナップショットとの差分)の回帰 =="
# 回帰(a): 作業者が開始時から置いていた未追跡ファイルは、スイート中ずっと存在し続けても
# (開始時にも終了時にも現れるため)差分に出ない=除外される。before/after はわざと非ソート順で
# 与える(comm -13 は両入力がソート済みである前提のアルゴリズムなので、_dirt_diff 内部の sort を
# 削ると非ソート入力に対して誤って非空を返す=このケースが sort の有無を pin する回帰になる)。
_dd_before_only="$(_dirt_diff "$(printf '%s\n' '?? zzz-scratch.md' '?? .epic_docs/plan.md')" "$(printf '%s\n' '?? .epic_docs/plan.md' '?? zzz-scratch.md')")"
out_is_empty "後始末漏れ検知回帰: 開始時から在る未追跡(例 .epic_docs/)は据え置きなら差分に出ない(非ソート入力でsort前提をpin)" "$_dd_before_only"

# 回帰(b): スイート実行中に新たに追跡ファイルの改変・未追跡残骸が発生した場合(命名は問わない)、
# 開始時に存在した未追跡ファイルが混ざっていても新規分だけが差分に出て捕捉される。
_dd_new_dirt="$(_dirt_diff "$(printf '%s\n' '?? .epic_docs/plan.md')" "$(printf '%s\n' '?? .epic_docs/plan.md' ' M harness/lib/example-dummy.sh' '?? leftover.bak')")"
out_has   "後始末漏れ検知回帰: スイート中に新たに改変された追跡ファイルは差分に出て捕捉される"       " M harness/lib/example-dummy.sh" "$_dd_new_dirt"
out_has   "後始末漏れ検知回帰: スイート中に新たに残った未追跡残骸は名前を問わず差分に出て捕捉される" "?? leftover.bak"          "$_dd_new_dirt"
out_hasnt "後始末漏れ検知回帰: 開始時から在った未追跡は新規汚染に混ざっても差分に混入しない"         ".epic_docs/plan.md"       "$_dd_new_dirt"

echo "== 失敗詳細の保全: 判定ロジック(_format_failure_report)の回帰 =="
# _format_failure_report を直接呼んで整形結果をpinする(ng() 経由だと本スイートの fail
# カウンタが増えてしまうため、純粋関数側だけを直接叩く。上の _dirt_diff と同じ設計判断)。
_ffr_out="$(_format_failure_report 2 "assert A (expected exit 0, got 1)" "assert B (missing: foo)")"
out_has "失敗詳細の保全回帰: 見出しに失敗件数が出る"                 "== failures (2) =="                    "$_ffr_out"
out_has "失敗詳細の保全回帰: 1件目の失敗名+期待/実際値が残る"       "assert A (expected exit 0, got 1)"     "$_ffr_out"
out_has "失敗詳細の保全回帰: 2件目の失敗名+期待値が残る"            "assert B (missing: foo)"               "$_ffr_out"

