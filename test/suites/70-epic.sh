echo "== epic-implement: 動的コンテキストプローブは lib スクリプト呼び出し(command substitution+if ガード回避) =="
# SKILL の動的コンテキストにインラインの command substitution `$(...)`・`if...fi` 分岐を直書きすると、
# ホスト側の permission チェック(静的解析不能な複雑シェルを難読化コマンドとみなすヒューリスティック)に
# 弾かれ SKILL 起動自体が失敗する。番号抽出・分岐ロジックは lib スクリプトへ出し、SKILL 側は単純呼び出しにする。
_ei_body="$(cat "$H/skills/epic-implement/SKILL.md" 2>/dev/null)"
out_has   "epic-implement: Epic Issue表示プローブは lib スクリプト呼び出し"       'yosage-dev-harness-epic-implement-probe epic "$ARGUMENTS"'      "$_ei_body"
out_has   "epic-implement: Sub-issue番号一覧プローブは lib スクリプト呼び出し"    'yosage-dev-harness-epic-implement-probe subissues "$ARGUMENTS"' "$_ei_body"
out_hasnt "epic-implement: 動的コンテキストにcommand substitution+ifが残っていない" '$(printf'                                                       "$_ei_body"
# epic-implement-probe.sh の警告(要確認・解決失敗)は stderr にしか出ず、
# 動的コンテキストがホストへ渡すのは標準出力なので、合流させないと届く保証が無かった。両方の
# 動的コンテキスト行が末尾に `2>&1` を持ち、stderr を標準出力へ合流させることを固定する。
out_has   "epic-implement: Epic Issue表示プローブの動的コンテキストは stderr を標準出力へ合流させる"      'yosage-dev-harness-epic-implement-probe epic "$ARGUMENTS" 2>&1'      "$_ei_body"
out_has   "epic-implement: Sub-issue番号一覧プローブの動的コンテキストは stderr を標準出力へ合流させる"    'yosage-dev-harness-epic-implement-probe subissues "$ARGUMENTS" 2>&1' "$_ei_body"
out_has   "epic-implement: argument-hint が <owner>/<repo>#<N> 形式も案内(cwdと別リポジトリのEpicを指定できる)" '<owner>/<repo>#' "$_ei_body"
out_has   "epic-implement: 動的コンテキストの解決失敗は会話からの類推へ進まず停止する旨を明記" 'エラーを抱えたまま会話からの類推へ進まない' "$_ei_body"
out_has   "epic-implement: フェーズ定義の探索は epic-scope-resolve.sh を使う(cwd固定をやめる)" 'yosage-dev-harness-epic-scope-resolve locate-phase' "$_ei_body"
out_has   "epic-implement: 「そもそも計画が無い」と「あるのに見つけられない」を区別する旨を明記" 'あるのに見つけられない' "$_ei_body"
out_has   "epic-implement: cross-repo構成では isolation=\"worktree\" を使わない旨を明記" '`isolation="worktree"` を使わない' "$_ei_body"

# 手順5(依存あり Sub-issues)は、オーケストレーター(ハーネス)がマージすることを前提にした
# 記述(「先行 Sub-issue のブランチを Epic ブランチにマージしてから実装を開始する」)を持って
# いたが、ハーネスからの PR マージは pr-loop.md/guard が例外なく禁止しているため実行不能だった。
# 裁定により、先行 Sub-issue のブランチを base にした PR を積み、マージを待たずに
# 実装を進める「スタック方式」へ改めた。マージを人間が行う不変・並列 Sub-issue(手順4)の扱いは
# 変えていない。
out_has   "epic-implement: 手順5の見出しがスタック方式である旨を明記" '### 5. 依存あり Sub-issues の順次実装（スタック方式）' "$_ei_body"
out_hasnt "epic-implement: 手順5にオーケストレーターがマージする旧文言が残っていない" '先行 Sub-issue のブランチを Epic ブランチにマージしてから実装を開始する' "$_ei_body"
out_has   "epic-implement: 手順5はマージを待たずに依存する Sub-issue へ進む旨を明記" 'マージを待たずに**依存する Sub-issue の実装へ進む' "$_ei_body"
out_has   "epic-implement: 依存する Sub-issue のブランチは先行ブランチから作成する旨を明記(Epicブランチからではない)" 'Epic ブランチではなく先行 Sub-issue のブランチから**作成する' "$_ei_body"
out_has   "epic-implement: PR の base も先行 Sub-issue のブランチにする旨を明記" 'PR の base も先行 Sub-issue のブランチにする' "$_ei_body"
# 一次レビュー指摘(🟡1): 連鎖の根がEpicブランチをbaseにする根拠が知見エントリにしか無く配布されない
# (知見エントリは配布物ではない)。配布される手順書側に短く根拠を明記する。
out_has   "epic-implement: 依存チェーンの根はEpicブランチをbaseにする旨と、手順4との整合が理由である根拠を手順内に明記(知見エントリだけに逃がさない)" '依存チェーンの根（他に依存されていない先頭 Sub-issue）だけは、手順4と同じく取り込み先（Epic ブランチ、' "$_ei_body"
out_has   "epic-implement: base の指定を作成直後にgh pr viewで確認する操作を明記(機械的に確認できる部分は寄せる)" 'gh pr view <依存する Sub-issue の PR番号> --json baseRefName -q .baseRefName' "$_ei_body"
out_has   "epic-implement: マージ順序はEpicブランチに近い側から人間が行う旨を手順6の報告に含めるよう明記" '積んだ PR は Epic ブランチに近い側（依存されている側）から' "$_ei_body"
out_has   "epic-implement: baseの自動付け替えを前提にしない旨を明記(自動削除設定に依存しない)" 'base の自動付け替えを前提にしない' "$_ei_body"
out_has   "epic-implement: 自動削除無効による過去の事故実例を明記(先行ブランチへの誤マージ)" '自動削除が無効なリポジトリに積んだ PR を連続マージしたところ' "$_ei_body"
_ei_stack_wrong_order='後続の変更が意図した統合先へ反映されないまま「マージ済み」に見える**
——取り込み後は差分が実際に統合先へ入ったかを確認し、反映されていなければ先行ブランチから統合先への
PR を別途立てて復旧する。'
out_has   "epic-implement: 順序を間違えた場合の帰結(反映されないまま見える)と復旧手順を明記" "$_ei_stack_wrong_order" "$_ei_body"
out_has   "epic-implement: 手順6の報告にスタック時のマージ順序を明記させる旨を追記" 'スタックした（依存あり）Sub-issue が含まれる場合は、**マージ順序**' "$_ei_body"
# 一次レビュー指摘(🟡3): 「base で絞り込む確認はスタックしたPRを取りこぼす」への対処を注意書きに
# 留めず、確認の仕方そのものを手順1で取得済み・完全性照合済みのSub-issue番号一覧を使う形へ変更する
# (gh pr list --base による絞り込みをやめ、Epicブランチの実際のgit履歴にClosesトレーラのコミットが
# 入っているかを番号ごとに確認する)。
# 旧方式(gh pr list --base ...)への言及自体は「使わない理由」の説明として本文に残るため、
# 全文不在ではなく実行コードブロックとして残っていないこと(bashフェンス直後の行ではない)を見る。
_ei_step7_old_as_command='```bash
gh pr list --base epic/<epic-name> --state open
```'
out_hasnt "epic-implement: 手順7がbase絞り込みのgh pr listを実行コマンドとして使っていない(旧方式の再発防止、説明としての言及は許容)" "$_ei_step7_old_as_command" "$_ei_body"
out_has   "epic-implement: 手順7はbase絞り込みではなくSub-issue番号一覧を使う理由を明記(スタックPRの取りこぼし防止)" 'base で絞り込む確認' "$_ei_body"
out_has   "epic-implement: 手順7は手順1取得済み・完全性照合済みのSub-issue番号一覧を使う旨を明記" '手順1で取得済み・完全性照合済みの
Sub-issue 番号一覧' "$_ei_body"
_ei_step7_gitlog_check="git log origin/epic/<epic-name> --format='%B' | grep -E '^Closes #[0-9]+\$'"
out_has   "epic-implement: 手順7はEpicブランチの実際のgit履歴でClosesトレーラの有無を確認する" "$_ei_step7_gitlog_check" "$_ei_body"
# 'for n in <sub-issue番号...>; do' 単体は手順8にも同一文字列があり手順7に対して非弁別的(その
# 単独チェックはmutation testで手順7側を空にしても手順8側の一致で見かけ上PASSしてしまう)。
# 手順7に固有の直後の grep -Fxq 行まで含めて弁別力を持たせる。
_ei_step7_forloop="for n in <sub-issue番号...>; do
  if ! printf '%s\n' \"\$_epic_closes\" | grep -Fxq \"Closes #\$n\"; then"
out_has   "epic-implement: 手順7の確認ループはSub-issue番号一覧を使い行全体の厳密一致(grep -Fxq)で照合する" "$_ei_step7_forloop" "$_ei_body"
out_has   "epic-implement: 手順7は行全体の厳密一致(grep -Fx)を使い番号の前方一致誤検知を避ける理由を明記" '単純な部分一致だと、短い番号の `Closes #<n>` 行が、その番号を
前方一致に含むより長い番号の行' "$_ei_body"

# 再レビュー指摘(危険側の誤り): 「履歴に見つかる」は「現在のツリーに実在する」を保証しない。
# 後続Sub-issueが同じ領域を衝突なく上書きした場合・当該コミットがrevertされた場合のいずれも、
# Closesトレーラの行は履歴に残るため手順7の確認は誤って「見つかった」と報告する。検査を強くする
# 方向は採らず、保証の範囲を手順に明記する形で受ける(旧方式にも同じ盲点がありこの変更の回帰ではない)。
_ei_step7_guarantee_scope='**この確認が保証するのは「対象コミットが Epic ブランチの履歴に一度でも入ったこと」だけである。内容が
現在のツリーに実際に残っているかは保証しない**（後続の変更が同じ領域を衝突なく上書きした場合・当該
コミットが後から取り消された（revert）場合のいずれも、履歴には残るため見逃す）。'
out_has   "epic-implement: 手順7が保証する範囲(履歴に入ったことのみ)と保証しない範囲(現在のツリーに残っているか)を明記" "$_ei_step7_guarantee_scope" "$_ei_body"
out_has   "epic-implement: 手順7の見逃しの具体経路として同一領域の衝突なき上書きを挙げる" '後続の変更が同じ領域を衝突なく上書きした場合' "$_ei_body"
out_has   "epic-implement: 手順7の見逃しの具体経路としてコミットのrevertを挙げる" '当該
コミットが後から取り消された（revert）場合' "$_ei_body"
out_has   "epic-implement: 旧方式が拾えていた一覧外の想定外openPRをこの確認は見ない旨を明記(🟡3)" 'Sub-issue 番号一覧に無い想定外の open な PR」はこの確認では見ない' "$_ei_body"

# Sub-issue 番号一覧(手順1で取得し以降のスキル全体で使い回す共有入力)が空・不完全なまま渡って
# きても、下流の個々の手順(手順8を含む)からは「対象ゼロ件」と区別がつかない欠陥(既に
# 修正済みの5箇所と同型)。手順8だけに検証を足すと同じ一覧を使う他の手順との間に非対称が生まれる
# ため、一覧を取得する手順1側にチェックを置き、全手順に効く形で固定する。
out_has   "epic-implement: Sub-issue番号一覧の完全性チェックの見出しが『この一覧はスキル全体で使い回す共有入力』であると明記(手順8だけに閉じない検証位置)" 'この一覧はスキル全体で使い回す共有入力・以降のすべての手順に効く' "$_ei_body"
out_has   "epic-implement: 番号一覧はepic-implement-probe.sh内でネイティブSub-issueの集合と突き合わせ済みである旨を明記" 'Sub-issue の集合（GraphQL）と突き合わせ済み' "$_ei_body"
_ei_orphan_note='突き合わせの
相手が存在しない場合（ネイティブリンクが0件なのに本文抽出は非ゼロ）'
out_has   "epic-implement: 突き合わせの相手が存在しない場合(ネイティブリンク0件・本文抽出は非ゼロ)も検知対象として明記" "$_ei_orphan_note" "$_ei_body"
out_has   "epic-implement: (要確認)警告が出た一覧を『対象ゼロ件』とみなさない旨を明記(空/不完全とゼロ件の区別)" 'その一覧を「対象ゼロ件」とみなさない' "$_ei_body"
out_has   "epic-implement: (要確認)が出た場合は依存解析・実装dispatch・クローズ確認を含む全手順へ進まず停止・確認する旨を明記" 'この一覧を使うすべての手順へ黙って進まず' "$_ei_body"
out_has   "epic-implement: (要確認)が出た場合はユーザーに停止・確認する(区別できなかった場合の挙動の明記)" 'ユーザーに停止・確認する' "$_ei_body"
out_has   "epic-implement: (要確認)が無ければ一覧をそのまま信頼して進めてよい旨を明記(誤検知時の過剰停止を防ぐ)" 'をそのまま信頼して先へ進んでよい' "$_ei_body"

# Sub-issue クローズ確認(手順8)の契機を「Epic issue を閉じる時点」に固定する。
# Epic issue を閉じる操作自体がこの手順に無かったため明示的に追加し(一次レビュー指摘)、
# Sub-issue の open/closed 判定は gh issue list の既定取得件数上限で取りこぼす欠陥があったため
# (一次レビュー指摘)、番号を明示指定する gh issue view ループへ差し替えた。自動クローズが
# 発火しない構成の具体は pr-loop.md へ名前参照に寄せ、この手順書側で再記述しない(一次レビュー指摘)。
out_has   "epic-implement: 手順8がEpicの完了確認とEpic issueのクローズを扱う見出しである旨を明記" '### 8. Epic の完了確認（Epic の PR・状態1・状態3）' "$_ei_body"
out_has   "epic-implement: 契機はEpic PRの既定ブランチへのマージを人間から確認できた時点である旨を明記" '人間から Epic PR が実際に既定ブランチへマージされたと確認できた時点' "$_ei_body"
out_has   "epic-implement: Epic issue自体を閉じる操作(gh issue close <epic_number>)を含む" 'gh issue close <epic_number> [--repo <owner>/<repo>]' "$_ei_body"
out_hasnt "epic-implement: 「既定の経路では Closes で閉じ済みのはず」という旧い前提の解説が残っていない" '裏取りだけの空振りになる' "$_ei_body"
out_has   "epic-implement: 自動クローズが発火しない構成の具体はpr-loop.mdへ名前参照し再記述しない旨を明記" 'クローズ / マージ」節が正本（ここでは再記述しない）' "$_ei_body"
out_hasnt "epic-implement: pr-loop.mdの構成列挙(既定ブランチがdevelopでない導入先)を再記述していない" '既定ブランチが `develop` でない導入先' "$_ei_body"
out_hasnt "epic-implement: gh issue listでの一括取得ロジックが残っていない(既定取得件数上限で取りこぼす欠陥の再発防止)" 'gh issue list [--repo <owner>/<repo>] --state open --json number' "$_ei_body"
out_has   "epic-implement: Sub-issue状態確認は番号明示のgh issue viewループ(一覧の既定件数上限を受けない)" 'gh issue view "$n" [--repo <owner>/<repo>] --json state -q .state' "$_ei_body"
out_has   "epic-implement: gh issue listの既定件数上限による取りこぼしリスクの説明を明記" '一覧から漏れて「閉じている」と誤判定しうる' "$_ei_body"

# gh issue view が失敗しても代入自体は成立し $state が空文字になるため、後続の
# [ "$state" = "OPEN" ] が false になり「open ではない=閉じている」と黙って混同されうる欠陥
# (再レビュー指摘)。終了コードを見る if ! 代入 idiom へ差し替え、失敗時は「開いていない」と
# みなさずループを止める旨を明記する。
out_has   "epic-implement: gh issue viewの終了コードで判定するif!代入idiomを使う(空文字とクローズ済みの取り違え防止)" 'if ! state="$(gh issue view "$n" [--repo <owner>/<repo>] --json state -q .state)"; then' "$_ei_body"
_ei_view_bare='  state="$(gh issue view "$n" [--repo <owner>/<repo>] --json state -q .state)"
  if [ "$state" = "OPEN" ]; then'
out_hasnt "epic-implement: gh issue viewの結果を終了コード判定無しで直接代入していない(旧欠陥の再発防止)" "$_ei_view_bare" "$_ei_body"
out_has   "epic-implement: 失敗時にopenではない=閉じているとみなさない旨を明記" 'open ではない＝閉じている」とみなさない' "$_ei_body"

# 最終レビュー指摘(5箇所目・同型): 2>&1 で成功時も標準エラーを $state に合流させていたため、
# gh 自体が標準エラーへ出す出力(アップデート通知等)が混ざると成功しているのに open 判定が
# 壊れうる欠陥。2>&1 を外し、標準出力だけを $state に取り込む形へ修正した。
out_hasnt "epic-implement: gh issue viewの呼び出しに2>&1が付いていない(成功時の標準エラー合流によるstate汚染の再発防止)" '.state 2>&1)"' "$_ei_body"
out_has   "epic-implement: 標準出力だけをstateに取り込み標準エラーは合流させない旨を明記" '標準出力だけを `$state` に取り込み、標準エラーは合流させない' "$_ei_body"
out_has   "epic-implement: 2>&1を付けると成功時でも汚染されうる理由を明記" '成功時でも `gh` 自体が標準エラーへ出す出力（アップデート通知等）が混ざって' "$_ei_body"
out_has   "epic-implement: 確認できていない・開いたままのSub-issueが残ったまま確認完了として先へ進まない旨を明記" '確認できていない・開いたままの Sub-issue が残ったまま「確認完了」として先へ進まない' "$_ei_body"

# 再レビュー指摘(自走スキャン依頼): 手順8には他にも「失敗が成功/空振りと同じ経路を通る」
# 呼び出しが2箇所残っていた。(a) Epic issue自体を閉じる gh issue close の終了コード未チェック、
# (b) ループ内でSub-issueを閉じる gh issue close の終了コード未チェック。いずれも失敗しても
# 何も表示されず正常終了するように見えた。終了コードを見る形へ差し替え、失敗を明記する。
_ei_epic_close_guarded='if ! gh issue close <epic_number> [--repo <owner>/<repo>]; then
  echo "Epic issue <epic_number> を閉じられなかった。原因を確認してから再実行する。" >&2
fi'
out_has   "epic-implement: Epic issue自体を閉じるgh issue closeも終了コード判定で保護している" "$_ei_epic_close_guarded" "$_ei_body"
_ei_epic_close_bare='gh issue close <epic_number> [--repo <owner>/<repo>]
```'
out_hasnt "epic-implement: Epic issue自体を閉じるgh issue closeが終了コード判定無しの裸のままではない(旧欠陥の再発防止)" "$_ei_epic_close_bare" "$_ei_body"
out_has   "epic-implement: 既に閉じているissueへのgh issue closeが終了コード0で安全である旨を実測根拠付きで明記" 'は「既に閉じている」旨の警告付きだが終了コードは0のままだった' "$_ei_body"
# 既定ブランチへ直接入れる例外の Sub-issue は、メインが解決したベースを投入指示に明示して渡す(実装者は会話の文脈も
# profile の宣言も知らない)。doc-writer へも要求される <base> を渡す。
out_has   "epic-implement: 例外の Sub-issue はメインが解決したベースを投入指示に明示して渡す" '投入指示に明示して渡す' "$_ei_body"
out_hasnt "epic-implement: 実装者が着手時に自分でベースを解決し直すとは書かない(文脈を持たない)" '実装者が着手時に自分で解決し直す' "$_ei_body"
out_has   "epic-implement: doc-writer へ解決したベース(<base>)を渡す" '`<base>`**（メインが解決したベース' "$_ei_body"

# 手順8の確認は安全網であり、開いたままのものを報告するだけで、取り込みの確認・PR へのリンク無しに閉じない
# (閉じるのは手順7の確認を経たものだけ)。ループの中に gh issue close "$n" を置かない。
_ei_s8_loop="$(printf '%s\n' "$_ei_body" | awk '/^### 8\. /{s=1} s&&/^for n in <sub-issue番号...>; do$/{f=1} f{print} f&&/^done$/{exit}')"
out_has   "epic-implement: 手順8のループは OPEN の Sub-issue を報告する" 'が開いたまま' "$_ei_s8_loop"
out_hasnt "epic-implement: 手順8のループは Sub-issue を確認もリンクも無しに閉じない(閉じるのは手順7の確認を経たものだけ)" 'gh issue close' "$_ei_s8_loop"
out_has   "epic-implement: 手順8の確認は閉じずに報告し、メインが手順7の確認を経て閉じる旨を明記" '報告するだけで閉じない' "$_ei_body"
out_hasnt "epic-implement: 手順8の状態3が「報告して閉じる」と書いていない(ループと食い違わない)" '開いたままのものを報告して閉じる' "$_ei_body"

# 計画ドキュメント(.epic_docs/<epic-name>/)そのものの不在検出。フェーズ/スコープ引数が
# 無いまま実装着手へ進むと、計画ドキュメントが丸ごと欠けていても従来は locate-phase の
# 任意チェック(「したい場合は」)止まりで見過ごせた。実装を起動する工程で必須のゲートに
# 引き上げたことを SKILL.md の記述で固定する(振る舞いの実体は locate-docs 自体のテストで
# 既に検証済みのため、ここでは「必須で呼ばれる・区別される・任意表現が残っていない」ことを見る)。
out_has   "epic-implement: 計画ドキュメントの不在検出はスコープ/フェーズ引数の有無に関わらず必須で実行する旨を明記" 'スコープ/フェーズ引数の有無に関わらず' "$_ei_body"
out_has   "epic-implement: 計画ドキュメントの不在検出は locate-docs を呼ぶ" 'yosage-dev-harness-epic-scope-resolve locate-docs' "$_ei_body"
out_has   "epic-implement: 不在検出の前に git fetch origin を行う" 'git fetch origin' "$_ei_body"
out_has   "epic-implement: exit 4(作業ツリーには無いが Epic ブランチの上にある)は停止しない" '**exit 4（作業ツリーには無いが、Epic ブランチの上にある）**: **停止しない**' "$_ei_body"
out_has   "epic-implement: exit 4 のときは git show で読む" '計画の中身は `git show <stdout の値>/<ファイル>` で読む' "$_ei_body"
out_has   "epic-implement: list-phases の exit 4 は0件でも4でブランチの上で発見の意味" '4=Epic ブランチの上で発見（0件でも4' "$_ei_body"
out_has   "epic-implement: git fetch origin の失敗は警告にとどめて続行する" '`git fetch origin` に失敗しても' "$_ei_body"
out_has   "epic-implement: そもそも計画ドキュメントが無い場合は停止してユーザーに確認する旨を明記" 'ここで停止し、ユーザーに確認する' "$_ei_body"
out_has   "epic-implement: 停止はハードブロックではなく『無いまま進める』判断で先へ進める逃げ道が明記されている" '無いまま進める判断が出た場合のみ' "$_ei_body"
out_has   "epic-implement: 起票の工程ではなく実装着手の工程で確認する理由(空振り防止)を明記" 'そこで警告すると毎回空振りする' "$_ei_body"
out_has   "epic-implement: 警告に留めず停止を選んだ理由を明記" 'この工程は人間がトリガする重い遷移であり' "$_ei_body"
out_has   "epic-implement: 探索の前提が欠けている場合は「そもそも無い」と混同しない旨を明記" '「そもそも無い」と混同せず' "$_ei_body"
out_hasnt "epic-implement: 計画ドキュメントの不在確認が任意扱い(したい場合は)のまま残っていない(必須化への回帰防止)" 'かつフェーズ定義の有無を確認したい場合は' "$_ei_body"

echo "== epic-implement: スコープ無しは全フェーズを人間の追加トリガ無しに完走する =="
# frontmatter description: 「途中フェーズ停止できる」という旧文言(スコープ無し=phase1だけ停止)は
# 新仕様(スコープ無し=完走・明示時のみ停止)と矛盾するため残っていないことを確認する。
out_hasnt "epic-implement: frontmatterのdescriptionに旧文言(任意スコープで途中フェーズ停止できる)が残っていない" '任意スコープ（フェーズ/Sub-issue リスト）で途中フェーズ停止できる' "$_ei_body"
out_has   "epic-implement: frontmatterのdescriptionがスコープ無し=完走・明示時のみ停止という新仕様を明記" 'スコープ無しなら全フェーズを人間の追加トリガ無しに完走' "$_ei_body"

# 手順1: スコープ無しの分岐が「phase1だけ実行して停止」から「全フェーズ完走」へ変わったこと。
# 明示指定時(phase/Sub-issueリスト)の「そのスコープだけ実行して停止」という既存挙動は残す(回帰させない)。
out_hasnt "epic-implement: 手順1にスコープ無し時の旧文言(phase1だけ実行して停止)が残っていない" 'phase1 だけ実行して停止' "$_ei_body"
out_hasnt "epic-implement: 手順1に次フェーズ提案の旧誘導(次は phase2 を提案)が残っていない" '「次は `/epic-implement <N> phase2`」を提案' "$_ei_body"
out_has   "epic-implement: 手順1はスコープ無し・フェーズ定義ありの場合に全フェーズを人間の追加トリガ無しに完走する旨を明記" '全フェーズを人間の追加トリガ無しに順に完走する' "$_ei_body"
out_has   "epic-implement: 手順1は明示指定(①②)時はそのスコープだけ実行して停止し回帰させない旨を明記" 'そのスコープだけ実行して停止する（回帰させない・現状どおり）' "$_ei_body"

# 手順1a: 全フェーズ完走のループ構造(新設)。list-phasesの利用・手順2/4/5への委譲・フェーズ間で
# 止まらない旨・フェーズをまたぐ依存も手順5のスタック方式でよい旨・設計判断のエスカレーション規律。
out_has   "epic-implement: 全フェーズ完走ループの専用見出しがある" '### 1a. 全フェーズ完走時のループ（スコープ無しの場合のみ）' "$_ei_body"
out_has   "epic-implement: 全フェーズ完走ループはlist-phasesでフェーズ一覧を列挙する" 'yosage-dev-harness-epic-scope-resolve list-phases' "$_ei_body"
out_has   "epic-implement: 全フェーズ完走ループは各フェーズを手順2(依存関係解析)にかける旨を明記" 'そのフェーズの対象 Sub-issue に対して手順2（依存関係解析）を行う' "$_ei_body"
out_has   "epic-implement: 全フェーズ完走ループは各フェーズを手順4・5で実装する旨を明記" '手順4（依存なし Sub-issue の並列実装）・手順5（依存あり Sub-issue のスタック方式）でそのフェーズを実装する' "$_ei_body"
out_has   "epic-implement: フェーズをまたぐ依存も手順5のスタック方式でマージを待たずに進めてよい旨を明記" 'フェーズをまたぐ依存も手順5の仕組みでそのまま進めてよい' "$_ei_body"
out_has   "epic-implement: フェーズ間で人間の確認・レビュー待ちを挟まない旨を明記" 'フェーズ間で人間の確認・レビュー待ちを挟まない' "$_ei_body"
out_has   "epic-implement: 全フェーズ完了後に手順6へ進み一括報告する旨を明記" '全フェーズの処理が終わったら手順6（レビュー依頼）へ進み、その時点で初めて一括報告する' "$_ei_body"

# メインの裁定ゲート: implementer の停止報告 or PRレビューの価値トレードオフ指摘を受けたら完走ループを止め、
# grounded-design Step3の裁定分岐に直接従う。PR一次レビュー指摘により、pr-loop.md「指摘対応」節への
# 名前参照は「実装中・レビュー前にメインが停止報告を受け取る」場面には文字通り一致しない(同節はPRレビュー
# コメントのラベルに基づくルーティングが対象)と判明したため、分岐の正本であるgrounded-design Step3を直接
# 参照する形へ修正した(pr-loop.md/implement-routing.mdはStep3をそれぞれの文脈へ適用したものに過ぎない、
# という位置づけの説明とセットで明記)。判断基準そのものは再記述せず名前参照に留める。
out_has   "epic-implement: implementerからの停止報告を受けたら完走ループ全体を止める旨を明記" 'Sub-issue の実装（`yosage-dev-harness:implementer`）から判断待ちとして停止報告が来た場合' "$_ei_body"
out_has   "epic-implement: PRレビューでの価値トレードオフ・スコープ判断指摘でも完走ループを止める旨を明記" 'PR レビューで価値トレードオフ・スコープ判断の指摘が出た場合' "$_ei_body"
out_has   "epic-implement: 完走ループ全体をそこで止める旨を明記" '完走ループ全体をそこで止め' "$_ei_body"
out_has   "epic-implement: 裁定はgrounded-design Step3の裁定分岐に直接従う旨を明記(名前参照)" '`grounded-design` Step3 の裁定分岐' "$_ei_body"
out_has   "epic-implement: pr-loop.md/implement-routing.mdはStep3を各文脈へ適用したものに過ぎない旨を明記(実装中・レビュー前の場面はどちらにも文字通り一致しないため)" 'いずれもこの Step3 をそれぞれの文脈' "$_ei_body"
out_hasnt "epic-implement: pr-loop.mdの指摘対応節への不正確な名前参照(一次レビュー指摘で修正済み)が残っていない" 'pr-loop.md`「指摘対応」節が定める裁定分岐' "$_ei_body"
out_has   "epic-implement: 対応が終わるまで次フェーズへ自動的に進まない旨を明記" '対応が終わるまで次フェーズへは自動的に進まない' "$_ei_body"
out_hasnt "epic-implement: 裁定分岐節がblocking/deferrableの判定基準自体を再記述していない(名前参照のみに留める)" '実装する物自体が変わる' "$_ei_body"
out_hasnt "epic-implement: implementer自身の一般的な停止報告規律(詰まったら回らずに停止)を本節で再記述していない(implementer.mdの大原則を再掲しない)" '詰まったら回らずに停止して報告' "$_ei_body"

# 手順6: レビュー依頼のタイミングをスコープ種別で分岐(明示時=そのスコープ完了時+次phase提案 / スコープ無し=全フェーズ完了後に一括)。
out_hasnt "epic-implement: 手順6に旧文言(次フェーズがあれば次はphase<k+1>を提案。スコープ無し・フェーズ無しの小epicは...)が残っていない" 'スコープ無し・フェーズ無しの小 epic は全 Sub-issue 完走後に報告' "$_ei_body"
out_has   "epic-implement: 手順6はphase/Sub-issueリスト明示時のみ次phaseの提案をする旨を明記" 'phase / Sub-issue リストを明示指定して実行した場合' "$_ei_body"
out_has   "epic-implement: 手順6はスコープ無し完走時は全フェーズ終了後に初めて一括報告する旨を明記" 'スコープ無しで完走した場合' "$_ei_body"

# 手順9: クリーンアップのタイミング「Phase間のレビュー待ち時」がphase明示実行時に限る旨を明記。
out_has   "epic-implement: 手順9のPhase間レビュー待ち時はphase明示実行時のみである旨を明記" '**phase を明示指定して個別実行した場合のみ**: Phase 間のレビュー待ち時' "$_ei_body"
out_has   "epic-implement: 手順9はスコープ無し完走時にPhase間のレビュー待ちが発生しない旨を明記" 'スコープ無しで完走する場合はこの「Phase 間のレビュー待ち時」は発生しない' "$_ei_body"

# 手順6: レビュー依頼のタイミングをスコープ種別で分岐(明示時=そのスコープ完了時+次phase提案 / スコープ無し=全フェーズ完了後に一括)。
out_hasnt "epic-implement: 手順6に旧文言(次フェーズがあれば次はphase<k+1>を提案。スコープ無し・フェーズ無しの小epicは...)が残っていない" 'スコープ無し・フェーズ無しの小 epic は全 Sub-issue 完走後に報告' "$_ei_body"
out_has   "epic-implement: 手順6はphase/Sub-issueリスト明示時のみ次phaseの提案をする旨を明記" 'phase / Sub-issue リストを明示指定して実行した場合' "$_ei_body"
out_has   "epic-implement: 手順6はスコープ無し完走時は全フェーズ終了後に初めて一括報告する旨を明記" 'スコープ無しで完走した場合' "$_ei_body"

# 手順9: クリーンアップのタイミング「Phase間のレビュー待ち時」がphase明示実行時に限る旨を明記。
out_has   "epic-implement: 手順9のPhase間レビュー待ち時はphase明示実行時のみである旨を明記" '**phase を明示指定して個別実行した場合のみ**: Phase 間のレビュー待ち時' "$_ei_body"
out_has   "epic-implement: 手順9はスコープ無し完走時にPhase間のレビュー待ちが発生しない旨を明記" 'スコープ無しで完走する場合はこの「Phase 間のレビュー待ち時」は発生しない' "$_ei_body"

file_is "lib: epic-implement-probe.sh が存在" "$H/lib/epic-implement-probe.sh"
file_is "lib: epic-scope-resolve.sh が存在" "$H/lib/epic-scope-resolve.sh"

# 機能スモーク(番号未指定分岐のみ。gh 呼び出しを伴う分岐はネットワーク/認証依存のためここでは叩かない):
out_has "epic-implement-probe: epic モードは番号未指定で案内文を表示(ghを呼ばない)"       "番号未指定 → step 1 で直前会話から類推・確認" "$(bash "$H/lib/epic-implement-probe.sh" epic "")"
out_has "epic-implement-probe: epic モードは数値以外のみの引数でも番号未指定扱い(ghを呼ばない)" "番号未指定 → step 1 で直前会話から類推・確認" "$(bash "$H/lib/epic-implement-probe.sh" epic "notanumber")"
_ei_out_sub_noarg="$(bash "$H/lib/epic-implement-probe.sh" subissues "" 2>&1)"; _ei_rc_sub_noarg=$?
if [ -z "$_ei_out_sub_noarg" ]; then ok "epic-implement-probe: subissues モードは番号未指定で出力が空(ghを呼ばない)"; else ng "epic-implement-probe: subissues モードは番号未指定で出力が空(ghを呼ばない) (got: $_ei_out_sub_noarg)"; fi
if [ "$_ei_rc_sub_noarg" -eq 0 ]; then ok "epic-implement-probe: subissues モードは番号未指定でも正常終了(exit 0)"; else ng "epic-implement-probe: subissues モードは番号未指定でも正常終了(exit 0)"; fi
out_has "epic-implement-probe: 不明な mode はエラー終了" "不明な mode" "$(bash "$H/lib/epic-implement-probe.sh" bogus "1" 2>&1)"

# gh を実際に叩かず、組み立てられるコマンド引数と本文抽出だけを検証する(モック gh を PATH に差す)。
# subissues モードは本文抽出(番号の列挙)の後にネイティブ Sub-issue の集合(GraphQL subIssues.nodes)とも
# 突き合わせるため、このモックは --json id / api graphql にも応答する。ネイティブ側は本文
# 抽出後の重複排除結果と同じ集合(10, 20)にして、既存の happy-path テストが完全性チェックの
# 警告(要確認)を誤って踏まないようにする(陽性対照: 一致していれば警告は出ないことを別途下で確認する)。
# api graphql の応答は「hasNextPage\tendCursor」の1行目に続けて番号を1行1件で返す形式(ページング
# 対応。eip_native_subissues が最初の行をメタ情報として解釈する契約)。このモックは1ページで
# 完結する(hasNextPage=false)。
_eipbin="$(mktemp -d)"
cat > "$_eipbin/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*)
      echo "Epic本文: 依存先は ${M}10 と ${M}20 と ${M}10(重複)"
      ;;
    *" --json id "*)
      echo "GID_EPIC_MOCK"
      ;;
    *)
      echo "gh $*"
      ;;
  esac
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n10\n20\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin/gh"

_eip_scoped_out="$(cd "$ROOT" && PATH="$_eipbin:$PATH" bash "$H/lib/epic-implement-probe.sh" epic "acme/target${HSH}42" 2>&1)"
out_has "epic-implement-probe: epic モードは <owner>/<repo>#<N> を --repo <owner>/<repo> <N> に解決" "gh issue view --repo acme/target 42" "$_eip_scoped_out"

_eip_broken_out="$(cd "$ROOT" && PATH="$_eipbin:$PATH" bash "$H/lib/epic-implement-probe.sh" epic "acme/target#abc" 2>&1)"; _eip_broken_rc=$?
if [ "$_eip_broken_rc" -ne 0 ]; then ok "epic-implement-probe: 壊れた scoped 形式(#の後が数字以外)は非ゼロ終了(停止)"; else ng "epic-implement-probe: 壊れた scoped 形式(#の後が数字以外)は非ゼロ終了(停止)"; fi
out_hasnt "epic-implement-probe: 壊れた scoped 形式は「番号未指定」扱いにならない(推測へ進まない合図として区別)" "番号未指定" "$_eip_broken_out"
out_hasnt "epic-implement-probe: 壊れた scoped 形式は bare 番号解決へ黙って落ちない(ghを呼ばない)" "gh issue view" "$_eip_broken_out"

_eip_ws="$(mktemp -d)"; mkdir -p "$_eip_ws/.claude"
printf '{ "workspace": true }\n' > "$_eip_ws/.claude/yosage-dev-harness.local.json"
_eip_ws_out="$(cd "$_eip_ws" && PATH="$_eipbin:$PATH" bash "$H/lib/epic-implement-probe.sh" epic "42" 2>&1)"; _eip_ws_rc=$?
if [ "$_eip_ws_rc" -ne 0 ]; then ok "epic-implement-probe: ワークスペース直下での bare 番号は非ゼロ終了(停止)"; else ng "epic-implement-probe: ワークスペース直下での bare 番号は非ゼロ終了(停止)"; fi
out_has   "epic-implement-probe: ワークスペース直下での bare 番号は <owner>/<repo>#<N> 指定を要求するメッセージを出す" '<owner>/<repo>#' "$_eip_ws_out"
out_hasnt "epic-implement-probe: ワークスペース直下での bare 番号は誤ったリポジトリの issue を掴まない(ghを呼ばない)" "gh issue view" "$_eip_ws_out"
rm -rf "$_eip_ws"

_eip_sub_scoped_out="$(cd "$ROOT" && PATH="$_eipbin:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1)"
out_has   "epic-implement-probe: subissues モードは repo 判明時に <owner>/<repo>#<N> 形式で出力(後続dispatchへそのまま渡せる)" "acme/target${HSH}10" "$_eip_sub_scoped_out"
out_has   "epic-implement-probe: subissues モードは重複排除する" "acme/target${HSH}20" "$_eip_sub_scoped_out"
_eip_sub_dupcount="$(printf '%s\n' "$_eip_sub_scoped_out" | grep -c '^acme/target'"$HSH"'10$' || true)"
if [ "$_eip_sub_dupcount" = "1" ]; then ok "epic-implement-probe: subissues モードは同一番号の重複出現を1件に畳む"; else ng "epic-implement-probe: subissues モードは同一番号の重複出現を1件に畳む (got: ${_eip_sub_dupcount})"; fi
out_hasnt "epic-implement-probe: 陽性対照-本文抽出件数とネイティブSub-issue件数が一致する通常系では(要確認)警告が出ない(誤検知しない)" "(要確認)" "$_eip_sub_scoped_out"
rm -rf "$_eipbin"

echo "== epic-implement-probe.sh: Sub-issue番号一覧が空・不完全な場合を対象ゼロ件と区別する =="
# 受け入れ条件: (1)空・不完全と対象ゼロ件を区別できる (2)区別できない場合の挙動が明記されている
# (3)検証位置がsubissuesを使う全手順に効く (4)意図的に壊すと該当アサーションだけ落ちる (5)既存5箇所は無傷。
# ここでは(1)(4)を機械的に固定する((2)(3)はSKILL.md本文のテキストアサーションで固定済み・上記参照)。
#
# 一次レビュー指摘: 件数(totalCount)だけの突き合わせは「関連づけが0件」と「抽出も0件」が同時の
# 正当なゼロ件と、「関連づけが0件なのに抽出は非ゼロ」(突き合わせの相手が存在せず確認不能)の
# 両方で `0 < 0`/`N < 0` がいずれも偽になり後者を検知できなかった(実際に再現された)。件数ではなく
# 集合(nodes)で突き合わせる形に直し、ケース2として追加した(実 Epic での再現は下記コメント参照)。

# ケース1: Epic本文の取得そのものが失敗(gh issue view --json body が非ゼロ終了)。
# 「対象ゼロ件」と混同させないため、標準出力は空のまま・非ゼロ終了・stderrに(要確認)付きで明示する。
_eipbin_bodyfail="$(mktemp -d)"
cat > "$_eipbin_bodyfail/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) exit 1 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_bodyfail/gh"
_eip_bodyfail_stdout="$(cd "$ROOT" && PATH="$_eipbin_bodyfail:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_bodyfail_stderr="$(cd "$ROOT" && PATH="$_eipbin_bodyfail:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
_eip_bodyfail_rc="$(cd "$ROOT" && PATH="$_eipbin_bodyfail:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" >/dev/null 2>&1; echo $?)"
out_is_empty "epic-implement-probe: Epic本文取得の失敗は標準出力が空のまま(空データと誤読させる出力を出さない)" "$_eip_bodyfail_stdout"
if [ "$_eip_bodyfail_rc" -ne 0 ]; then ok "epic-implement-probe: Epic本文取得の失敗は非ゼロ終了(取得失敗を対象ゼロ件と同じexit 0にしない)"; else ng "epic-implement-probe: Epic本文取得の失敗は非ゼロ終了(取得失敗を対象ゼロ件と同じexit 0にしない)"; fi
out_has "epic-implement-probe: Epic本文取得の失敗はstderrに(要確認)付きで明示される" "(要確認)" "$_eip_bodyfail_stderr"
out_has "epic-implement-probe: Epic本文取得の失敗は『取得できていません』と明示され対象ゼロ件と文言上も区別される" "取得できていません" "$_eip_bodyfail_stderr"
rm -rf "$_eipbin_bodyfail"

# ケース2(一次レビューで指摘された実害の再現): ネイティブ Sub-issue のリンクが1件も無い(node解決・
# GraphQLクエリ自体は成功するが集合が空)のに、本文抽出は5件ある。突き合わせる相手がそもそも
# 存在しないため「完全性を確認できない」扱いにする(「正当にゼロ件」でも「不完全と確定」でもない
# 第三の状態)。実際に (非Epicの通常issueで本文が他issueへ1件言及するが当然ネイティブ
# リンクは0件)に対して修正前のコードを実行すると、警告無し・exit 0 で5件相当が出力されてしまう
# ことを実機(gh api を実際に叩いて)確認した上で、このモックで固定する。
_eipbin_orphan="$(mktemp -d)"
cat > "$_eipbin_orphan/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: 依存先は ${M}50 と ${M}51 と ${M}52 と ${M}53 と ${M}54"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_orphan/gh"
_eip_orphan_stdout="$(cd "$ROOT" && PATH="$_eipbin_orphan:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_orphan_stderr="$(cd "$ROOT" && PATH="$_eipbin_orphan:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_has "epic-implement-probe: ネイティブリンクが0件でも本文抽出した一覧はそのまま出力される(握り潰さない)" "acme/target${HSH}50" "$_eip_orphan_stdout"
out_has "epic-implement-probe: ネイティブリンクが0件で本文抽出が非ゼロの場合はstderrに(要確認)付きで明示される(一次レビュー指摘の核心)" "(要確認)" "$_eip_orphan_stderr"
out_has "epic-implement-probe: ネイティブリンクが0件の場合の文言は『突き合わせる相手が存在しません』であり不完全と断定しない" "突き合わせる相手が存在しません" "$_eip_orphan_stderr"
_eip_orphan_count="$(printf '%s\n' "$_eip_orphan_stdout" | grep -c '^acme/target#' || true)"
if [ "$_eip_orphan_count" = "5" ]; then ok "epic-implement-probe: ネイティブリンクが0件(絞り込む基準が無い)でも本文抽出した5件が1件も落ちない(空だからといって全部を落とすのは誤り、の回帰防止)"; else ng "epic-implement-probe: ネイティブリンクが0件(絞り込む基準が無い)でも本文抽出した5件が1件も落ちない(空だからといって全部を落とすのは誤り、の回帰防止) (got: ${_eip_orphan_count})"; fi
rm -rf "$_eipbin_orphan"

# ケース3: 本文取得は成功したが、完全性の照合(ネイティブ Sub-issue のnode ID解決)自体が失敗。
# 「不完全と断定」はしないが「確認できた」とも言わない(要確認)。一覧そのものは出力する。
_eipbin_idfail="$(mktemp -d)"
cat > "$_eipbin_idfail/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: 依存先は ${M}30 と ${M}31"; exit 0 ;;
    *" --json id "*) exit 1 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_idfail/gh"
_eip_idfail_stdout="$(cd "$ROOT" && PATH="$_eipbin_idfail:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_idfail_stderr="$(cd "$ROOT" && PATH="$_eipbin_idfail:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_has "epic-implement-probe: 照合(node ID解決)が失敗しても本文抽出した一覧はそのまま出力される(不完全と決めつけて握り潰さない)" "acme/target${HSH}30" "$_eip_idfail_stdout"
out_has "epic-implement-probe: 照合(node ID解決)の失敗はstderrに(要確認)付きで明示される" "(要確認)" "$_eip_idfail_stderr"
out_has "epic-implement-probe: 照合(node ID解決)の失敗は『確認できません』と明示され不完全と断定する文言にならない" "確認できません" "$_eip_idfail_stderr"
_eip_idfail_count="$(printf '%s\n' "$_eip_idfail_stdout" | grep -c '^acme/target#' || true)"
if [ "$_eip_idfail_count" = "2" ]; then ok "epic-implement-probe: 照合(node ID解決)が失敗した場合も本文抽出した2件が1件も落ちない(絞り込む基準が確認できない場合は絞り込まない)"; else ng "epic-implement-probe: 照合(node ID解決)が失敗した場合も本文抽出した2件が1件も落ちない(絞り込む基準が確認できない場合は絞り込まない) (got: ${_eip_idfail_count})"; fi
rm -rf "$_eipbin_idfail"

# ケース4: 照合は成功し、ネイティブ Sub-issue の集合の一部が本文抽出の集合に含まれない
# =不完全の疑い。一覧が「不完全」であることを検出する本体(受け入れ条件1の核心: 空では
# なく一部の番号が欠けているケース)。実 Epic でネイティブリンクにはあるが本文からは
# 抽出できていない番号が実在することを実機で確認済み(コミットメッセージ・PR本文に記録)。
_eipbin_mismatch="$(mktemp -d)"
cat > "$_eipbin_mismatch/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: 依存先は ${M}40 と ${M}41"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n40\n41\n42\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_mismatch/gh"
_eip_mismatch_stdout="$(cd "$ROOT" && PATH="$_eipbin_mismatch:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_mismatch_stderr="$(cd "$ROOT" && PATH="$_eipbin_mismatch:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_has "epic-implement-probe: ネイティブSub-issueの一部が本文抽出に含まれない場合も一覧そのものは出力される(判断は呼び出し元SKILLへ委ねる)" "acme/target${HSH}40" "$_eip_mismatch_stdout"
out_has "epic-implement-probe: 欠落(不完全の疑い)はstderrに(要確認)付きで明示される(受け入れ条件1の核心)" "(要確認)" "$_eip_mismatch_stderr"
out_has "epic-implement-probe: 欠落している番号自体がstderrに列挙される(42)" "${HSH}42" "$_eip_mismatch_stderr"
out_has "epic-implement-probe: 欠落の警告文言(番号一覧から抜け落ちている可能性)が出る" "抜け落ちている可能性" "$_eip_mismatch_stderr"
# SKILL 側の動的コンテキストが実際に使う呼び出し形(末尾 `2>&1` で標準出力へ
# 合流)そのもので再実行し、一覧(元は標準出力)と(要確認)警告(元は標準エラー)が同じ1本の
# ストリームに両方乗ることを確認する(合流させる側=呼び出し元の変更が効いていることの実証。
# epic-implement-probe.sh 自身の出力先(stdout/stderr の分離)はこの回帰では変えていない)。
_eip_mismatch_merged="$(cd "$ROOT" && PATH="$_eipbin_mismatch:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1)"
out_has "epic-implement-probe: 動的コンテキストと同じ2>&1合流呼び出しで一覧が出る" "acme/target${HSH}40" "$_eip_mismatch_merged"
out_has "epic-implement-probe: 同じ合流呼び出しで(要確認)警告も同じストリームに出る(警告がstderr専用で届く保証が無かった依存の解消)" "(要確認)" "$_eip_mismatch_merged"
rm -rf "$_eipbin_mismatch"

# ケース5(陽性対照・一致): 本文に言及が無く、ネイティブ Sub-issue の集合も空=正当に対象ゼロ件。
# ここで(要確認)が出てはいけない(出れば誤検知であり、ケース2との区別ができていないことになる)。
_eipbin_zero="$(mktemp -d)"
cat > "$_eipbin_zero/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: Sub-issueへの言及なし"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_zero/gh"
_eip_zero_stdout="$(cd "$ROOT" && PATH="$_eipbin_zero:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_zero_stderr="$(cd "$ROOT" && PATH="$_eipbin_zero:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_is_empty "epic-implement-probe: 正当にSub-issueがゼロ件のEpicは標準出力が空(ケース2/4と出力形が同じでも警告の有無で区別できる)" "$_eip_zero_stdout"
out_hasnt "epic-implement-probe: 陽性対照-正当にゼロ件の場合は(要確認)警告が出ない(空・不完全との誤検知が無い)" "(要確認)" "$_eip_zero_stderr"
rm -rf "$_eipbin_zero"

# ケース6(警告ではなく絞り込み): 本文抽出がネイティブ Sub-issue の集合より
# 広い(Sub-issue ではない関連issueへの言及(99番)を含む)。この方向は誤検知の実害が実 Epic で
# 実機確認されている(ネイティブに無い関連issue番号が本文に混在する)ため、
# 警告(要確認)は出さない。代わりに、ネイティブ Sub-issue の集合が非空(=構造的な正本として使える)
# であることを利用し、出力そのものをその集合との積集合へ絞り込む(99番を対象から除外する)。
_eipbin_extra="$(mktemp -d)"
cat > "$_eipbin_extra/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: 依存先は ${M}60 と ${M}61 、関連issueとして ${M}99 にも言及"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n60\n61\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_extra/gh"
_eip_extra_stdout="$(cd "$ROOT" && PATH="$_eipbin_extra:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_extra_stderr="$(cd "$ROOT" && PATH="$_eipbin_extra:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_has   "epic-implement-probe: 絞り込み後もネイティブ集合に含まれる番号(60)は出力に残る" "acme/target${HSH}60" "$_eip_extra_stdout"
out_has   "epic-implement-probe: 絞り込み後もネイティブ集合に含まれる番号(61)は出力に残る" "acme/target${HSH}61" "$_eip_extra_stdout"
out_hasnt "epic-implement-probe: ネイティブ集合に含まれない番号(99)は絞り込みで出力から外れる(受け入れ条件1の核心)" "acme/target${HSH}99" "$_eip_extra_stdout"
out_hasnt "epic-implement-probe: 過剰抽出の絞り込みは(要確認)警告の対象にしない(裁定=警告ではなく絞り込み・実Epicでの誤検知回避)" "(要確認)" "$_eip_extra_stderr"
out_has   "epic-implement-probe: 絞り込みで除外した番号(99)は完全には沈黙させずstderrに残す(抽出側の欠陥に事後で気づけるように)" "${HSH}99" "$_eip_extra_stderr"
out_has   "epic-implement-probe: 絞り込みの情報行は『対象から除外しました』という非警告の文言になる" "対象から除外しました" "$_eip_extra_stderr"
rm -rf "$_eipbin_extra"

# ケース6b(絞り込みが空にならない境界の再確認): 除外前後で出力の行数が2件ぴったりに
# なることを数で固定する(除外対象の99番が別の形(例えば空白区切りの3件目)で紛れ込んだまま残って
# いないかを文字列一致だけでなく件数でも見る。文字列一致だけだと "acme/target990" のような余分な
# 番号が混入していても "acme/target99" への部分一致は起きないため、件数チェックで補完する)。
_eip_extra_count="$(printf '%s\n' "$_eip_extra_stdout" | grep -c '^acme/target#' || true)"
if [ "$_eip_extra_count" = "2" ]; then ok "epic-implement-probe: 絞り込み後の出力はちょうど2件(60,61)に絞られる(件数での固定)"; else ng "epic-implement-probe: 絞り込み後の出力はちょうど2件(60,61)に絞られる(件数での固定) (got: ${_eip_extra_count})"; fi

# ケース6c(裁定の核心・関連づけの集合が空のときは絞り込めない): ネイティブ Sub-issue が1件も無い
# (=絞り込む基準そのものが無い)場合、本文抽出した集合を一切絞り込まず、全件を
# そのまま出力する(「空だからといって全部を落とすのは誤り」の直接固定。ケース2(orphan)は単体
# の存在しか見ていなかったため、ここでは全件が生き残ることを件数でも確認する)。
_eipbin_emptynative="$(mktemp -d)"
cat > "$_eipbin_emptynative/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: 依存先は ${M}60 と ${M}61 、関連issueとして ${M}99 にも言及"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_emptynative/gh"
_eip_emptynative_stdout="$(cd "$ROOT" && PATH="$_eipbin_emptynative:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_emptynative_count="$(printf '%s\n' "$_eip_emptynative_stdout" | grep -c '^acme/target#' || true)"
out_has "epic-implement-probe: 関連づけの集合(ネイティブSub-issue)が空のときは99も含め絞り込まずそのまま出力される(裁定の核心)" "acme/target${HSH}99" "$_eip_emptynative_stdout"
if [ "$_eip_emptynative_count" = "3" ]; then ok "epic-implement-probe: 関連づけの集合が空のときは本文抽出した3件が1件も落ちない(件数での固定・全部落とす誤りの回帰防止)"; else ng "epic-implement-probe: 関連づけの集合が空のときは本文抽出した3件が1件も落ちない(件数での固定・全部落とす誤りの回帰防止) (got: ${_eip_emptynative_count})"; fi
rm -rf "$_eipbin_emptynative"

# ケース6d(一次レビュー指摘): 絞り込みの照合が完全一致(exact match)であることを
# 固定する。一方の桁列がもう一方の桁列に含まれる番号の組(8 と 80)を使う——ネイティブ Sub-issue の
# 集合は{80}のみ(8は含まれない)。照合が部分一致(substring match)に壊れていると、"8" は "80" という
# 文字列の中に部分文字列として現れるため、"ネイティブ集合に含まれる"と誤判定され、絞り込みで除外
# されるべき8が出力に残ってしまう(除外されるべき番号が残る型の欠陥)。この検証は
# acme/target8 と acme/target80 が「行として完全一致するか」で判定する(単純な文字列包含検査
# (out_has/out_hasnt)を使うと、"acme/target8" 自体が "acme/target80" の部分文字列であるため、
# この検証固有の目的(完全一致の固定)を裏切る形で誤判定してしまう。そのため grep -c '^…$' で
# 行全体の一致を数える)。
_eipbin_exactmatch="$(mktemp -d)"
cat > "$_eipbin_exactmatch/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: 依存先は ${M}8 と ${M}80"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n80\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_exactmatch/gh"
_eip_exactmatch_stdout="$(cd "$ROOT" && PATH="$_eipbin_exactmatch:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_exactmatch_stderr="$(cd "$ROOT" && PATH="$_eipbin_exactmatch:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
_eip_exactmatch_has8="$(printf '%s\n' "$_eip_exactmatch_stdout" | grep -c '^acme/target'"$HSH"'8$' || true)"
_eip_exactmatch_has80="$(printf '%s\n' "$_eip_exactmatch_stdout" | grep -c '^acme/target'"$HSH"'80$' || true)"
_eip_exactmatch_total="$(printf '%s\n' "$_eip_exactmatch_stdout" | grep -c '^acme/target#' || true)"
if [ "$_eip_exactmatch_has8" = "0" ]; then ok "epic-implement-probe: 絞り込みの照合は完全一致(8はネイティブ{80}に含まれないので除外される。部分一致だと8を含む誤判定で除外できない)"; else ng "epic-implement-probe: 絞り込みの照合は完全一致(8はネイティブ{80}に含まれないので除外される。部分一致だと8を含む誤判定で除外できない) (unexpected: acme/target8 の行が出力に残っている)"; fi
if [ "$_eip_exactmatch_has80" = "1" ]; then ok "epic-implement-probe: 絞り込みの照合は完全一致(80はネイティブ{80}に含まれるので残る)"; else ng "epic-implement-probe: 絞り込みの照合は完全一致(80はネイティブ{80}に含まれるので残る) (got: ${_eip_exactmatch_has80})"; fi
if [ "$_eip_exactmatch_total" = "1" ]; then ok "epic-implement-probe: 一方が他方の部分文字列になる番号の組でも出力はちょうど1件(80)に絞られる(完全一致の固定・件数での補強)"; else ng "epic-implement-probe: 一方が他方の部分文字列になる番号の組でも出力はちょうど1件(80)に絞られる(完全一致の固定・件数での補強) (got: ${_eip_exactmatch_total})"; fi
out_has "epic-implement-probe: 除外された8はstderrの情報行に列挙される(完全一致で正しく除外されたことの確認)" "${HSH}8" "$_eip_exactmatch_stderr"
rm -rf "$_eipbin_exactmatch"

# ケース7(2度目の一次レビュー指摘・実害の再現): ネイティブ Sub-issue の集合が1ページ(first:100)を
# 超える(150件)。旧実装(1ページしか見ない)では101件目以降が黙って欠落し、この完全性チェック
# 自身が「一覧取得の既定件数上限で枠外が漏れる」という、この手順(epic-implement 手順8)で既に
# 修正済みの欠陥(1件目)を再生産していた。モックは page1(after無し)で1-100・hasNextPage=true・
# endCursor=CURSOR_1 を返し、page2(after=CURSOR_1)で101-150・hasNextPage=false を返す。本文抽出
# 側は1-100のみ(101-150への言及が本文から欠けている状態を再現)。
_eip_page1_150="$(seq 1 100 | sed 's/^/#/' | tr '\n' ' ')"
_eipbin_over100="$(mktemp -d)"
export _EIP_TEST_BODY_OVER100="Epic本文: 依存先は ${_eip_page1_150}"
cat > "$_eipbin_over100/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) printf '%s\n' "$_EIP_TEST_BODY_OVER100"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  case " $* " in
    *" -f after=CURSOR_1 "*)
      printf 'false\t\n'
      seq 101 150
      ;;
    *)
      printf 'true\tCURSOR_1\n'
      seq 1 100
      ;;
  esac
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_over100/gh"
_eip_over100_stderr="$(cd "$ROOT" && PATH="$_eipbin_over100:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
_eip_over100_stdout="$(cd "$ROOT" && PATH="$_eipbin_over100:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
out_has "epic-implement-probe: 150件のネイティブSub-issue(1ページ超)でも100件目までは正しく出力される(ページング機構そのものの健全性)" "acme/target${HSH}1" "$_eip_over100_stdout"
out_has "epic-implement-probe: 150件のネイティブSub-issueのうち101件目以降(1ページ目に無い分)が欠落として検知される(2度目の一次レビュー指摘の核心)" "(要確認)" "$_eip_over100_stderr"
out_has "epic-implement-probe: 101件目以降の欠落番号(150)が具体的にstderrへ列挙される(旧実装は1ページ目しか見ておらず検知不能だった)" "${HSH}150" "$_eip_over100_stderr"
out_has "epic-implement-probe: 境界直後の欠落番号(101)もstderrへ列挙される" "${HSH}101" "$_eip_over100_stderr"
unset _EIP_TEST_BODY_OVER100
rm -rf "$_eipbin_over100"

# ケース8(境界・ページサイズちょうど100件): 1ページで完結し(hasNextPage=false)、本文抽出も
# 100件すべて揃っている場合に誤って(要確認)が出ないことを確認する(ページングを導入したことで
# ちょうど100件の正当なEpicを壊していないか)。2ページ目が呼ばれたかどうかは、gh 呼び出し自体の
# stderr(プローブ側で2>/dev/nullされ握り潰される)ではなく、モック内で副作用として書き出す
# マーカーファイルの有無で判定する(握り潰されない経路で確かめる=空振りしない検証)。
_eip_body_100="$(seq 1 100 | sed 's/^/#/' | tr '\n' ' ')"
_eipbin_exact100="$(mktemp -d)"
_eip_exact100_marker="$(mktemp -u)"
export _EIP_TEST_BODY_EXACT100="Epic本文: 依存先は ${_eip_body_100}"
export _EIP_TEST_MARKER_EXACT100="$_eip_exact100_marker"
cat > "$_eipbin_exact100/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) printf '%s\n' "$_EIP_TEST_BODY_EXACT100"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  case " $* " in
    *" -f after="*)
      touch "$_EIP_TEST_MARKER_EXACT100"
      exit 1
      ;;
    *)
      printf 'false\t\n'
      seq 1 100
      ;;
  esac
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_exact100/gh"
rm -f "$_eip_exact100_marker"
_eip_exact100_stderr="$(cd "$ROOT" && PATH="$_eipbin_exact100:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_hasnt "epic-implement-probe: 境界(ちょうど100件・1ページで完結)では(要確認)警告が出ない(誤検知しない)" "(要確認)" "$_eip_exact100_stderr"
if [ -e "$_eip_exact100_marker" ]; then ng "epic-implement-probe: 境界(ちょうど100件)で2ページ目を要求していない(1ページに収まる場合は問い合わせ回数を増やさない。マーカーファイルの不在で確認=gh呼び出し自体のstderr握り潰しを迂回)"; else ok "epic-implement-probe: 境界(ちょうど100件)で2ページ目を要求していない(1ページに収まる場合は問い合わせ回数を増やさない。マーカーファイルの不在で確認=gh呼び出し自体のstderr握り潰しを迂回)"; fi
unset _EIP_TEST_BODY_EXACT100 _EIP_TEST_MARKER_EXACT100
rm -f "$_eip_exact100_marker"
rm -rf "$_eipbin_exact100"

# ケース9(境界・ページサイズ+1件=101件): ちょうど1件だけ2ページ目に回る最小のケース。本文抽出は
# 1-100のみ(101番目=2ページ目の1件のみが本文から欠けている状態)。2ページ目への継続要求が
# 実際に行われ、かつその1件の欠落が正しく検知されることを確認する(境界を1件跨いだ瞬間に判定が
# 反転する箇所)。
_eip_body_100b="$(seq 1 100 | sed 's/^/#/' | tr '\n' ' ')"
_eipbin_101="$(mktemp -d)"
export _EIP_TEST_BODY_101="Epic本文: 依存先は ${_eip_body_100b}"
cat > "$_eipbin_101/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) printf '%s\n' "$_EIP_TEST_BODY_101"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  case " $* " in
    *" -f after=CURSOR_101 "*)
      printf 'false\t\n101\n'
      ;;
    *)
      printf 'true\tCURSOR_101\n'
      seq 1 100
      ;;
  esac
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_101/gh"
_eip_101_stderr="$(cd "$ROOT" && PATH="$_eipbin_101:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_has "epic-implement-probe: 境界+1件(101件・2ページ目に1件のみ)でも欠落(101)が検知される" "${HSH}101" "$_eip_101_stderr"
out_has "epic-implement-probe: 境界+1件のケースは(要確認)警告が出る" "(要確認)" "$_eip_101_stderr"
unset _EIP_TEST_BODY_101
rm -rf "$_eipbin_101"

# ケース10(一次レビュー指摘・ループ途中の取得失敗を固定): 1ページ目は成功(hasNextPage=true・
# 100件)、2ページ目の取得そのものが失敗する。このとき、それまでに集めた1ページ目分だけの部分
# 集合を「ネイティブSub-issueの全体」として黙って欠落判定に使ってはならない(実際より少ない集合との
# 突き合わせは、真の欠落を見逃す=この課題票で繰り返し出た型と同じ)。正しい挙動は「完全性を
# 確認できない」の分岐へ落ちること。本文抽出は1-50のみにしておく(もし部分集合(1-100)で誤って
# 欠落判定が走ると「...が抜け落ちている」という誤った(かつ本来もっと多いはずの)欠落
# 警告が出る。正しい実装ではこの欠落警告自体が出ず、「取得に失敗しました」側の文言になる)。
_eip_body_50="$(seq 1 50 | sed 's/^/#/' | tr '\n' ' ')"
_eipbin_pagefail="$(mktemp -d)"
export _EIP_TEST_BODY_PAGEFAIL="Epic本文: 依存先は ${_eip_body_50}"
cat > "$_eipbin_pagefail/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) printf '%s\n' "$_EIP_TEST_BODY_PAGEFAIL"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  case " $* " in
    *" -f after=CURSOR_PAGEFAIL "*)
      exit 1
      ;;
    *)
      printf 'true\tCURSOR_PAGEFAIL\n'
      seq 1 100
      ;;
  esac
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_pagefail/gh"
_eip_pagefail_stdout="$(cd "$ROOT" && PATH="$_eipbin_pagefail:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_pagefail_stderr="$(cd "$ROOT" && PATH="$_eipbin_pagefail:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
out_has   "epic-implement-probe: ループ2ページ目の取得失敗時も本文抽出した一覧はそのまま出力される(握り潰さない)" "acme/target${HSH}1" "$_eip_pagefail_stdout"
out_has   "epic-implement-probe: ループ2ページ目の取得失敗は『取得に失敗しました』側の(要確認)警告になる(一次レビュー指摘の核心)" "取得に失敗しました" "$_eip_pagefail_stderr"
out_hasnt "epic-implement-probe: ループ2ページ目の取得失敗時、1ページ目だけの部分集合で欠落判定(抜け落ちている可能性)を行わない(部分集合を正本として使わない)" "抜け落ちている可能性" "$_eip_pagefail_stderr"
_eip_pagefail_count="$(printf '%s\n' "$_eip_pagefail_stdout" | grep -c '^acme/target#' || true)"
if [ "$_eip_pagefail_count" = "50" ]; then ok "epic-implement-probe: ループ途中のページ取得失敗時は本文抽出した50件が1件も落ちない(完全性を確認できない=絞り込む基準も確認できないので絞り込まない)"; else ng "epic-implement-probe: ループ途中のページ取得失敗時は本文抽出した50件が1件も落ちない(完全性を確認できない=絞り込む基準も確認できないので絞り込まない) (got: ${_eip_pagefail_count})"; fi
unset _EIP_TEST_BODY_PAGEFAIL
rm -rf "$_eipbin_pagefail"

# ケース11(欠落側と絞り込みの独立性): 欠落(ネイティブにあるが本文に無い番号)と
# 過剰抽出(本文にあるがネイティブに無い番号)が同一 Epic で同時に起きる場合、両者は互いに干渉せず
# 独立して働くことを固定する。ネイティブ集合={70,71,72}・本文抽出={70,99}(71,72が本文から欠落・
# 99が過剰抽出)。期待: 出力は{70}のみ(71,72は元から本文に無いので出力されようがない・99は絞り込みで
# 除外)、stderrには欠落警告(71,72・(要確認)付き)と絞り込みの情報行(99・(要確認)無し)の両方が出る。
_eipbin_both="$(mktemp -d)"
cat > "$_eipbin_both/gh" <<'EIPGH'
#!/usr/bin/env bash
M='#'
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case " $* " in
    *" --json body "*) echo "Epic本文: 依存先は ${M}70 、関連issueとして ${M}99 にも言及"; exit 0 ;;
    *" --json id "*) echo "GID_EPIC_MOCK"; exit 0 ;;
    *) echo "gh $*"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf 'false\t\n70\n71\n72\n'
  exit 0
fi
echo "gh $*"
EIPGH
chmod +x "$_eipbin_both/gh"
_eip_both_stdout="$(cd "$ROOT" && PATH="$_eipbin_both:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>/dev/null)"
_eip_both_stderr="$(cd "$ROOT" && PATH="$_eipbin_both:$PATH" bash "$H/lib/epic-implement-probe.sh" subissues "acme/target${HSH}42" 2>&1 1>/dev/null)"
_eip_both_count="$(printf '%s\n' "$_eip_both_stdout" | grep -c '^acme/target#' || true)"
out_has   "epic-implement-probe: 欠落と過剰抽出が同時に起きても両者に共通する番号(70)は出力に残る" "acme/target${HSH}70" "$_eip_both_stdout"
out_hasnt "epic-implement-probe: 欠落と過剰抽出が同時に起きても過剰抽出分(99)は絞り込みで出力から外れる(独立して働く)" "acme/target${HSH}99" "$_eip_both_stdout"
if [ "$_eip_both_count" = "1" ]; then ok "epic-implement-probe: 欠落と過剰抽出が同時に起きても出力はちょうど1件(70)に絞られる"; else ng "epic-implement-probe: 欠落と過剰抽出が同時に起きても出力はちょうど1件(70)に絞られる (got: ${_eip_both_count})"; fi
out_has   "epic-implement-probe: 欠落側の警告(71,72)は(要確認)付きで独立して出る" "抜け落ちている可能性" "$_eip_both_stderr"
out_has   "epic-implement-probe: 欠落側の警告には欠落番号(71)が列挙される" "${HSH}71" "$_eip_both_stderr"
out_has   "epic-implement-probe: 欠落側の警告には欠落番号(72)が列挙される" "${HSH}72" "$_eip_both_stderr"
out_has   "epic-implement-probe: 絞り込みの情報行(99除外)も同時に独立して出る" "対象から除外しました" "$_eip_both_stderr"
out_has   "epic-implement-probe: 絞り込みの情報行には除外番号(99)が列挙される" "${HSH}99" "$_eip_both_stderr"
rm -rf "$_eipbin_both"

echo "== epic-scope-resolve.sh: 計画ドキュメント(.epic_docs/)の置き場をcwd固定からワークスペース対応へ =="
# 実際のワークスペース構成(ワークスペース自身が独立した git リポジトリ、実装先=メンバーリポジトリは
# その子ディレクトリに同居)を再現するフィクスチャで検証する(親の兄弟ではなく子であることが重要。
# gh-review.sh の自組織識別子導出テストと同じ構成)。
_esr_ws="$(mktemp -d)"
(cd "$_esr_ws" && git init -q)
_esr_member="$_esr_ws/member"; mkdir -p "$_esr_member"
(cd "$_esr_member" && git init -q)

out_has "epic-scope-resolve: outermost-root はワークスペース自身から見て自分自身" "$_esr_ws" "$(cd "$_esr_ws" && bash "$H/lib/epic-scope-resolve.sh" outermost-root)"
out_has "epic-scope-resolve: outermost-root はメンバーリポジトリから見てもワークスペース(子から親を辿る)" "$_esr_ws" "$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" outermost-root)"

# 観測1(最重要・の核心): 計画ドキュメントがワークスペース側にしか無くても、実装先(メンバー
# リポジトリ)の中から探索して見つけられる。
_esr_locate_before="$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" locate-docs myepic 2>&1)"; _esr_locate_before_rc=$?
exit_is "epic-scope-resolve: locate-docs は計画が無ければ exit 1(そもそも無い。前提が欠けている exit 2 とは別コード)" 1 "$_esr_locate_before_rc"
out_has "epic-scope-resolve: 計画が無いときは「そもそも計画ドキュメントが存在しない」旨をstderrへ" "そもそも計画ドキュメントが存在しない" "$_esr_locate_before"

mkdir -p "$_esr_ws/.epic_docs/myepic/phase1"
_esr_locate_after="$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" locate-docs myepic 2>&1)"; _esr_locate_after_rc=$?
if [ "$_esr_locate_after_rc" -eq 0 ]; then ok "epic-scope-resolve: 計画ドキュメントがワークスペース側にあれば実装先リポジトリの中からでも見つかる"; else ng "epic-scope-resolve: 計画ドキュメントがワークスペース側にあれば実装先リポジトリの中からでも見つかる"; fi
out_has "epic-scope-resolve: locate-docs はワークスペース側の絶対パスを表示する" "$_esr_ws/.epic_docs/myepic" "$_esr_locate_after"

# 観測2: フェーズによるスコープ絞りが実際に機能する(メンバーリポジトリの中から phase1 を解決できる)。
_esr_phase_ok="$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" locate-phase myepic phase1 2>&1)"; _esr_phase_ok_rc=$?
if [ "$_esr_phase_ok_rc" -eq 0 ]; then ok "epic-scope-resolve: フェーズによるスコープ絞りがワークスペース越しに機能する"; else ng "epic-scope-resolve: フェーズによるスコープ絞りがワークスペース越しに機能する"; fi
out_has "epic-scope-resolve: locate-phase はフェーズディレクトリの絶対パスを表示する" "$_esr_ws/.epic_docs/myepic/phase1" "$_esr_phase_ok"

# 観測3(silent フォールバックの回帰・最重要): 計画ドキュメント自体は見つかるが、指定フェーズが
# 無い場合は「そもそも計画が無い」(exit 1)とは異なる終了コード(exit 3)・異なる理由で報告し、
# 黙って依存ウェーブへ落ちて良いケース(計画が無い)と区別できる。
_esr_phase_missing="$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" locate-phase myepic phase9 2>&1)"; _esr_phase_missing_rc=$?
exit_is "epic-scope-resolve: 計画はあるが指定フェーズが無い場合は exit 3(計画が無い場合のexit 1とは別コード)" 3 "$_esr_phase_missing_rc"
out_has "epic-scope-resolve: フェーズが見つからない理由は「あるのに見つけられない」と明示し「計画が無い」と区別する" "あるのに見つけられていない" "$_esr_phase_missing"
out_hasnt "epic-scope-resolve: フェーズが見つからない場合のメッセージは「そもそも計画ドキュメントが存在しない」を再利用しない(理由が違う)" "そもそも計画ドキュメントが存在しない" "$_esr_phase_missing"

# 観測4: git リポジトリの外・引数不足は exit 2(前提が欠けている)で区別される。
_esr_outside="$(mktemp -d)"
_esr_outside_out="$(cd "$_esr_outside" && bash "$H/lib/epic-scope-resolve.sh" locate-docs myepic 2>&1)"; _esr_outside_rc=$?
exit_is "epic-scope-resolve: git リポジトリの外での locate-docs は exit 2" 2 "$_esr_outside_rc"
rm -rf "$_esr_outside"
_esr_noargs_rc=0; bash "$H/lib/epic-scope-resolve.sh" locate-docs >/dev/null 2>&1 || _esr_noargs_rc=$?
exit_is "epic-scope-resolve: epic-name 未指定の locate-docs は exit 2" 2 "$_esr_noargs_rc"

# 観測5(後方互換・単一リポジトリ): 上に他のリポジトリが無ければ自分自身が最も外側になるため、
# 従来どおり cwd 直下の .epic_docs/ がそのまま置き場になる。
_esr_solo="$(mktemp -d)"
(cd "$_esr_solo" && git init -q && mkdir -p .epic_docs/soloepic/phase2)
_esr_solo_out="$(cd "$_esr_solo" && bash "$H/lib/epic-scope-resolve.sh" locate-phase soloepic phase2 2>&1)"; _esr_solo_rc=$?
if [ "$_esr_solo_rc" -eq 0 ]; then ok "epic-scope-resolve: 単一リポジトリでは従来どおりcwd直下の.epic_docs/を解決する(後方互換)"; else ng "epic-scope-resolve: 単一リポジトリでは従来どおりcwd直下の.epic_docs/を解決する(後方互換)"; fi
out_has "epic-scope-resolve: 単一リポジトリでの解決先はcwd直下" "$_esr_solo/.epic_docs/soloepic/phase2" "$_esr_solo_out"
rm -rf "$_esr_solo"

out_has "epic-scope-resolve: 不明な mode はエラー終了" "不明な mode" "$(bash "$H/lib/epic-scope-resolve.sh" bogus 2>&1)"
out_has "epic-scope-resolve: 不明なmodeのエラーメッセージにlist-phasesも案内される" "list-phases" "$(bash "$H/lib/epic-scope-resolve.sh" bogus 2>&1)"

echo "== epic-scope-resolve.sh: list-phases mode(epic-implementのスコープ無し完走が使うフェーズ列挙) =="
# phase1 始まりとは限らない前提(0/10も混在)・非数値サフィックス(phaseX)は対象外、を1フィクスチャで検証する。
mkdir -p "$_esr_ws/.epic_docs/myepic/phase0" "$_esr_ws/.epic_docs/myepic/phase2" "$_esr_ws/.epic_docs/myepic/phase10" "$_esr_ws/.epic_docs/myepic/phaseX" "$_esr_ws/.epic_docs/myepic/notaphase"
_esr_list_out="$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" list-phases myepic 2>&1)"; _esr_list_rc=$?
exit_is "epic-scope-resolve: list-phases は計画・フェーズが見つかれば exit 0" 0 "$_esr_list_rc"
_esr_list_expected="phase0
phase1
phase2
phase10"
if [ "$_esr_list_out" = "$_esr_list_expected" ]; then
  ok "epic-scope-resolve: list-phases は phase<N> ディレクトリを番号の昇順で列挙する(phase1始まり前提を置かず0/10混在でも正しく並ぶ)"
else
  ng "epic-scope-resolve: list-phases は phase<N> ディレクトリを番号の昇順で列挙する(phase1始まり前提を置かず0/10混在でも正しく並ぶ) (got: $_esr_list_out)"
fi
out_hasnt "epic-scope-resolve: list-phases は非数値サフィックス(phaseX)のディレクトリを対象外にする" "phaseX" "$_esr_list_out"
out_hasnt "epic-scope-resolve: list-phases はphase接頭辞を持たないディレクトリ(notaphase)を対象外にする" "notaphase" "$_esr_list_out"

# 計画ドキュメントはあるがフェーズ分割していない Epic: 空出力・exit 0(「そもそも計画が無い」exit 1とは区別)。
mkdir -p "$_esr_ws/.epic_docs/nophaseepic"
_esr_list_empty_out="$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" list-phases nophaseepic 2>&1)"; _esr_list_empty_rc=$?
exit_is "epic-scope-resolve: list-phases はフェーズ定義が無くても計画ドキュメントがあれば exit 0(空出力)" 0 "$_esr_list_empty_rc"
if [ -z "$_esr_list_empty_out" ]; then
  ok "epic-scope-resolve: list-phases はフェーズ未分割の Epic で空出力を返す(そもそも計画が無い場合と区別)"
else
  ng "epic-scope-resolve: list-phases はフェーズ未分割の Epic で空出力を返す(そもそも計画が無い場合と区別) (got: $_esr_list_empty_out)"
fi

# そもそも計画ドキュメント自体が無い場合は locate-docs と同じ exit 1・同じ理由文言を再利用する。
_esr_list_noplan_out="$(cd "$_esr_member" && bash "$H/lib/epic-scope-resolve.sh" list-phases neverexisted 2>&1)"; _esr_list_noplan_rc=$?
exit_is "epic-scope-resolve: list-phases は計画ドキュメント自体が無い場合 exit 1(locate-docs と同じコード)" 1 "$_esr_list_noplan_rc"
out_has "epic-scope-resolve: list-phasesの計画無し理由はlocate-docsと同じ文言を再利用する" "そもそも計画ドキュメントが存在しない" "$_esr_list_noplan_out"

_esr_list_noargs_rc=0; bash "$H/lib/epic-scope-resolve.sh" list-phases >/dev/null 2>&1 || _esr_list_noargs_rc=$?
exit_is "epic-scope-resolve: epic-name 未指定の list-phases は exit 2" 2 "$_esr_list_noargs_rc"

rm -rf "$_esr_ws"

echo "== epic-scope-resolve.sh: 計画が Epic ブランチの上にだけあるとき(exit 4) =="
# 単一リポジトリの導入先: 計画の正本は Epic ブランチにあり、メインは既定ブランチにいる。
_esr_b="$(mktemp -d)"
mk_bare_remote_clone "$_esr_b" --default main
_esr_w="$_esr_b/work"
git -C "$_esr_w" checkout -q -b epic/e1
mkdir -p "$_esr_w/.epic_docs/e1/phase1" "$_esr_w/.epic_docs/e1/phase2"
printf 'plan-body\n' > "$_esr_w/.epic_docs/e1/README.md"
printf 'phase1-body\n' > "$_esr_w/.epic_docs/e1/phase1/plan.md"
printf 'phase2-body\n' > "$_esr_w/.epic_docs/e1/phase2/plan.md"
printf 'x\n' > "$_esr_w/.epic_docs/e1/notes.txt"
gitc -C "$_esr_w" add .epic_docs
gitc -C "$_esr_w" commit -q -m "docs: plan"
git -C "$_esr_w" push -q origin epic/e1
git -C "$_esr_w" checkout -q main
_esr_run() { (cd "$_esr_w" && bash "$H/lib/epic-scope-resolve.sh" "$@"); }

# 作業ツリーに無い(既定ブランチにいる)
[ ! -e "$_esr_w/.epic_docs" ] && ok "epic-scope-resolve(ブランチ): 前提: 既定ブランチの作業ツリーに計画は無い" || ng "epic-scope-resolve(ブランチ): 前提: 既定ブランチの作業ツリーに計画は無い"

# origin/epic/<name> と epic/<name> の両方がある → origin 側を先に返す
_esr_o="$(_esr_run locate-docs e1 2>/dev/null)"; _esr_o_rc=$?
exit_is "epic-scope-resolve(ブランチ): Epic ブランチにだけ計画があれば locate-docs は exit 4" 4 "$_esr_o_rc"
if [ "$_esr_o" = "refs/remotes/origin/epic/e1:.epic_docs/e1" ]; then ok "epic-scope-resolve(ブランチ): stdout は <ref>:.epic_docs/<name>(origin 側を先に探す)"; else ng "epic-scope-resolve(ブランチ): stdout は <ref>:.epic_docs/<name>(origin 側を先に探す)"; fi
_esr_o_err="$(_esr_run locate-docs e1 2>&1 >/dev/null)"
out_has "epic-scope-resolve(ブランチ): stderr に git show で読む案内" "git show" "$_esr_o_err"
# 統合した形: stdout の値をそのまま git show に渡すと中身が読める
_esr_show="$(git -C "$_esr_w" show "$_esr_o/README.md" 2>&1)"
if [ "$_esr_show" = "plan-body" ]; then ok "epic-scope-resolve(ブランチ): exit 4 の stdout を git show に渡すと計画の中身が読める"; else ng "epic-scope-resolve(ブランチ): exit 4 の stdout を git show に渡すと計画の中身が読める"; fi
# 2回目も同じ結果
_esr_o2="$(_esr_run locate-docs e1 2>/dev/null)"; _esr_o2_rc=$?
exit_is "epic-scope-resolve(ブランチ): 2回目の locate-docs も exit 4" 4 "$_esr_o2_rc"
if [ "$_esr_o2" = "$_esr_o" ]; then ok "epic-scope-resolve(ブランチ): 2回目の stdout も同じ"; else ng "epic-scope-resolve(ブランチ): 2回目の stdout も同じ"; fi
# 作業ツリーに残骸を作らない
[ ! -e "$_esr_w/.epic_docs" ] && ok "epic-scope-resolve(ブランチ): 作業ツリーへ展開しない" || ng "epic-scope-resolve(ブランチ): 作業ツリーへ展開しない"

# フェーズ: ある → exit 4 / 無い → exit 3
_esr_p="$(_esr_run locate-phase e1 phase1 2>/dev/null)"; _esr_p_rc=$?
exit_is "epic-scope-resolve(ブランチ): ブランチの上にフェーズがあれば locate-phase は exit 4" 4 "$_esr_p_rc"
if [ "$_esr_p" = "refs/remotes/origin/epic/e1:.epic_docs/e1/phase1" ]; then ok "epic-scope-resolve(ブランチ): locate-phase の stdout は <ref>:.epic_docs/<name>/<phase>"; else ng "epic-scope-resolve(ブランチ): locate-phase の stdout は <ref>:.epic_docs/<name>/<phase>"; fi
if [ "$(git -C "$_esr_w" show "$_esr_p/plan.md" 2>&1)" = "phase1-body" ]; then ok "epic-scope-resolve(ブランチ): locate-phase の値で git show できる"; else ng "epic-scope-resolve(ブランチ): locate-phase の値で git show できる"; fi
_esr_pm_err="$(_esr_run locate-phase e1 phase9 2>&1 >/dev/null)"; _esr_pm_rc=$?
exit_is "epic-scope-resolve(ブランチ): ブランチの上にフェーズが無ければ locate-phase は exit 3" 3 "$_esr_pm_rc"
out_has "epic-scope-resolve(ブランチ): フェーズが無い理由は「あるのに見つけられていない」" "あるのに見つけられていない" "$_esr_pm_err"
# ファイル(notes.txt)はフェーズとして扱わない
_esr_pf="$(_esr_run locate-phase e1 notes.txt 2>/dev/null)"; _esr_pf_rc=$?
exit_is "epic-scope-resolve(ブランチ): ディレクトリでないものはフェーズにならない(exit 3)" 3 "$_esr_pf_rc"
# 列挙
_esr_l="$(_esr_run list-phases e1 2>/dev/null)"; _esr_l_rc=$?
exit_is "epic-scope-resolve(ブランチ): list-phases はブランチの上なら exit 4" 4 "$_esr_l_rc"
_esr_l_want="$(printf 'phase1\nphase2')"
if [ "$_esr_l" = "$_esr_l_want" ]; then ok "epic-scope-resolve(ブランチ): list-phases はサブディレクトリの phase<N> だけを昇順で列挙する"; else ng "epic-scope-resolve(ブランチ): list-phases はサブディレクトリの phase<N> だけを昇順で列挙する"; fi
if [ "$(_esr_run list-phases e1 2>/dev/null)" = "$_esr_l" ]; then ok "epic-scope-resolve(ブランチ): list-phases の2回目も同じ結果"; else ng "epic-scope-resolve(ブランチ): list-phases の2回目も同じ結果"; fi

# ローカルの epic/<name> だけ(origin/epic/<name> が無い)
git -C "$_esr_w" update-ref -d refs/remotes/origin/epic/e1
_esr_lo="$(_esr_run locate-docs e1 2>/dev/null)"; _esr_lo_rc=$?
exit_is "epic-scope-resolve(ブランチ): ローカルの epic/<name> だけでも exit 4" 4 "$_esr_lo_rc"
if [ "$_esr_lo" = "refs/heads/epic/e1:.epic_docs/e1" ]; then ok "epic-scope-resolve(ブランチ): ローカルだけの場合の ref は refs/heads/epic/<name>"; else ng "epic-scope-resolve(ブランチ): ローカルだけの場合の ref は refs/heads/epic/<name>"; fi
_esr_lp="$(_esr_run locate-phase e1 phase2 2>/dev/null)"; _esr_lp_rc=$?
exit_is "epic-scope-resolve(ブランチ): ローカルだけでも locate-phase は exit 4" 4 "$_esr_lp_rc"

# フェーズ名は固定文字列で比べる(`phase.` が phase1 に一致しない)
_esr_re_rc=0; _esr_run locate-phase e1 'phase.' >/dev/null 2>&1 || _esr_re_rc=$?
exit_is "epic-scope-resolve(ブランチ): フェーズ名は正規表現でなく固定文字列(phase. は exit 3)" 3 "$_esr_re_rc"

# .epic_docs/<name> がファイル(blob)なら計画ではない → exit 1
git -C "$_esr_w" checkout -q -b epic/bl main
printf 'f\n' > "$_esr_w/.epic_docs_tmp"; mkdir -p "$_esr_w/.epic_docs"; mv "$_esr_w/.epic_docs_tmp" "$_esr_w/.epic_docs/bl"
gitc -C "$_esr_w" add .epic_docs; gitc -C "$_esr_w" commit -q -m "docs: file"
git -C "$_esr_w" checkout -q main; rm -rf "$_esr_w/.epic_docs"
_esr_bl_rc=0; _esr_run locate-docs bl >/dev/null 2>&1 || _esr_bl_rc=$?
exit_is "epic-scope-resolve(ブランチ): .epic_docs/<name> がファイルなら locate-docs は exit 1" 1 "$_esr_bl_rc"
_esr_bl2_rc=0; _esr_run list-phases bl >/dev/null 2>&1 || _esr_bl2_rc=$?
exit_is "epic-scope-resolve(ブランチ): .epic_docs/<name> がファイルなら list-phases も exit 1" 1 "$_esr_bl2_rc"

# epic-name に / を含む(.epic_docs の下を1段掘った名前)
git -C "$_esr_w" checkout -q -b epic/h/x main
mkdir -p "$_esr_w/.epic_docs/h/x/phase1" "$_esr_w/.epic_docs/h/x/phase3"
printf 'a\n' > "$_esr_w/.epic_docs/h/x/phase1/plan.md"; printf 'b\n' > "$_esr_w/.epic_docs/h/x/phase3/plan.md"
gitc -C "$_esr_w" add .epic_docs; gitc -C "$_esr_w" commit -q -m "docs: slash plan"
git -C "$_esr_w" checkout -q main; rm -rf "$_esr_w/.epic_docs"
_esr_s="$(_esr_run locate-docs h/x 2>/dev/null)"; _esr_s_rc=$?
exit_is "epic-scope-resolve(ブランチ): epic-name に / を含んでも locate-docs は exit 4" 4 "$_esr_s_rc"
if [ "$_esr_s" = "refs/heads/epic/h/x:.epic_docs/h/x" ]; then ok "epic-scope-resolve(ブランチ): / を含む名前の stdout"; else ng "epic-scope-resolve(ブランチ): / を含む名前の stdout (got: $_esr_s)"; fi
_esr_sp="$(_esr_run locate-phase h/x phase1 2>/dev/null)"; _esr_sp_rc=$?
exit_is "epic-scope-resolve(ブランチ): / を含む名前でも locate-phase は exit 4" 4 "$_esr_sp_rc"
if [ "$(git -C "$_esr_w" show "$_esr_sp/plan.md")" = "a" ]; then ok "epic-scope-resolve(ブランチ): / を含む名前の locate-phase の値で git show できる"; else ng "epic-scope-resolve(ブランチ): / を含む名前の locate-phase の値で git show できる"; fi
_esr_sre_rc=0; _esr_run locate-phase h/x 'phase.' >/dev/null 2>&1 || _esr_sre_rc=$?
exit_is "epic-scope-resolve(ブランチ): / を含む名前でも phase. は exit 3(phase1 に一致しない)" 3 "$_esr_sre_rc"
_esr_sl="$(_esr_run list-phases h/x 2>/dev/null)"; _esr_sl_rc=$?
exit_is "epic-scope-resolve(ブランチ): / を含む名前の list-phases は exit 4" 4 "$_esr_sl_rc"
_esr_sl_want="$(printf 'phase1\nphase3')"
if [ "$_esr_sl" = "$_esr_sl_want" ]; then ok "epic-scope-resolve(ブランチ): / を含む名前の list-phases の列挙"; else ng "epic-scope-resolve(ブランチ): / を含む名前の list-phases の列挙 (got: $_esr_sl)"; fi

# どちらにも無い → exit 1(Epic ブランチはあるが計画が入っていない場合も含む)
_esr_none="$(_esr_run locate-docs nosuch 2>&1)"; _esr_none_rc=$?
exit_is "epic-scope-resolve(ブランチ): どちらにも無ければ exit 1" 1 "$_esr_none_rc"
out_has "epic-scope-resolve(ブランチ): どちらにも無いときは従来どおり「そもそも計画ドキュメントが存在しない」" "そもそも計画ドキュメントが存在しない" "$_esr_none"
git -C "$_esr_w" branch -q epic/empty main
_esr_empty_rc=0; _esr_run locate-docs empty >/dev/null 2>&1 || _esr_empty_rc=$?
exit_is "epic-scope-resolve(ブランチ): Epic ブランチはあるが計画が入っていなければ exit 1" 1 "$_esr_empty_rc"
_esr_nol_rc=0; _esr_run list-phases nosuch >/dev/null 2>&1 || _esr_nol_rc=$?
exit_is "epic-scope-resolve(ブランチ): list-phases も計画が無ければ exit 1" 1 "$_esr_nol_rc"

# 作業ツリーにあれば従来どおり exit 0(ブランチより優先)
git -C "$_esr_w" checkout -q epic/e1
_esr_wt_rc=0; _esr_wt="$(_esr_run locate-docs e1 2>/dev/null)" || _esr_wt_rc=$?
exit_is "epic-scope-resolve(ブランチ): 作業ツリーに計画があれば従来どおり exit 0" 0 "$_esr_wt_rc"
if [ "$(cd "$_esr_wt" && pwd -P)" = "$(cd "$_esr_w" && pwd -P)/.epic_docs/e1" ]; then ok "epic-scope-resolve(ブランチ): 作業ツリーにあるときの stdout は絶対パス"; else ng "epic-scope-resolve(ブランチ): 作業ツリーにあるときの stdout は絶対パス"; fi
rm -rf "$_esr_b"

file_is "lib: epic-scope-resolve.sh は実行権限を持つ" "$H/lib/epic-scope-resolve.sh"
if [ -x "$H/lib/epic-scope-resolve.sh" ]; then ok "lib: epic-scope-resolve.sh に実行権限が付いている"; else ng "lib: epic-scope-resolve.sh に実行権限が付いている"; fi

echo "== git-outermost-root.sh: 最も外側のリポジトリを辿る処理を共通化し、gh-review.sh / epic-scope-resolve.sh のバイト単位重複を解消 =="
# 以前は「現在地から上へ辿って最も外側の git リポジトリを見つける」ループが
# epic-scope-resolve.sh(esr_outermost_root)と gh-review.sh(_ghr_collect_own_identifiers)に
# バイト単位で重複しており、一致をテストで固定する一時的な措置が入っていた。本ブロックは
# その一時的な措置(一致の固定)を、共通化の実体(1箇所への集約と両者からの利用)を検証する
# 形へ置き換える。
file_is "lib: git-outermost-root.sh が存在" "$H/lib/git-outermost-root.sh"
_gor_body="$(cat "$H/lib/git-outermost-root.sh" 2>/dev/null)"
out_has "git-outermost-root.sh: git_outermost_root() を定義する" 'git_outermost_root() {' "$_gor_body"

_esr_body="$(cat "$H/lib/epic-scope-resolve.sh" 2>/dev/null)"
_ghr_body2="$(cat "$H/lib/gh-review.sh" 2>/dev/null)"
out_has "epic-scope-resolve.sh: git-outermost-root.sh を source する" 'source "$(dirname "${BASH_SOURCE[0]}")/git-outermost-root.sh"' "$_esr_body"
out_has "gh-review.sh: git-outermost-root.sh を source する" 'source "$(dirname "${BASH_SOURCE[0]}")/git-outermost-root.sh"' "$_ghr_body2"
out_has "epic-scope-resolve.sh: outermost-root モードは共通関数 git_outermost_root を呼ぶ" 'outermost-root) git_outermost_root ;;' "$_esr_body"
out_has "gh-review.sh: 自組織識別子の導出は共通関数 git_outermost_root を呼ぶ" 'outer_top="$(git_outermost_root)"' "$_ghr_body2"

# 探索ループの本体(識別用の行)が、共有先(git-outermost-root.sh)以外の場所で再実装されて
# いない=1箇所に寄っていることを確認する(重複が解消されたことの直接検証)。
out_hasnt "epic-scope-resolve.sh: 探索ループが再実装されていない(共通化により消えているはず)" 'outer_top="$own_top"' "$_esr_body"
out_hasnt "gh-review.sh: 探索ループが再実装されていない(共通化により消えているはず)" 'outer_top="$own_top"' "$_ghr_body2"
out_has "git-outermost-root.sh: 探索ループの実体はここに1箇所だけある" 'outer_top="$own_top"' "$_gor_body"

echo "== epic-create-docs / epic-create-issues: .epic_docs/ の置き場をワークスペース対応へ =="
_ecd_body="$(cat "$H/skills/epic-create-docs/SKILL.md" 2>/dev/null)"
out_has "epic-create-docs: .epic_docs/ の置き場を epic-scope-resolve.sh の outermost-root で解決する" "yosage-dev-harness-epic-scope-resolve outermost-root" "$_ecd_body"
out_hasnt "epic-create-docs: cwd直下の .epic_docs/ 決め打ちの ls コマンドが残っていない" 'ls .epic_docs/' "$_ecd_body"

echo "== epic-create-docs: Sub-issue 分割基準に検証可能性・取り込み可能性・検証条件の質を追加 =="
out_hasnt "epic-create-docs: サイズのみを目安とする旧文言が残っていない(サイズ基準1本化への回帰防止)" 'Sub-issue の粒度は「1 PR で完結する」サイズを目安にする' "$_ecd_body"
out_has "epic-create-docs: 分割基準1(独立に検証できるか)が明記されている" "独立に検証できるか" "$_ecd_body"
out_has "epic-create-docs: 分割基準2(独立に取り込めるか)が明記されている" "独立に取り込めるか" "$_ecd_body"
out_has "epic-create-docs: 独立に検証できる基準に、独立に取り込めるを満たさない対比例がある(一次レビュー)" "満たすが「独立に取り込めるか」を満たさない例は" "$_ecd_body"
out_has "epic-create-docs: 独立に取り込める基準に、独立に検証できるを満たさない対比例がある(一次レビュー)" "満たすが「独立に検証できるか」を満たさない例は" "$_ecd_body"
out_has "epic-create-docs: 両基準の一方でも満たさない場合は1つのSub-issueにまとめる旨が明記されている" "1つの Sub-issue にまとめる" "$_ecd_body"
out_has "epic-create-docs: 2基準の結果が取り込み先の判断の材料になる旨が明記されている" "取り込み先の判断の材料になる" "$_ecd_body"
out_has "epic-create-docs: 複数の独立した利用側が同じ新設基盤を使う場合の判定例がある" "残りの利用側はそれぞれ独立した Sub-issue に分けられる" "$_ecd_body"
out_has "epic-create-docs: 対称な実装だからという理由は2基準に根拠が無くまとめる理由にならない旨が明記されている" "「対称な実装だから一緒に」は2基準のいずれにも根拠を持たない判断であり" "$_ecd_body"
out_has "epic-create-docs: 並列は競合を避けた結果であり目的ではない旨が明記されている(直列許容)" "競合を避けた結果であって目的ではない" "$_ecd_body"
out_has "epic-create-docs: 検証条件は統合された構成で観測する観点を判断の分岐点として持つ(一次レビュー)" "統合された構成で観測する（成果物が存在することではなく" "$_ecd_body"
out_has "epic-create-docs: 単体構成でファイルが存在するだけでは統合構成観測を満たさない旨が明記されている(一次レビュー)" "単体構成で「ファイルが存在する」を満たしても、この観点は満たさない" "$_ecd_body"
out_has "epic-create-docs: 検証方法の質(両方向)の観点がある" "両方向（既定値が効くこと" "$_ecd_body"
out_has "epic-create-docs: 検証方法の質(失敗するべきときに失敗)の観点がある" "失敗するべきときに実際に失敗すること" "$_ecd_body"
out_has "epic-create-docs: 検証方法の質(2回目の実行)の観点がある" "2回目の実行でも壊れないこと" "$_ecd_body"
out_has "epic-create-docs: 検証方法の質(状態が残っていない環境)の観点がある" "状態が残っていない環境" "$_ecd_body"

echo "== epic-create-docs: 実装内容節に具体的観点を追加しコード例の一致不要規定を明確化 =="
out_hasnt "epic-create-docs: コード例は最終実装と一致する必要はないという旧文言が残っていない(具体度低下と読める表現の回帰防止)" 'コード例は実装の方向性を示すもの。最終実装と一致する必要はない' "$_ecd_body"
out_has "epic-create-docs: 実装内容節の導入文(方向性の散文説明で済ませない旨)が明記されている" '`## 実装内容` は「具体的な変更内容」だけでなく、方向性の散文説明で済ませない' "$_ecd_body"
out_has "epic-create-docs: 実装内容の観点(型/スキーマ/シグネチャを実際の記法で書く)が明記されている" "新規に定義する型・スキーマ・関数シグネチャは、実際の記法で書く" "$_ecd_body"
out_has "epic-create-docs: 実装内容の観点(分岐条件の列挙)が明記されている" "分岐条件（成功/失敗/エッジケース）を列挙し、それぞれの処理を書く" "$_ecd_body"
out_has "epic-create-docs: 実装内容の観点(既存コードとの接続点)が明記されている" "既存コードとの接続点（呼び出し元・呼び出し先）を、具体的なファイルパス・シンボル名で示す" "$_ecd_body"
out_has "epic-create-docs: コード例の一致不要規定が具体度低下を意味しない旨に書き直されている" "「最終実装と一致しなくてよい」は「具体度を下げてよい」の言い換えではない" "$_ecd_body"

_eci_scope_body="$(cat "$H/skills/epic-create-issues/SKILL.md" 2>/dev/null)"
out_has "epic-create-issues: 実装先リポジトリと最も外側のリポジトリが異なる場合の扱いを明記" "最も外側のリポジトリと異なる場合" "$_eci_scope_body"
out_has "epic-create-issues: --repo を gh issue create / gh issue view / gh-subissue-link.sh へ通す旨を明記" '--repo <owner>/<repo>' "$_eci_scope_body"

# follow-up: 注意事項の「PR は Sub-issue ブランチから Epic ブランチへ作成する」という無条件記述を、
# pr-loop.md の既定(develop)/選択(まとめる場合のみ epic ブランチ)へ揃える。
out_has "epic-create-issues: 注意事項に PR の取り込み先は Sub-issue 本文の取り込み先に従う旨を明記" "PR の取り込み先は、Sub-issue 本文の \`## 取り込み先\` に従う" "$_eci_scope_body"
out_hasnt "epic-create-issues: PR が Sub-issue ブランチから Epic ブランチへ無条件で作成されるという旧文言が残っていない" "PR は Sub-issue ブランチから Epic ブランチへ作成する" "$_eci_scope_body"

echo "== epic-create-issues: 手順5(Epicブランチ作成・.epic_docs反映)の既定(単一リポジトリ)経路はpushを1回に保つ(cross-repo対応で分岐を足した際の回帰防止) =="
# cross-repo構成向けに分岐を足した際、既定(単一リポジトリ)経路のpushが誤って2回になる回帰が
# 一次レビューで指摘された(ブランチ作成直後の無条件pushと、単一リポジトリ分岐内でのpushが
# 重複していた)。既定経路を重くしない(multi-repo対応が単一リポジトリ利用者に摩擦を足さない)
# ことを、手順5の本文から機械的に固定する。
_eci_step5_full="$(sed -n '/^### 5\. Epic ブランチ作成/,/^### 6\. /p' "$H/skills/epic-create-issues/SKILL.md")"
if [ -z "$_eci_step5_full" ]; then
  ng "epic-create-issues: 手順5セクションの抽出に失敗(見出しの文言が変わった可能性。抽出パターンを見直すこと)"
else
  # 既定(単一リポジトリ)経路 = 手順5の先頭から「異なる場合」分岐の直前まで
  # (共通の前置き ＋ 「同じ場合」分岐。単一リポジトリはこちらしか通らない)。
  _eci_step5_default_path="$(awk '/^- \*\*実装先リポジトリが最も外側のリポジトリと異なる場合\*\*/{exit} {print}' <<< "$_eci_step5_full")"
  _eci_step5_default_push_count="$(printf '%s\n' "$_eci_step5_default_path" | grep -c '^ *git push')"
  if [ "$_eci_step5_default_push_count" = "1" ]; then
    ok "epic-create-issues: 既定(単一リポジトリ)経路のpushはちょうど1回"
  else
    ng "epic-create-issues: 既定(単一リポジトリ)経路のpushが1回ではない(got: ${_eci_step5_default_push_count}回)。既定経路を重くしない(multi-repo対応が単一リポジトリ利用者に摩擦を足さない)方針に反する"
  fi
  # 手順全体(単一リポジトリ分岐＋ワークスペース分岐)を通してpushはちょうど2回
  # (各分岐で1回ずつ。0回=ブランチが一切pushされない・3回以上=どこかで重複、のどちらも検知する)。
  _eci_step5_total_push_count="$(printf '%s\n' "$_eci_step5_full" | grep -c '^ *git push')"
  if [ "$_eci_step5_total_push_count" = "2" ]; then
    ok "epic-create-issues: 手順5全体(両分岐)のpushはちょうど2回(各分岐1回ずつ)"
  else
    ng "epic-create-issues: 手順5全体のpush回数が想定外(got: ${_eci_step5_total_push_count}回、期待2回)"
  fi
fi

echo "== gh-issue-resolve.sh: 動的コンテキストの対象issue解決はワークスペース直下でも取り違えない =="
# ワークスペース直下の新規セッションでは、動的コンテキストの `!` がセッションの作業ディレクトリ
# (ワークスペース側の git リポジトリ)で解決されるため、bare な issue 番号を渡すと本来のメンバー
# リポジトリではなくワークスペース側リポジトリの同番号 issue を静かに掴んでしまう(番号衝突時に
# silently-wrong)。解決ロジックを lib へ切り出し、SKILL 側は単純呼び出し1個に留める。
for _gir_skill in issue-implement epic-implement-subissue epic-review; do
  _gir_body="$(cat "$H/skills/${_gir_skill}/SKILL.md" 2>/dev/null)"
  out_has   "${_gir_skill}: 動的コンテキストは gh-issue-resolve.sh の単純呼び出し" 'yosage-dev-harness-gh-issue-resolve "$ARGUMENTS"' "$_gir_body"
  out_hasnt "${_gir_skill}: gh issue view \$ARGUMENTS の直呼びが残っていない"       '`gh issue view $ARGUMENTS`'                    "$_gir_body"
  out_has   "${_gir_skill}: argument-hint が <owner>/<repo>#<N> 形式も案内"        '<owner>/<repo>#'                               "$_gir_body"
done

# Closes # テンプレート回帰(一次レビュー指摘): argument-hint に <owner>/<repo>#<N> 形式を追加した
# issue-implement / epic-implement-subissue のコミット/PR本文テンプレートで `Closes #$ARGUMENTS` の
# ままだと、$ARGUMENTS が owner/repo のとき `Closes #owner/repo` と壊れ GitHub の自動クローズが
# 効かない。bare な issue 番号のみを使うようテンプレートを直した(epic-review は Closes #$ARGUMENTS を
# 書かないため対象外)。
for _gir_closes_skill in issue-implement epic-implement-subissue; do
  _gir_closes_body="$(cat "$H/skills/${_gir_closes_skill}/SKILL.md" 2>/dev/null)"
  out_hasnt "${_gir_closes_skill}: Closes テンプレートに \$ARGUMENTS を直書きしていない(owner/repo#N形式で壊れるため)" 'Closes #$ARGUMENTS' "$_gir_closes_body"
done

file_is "lib: gh-issue-resolve.sh が存在" "$H/lib/gh-issue-resolve.sh"

# gh を実際に叩かず、組み立てられるコマンド引数だけを検証する(モック gh を PATH に差す)。
_girbin="$(mktemp -d)"
cat > "$_girbin/gh" <<'GIRGH'
#!/usr/bin/env bash
echo "gh $*"
GIRGH
chmod +x "$_girbin/gh"

_gir_scoped_out="$(cd "$ROOT" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "acme/target${HSH}42" 2>&1)"
out_has "gh-issue-resolve: <owner>/<repo>#<N> は --repo <owner>/<repo> <N> に解決" "gh issue view --repo acme/target 42" "$_gir_scoped_out"

# # の直前に空白1個をはさむ打ち間違い(owner/repo #N)も scoped 経路で解決する。
# 空白入りタイプミスが bare 番号抽出へフォールバックし、現在リポジトリの番号を静かに
# 誤って解決する事故(silently-wrong)を防ぐ回帰確認。
_gir_scoped_space_out="$(cd "$ROOT" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "acme/target ${HSH}42" 2>&1)"
out_has   "gh-issue-resolve: <owner>/<repo> #<N>(#直前に空白1個)も --repo <owner>/<repo> <N> に解決" "gh issue view --repo acme/target 42" "$_gir_scoped_space_out"

# #直前ではなく # の直後に空白が入る典型的なタイプミス(owner/repo# 42)。旧コードは scoped 抽出
# (# の直後に数字が隣接する厳密一致のみ)に失敗して bare 番号抽出へフォールバックし、現在リポジトリの
# 42 を静かに解決していた(`gh issue view 42`)。新コードは "/" と "#" が同一トークンに同居する時点で
# scoped 候補とみなし、厳密形式検証に失敗させて bare へは黙って落とさず非ゼロ終了+停止メッセージで
# 止める。上の "#直前に空白" ケースだけだと旧コードでも赤にならない(旧コードの catch-all は
# `gh issue view acme/target ` を出すだけで元々 `gh issue view 42` を含まず、
# out_hasnt が常に緑になる vacuous な確認だった)ため、この変種を別途固定する。
_gir_scoped_spaceafter_out="$(cd "$ROOT" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "acme/target${HSH} 42" 2>&1)"; _gir_scoped_spaceafter_rc=$?
if [ "$_gir_scoped_spaceafter_rc" -ne 0 ]; then ok "gh-issue-resolve: <owner>/<repo># <N>(#直後に空白)は非ゼロ終了(停止)"; else ng "gh-issue-resolve: <owner>/<repo># <N>(#直後に空白)は非ゼロ終了(停止)"; fi
out_hasnt "gh-issue-resolve: <owner>/<repo># <N>(#直後に空白)は現在リポジトリの bare 番号(42)へ静かに誤解決しない" "gh issue view 42" "$_gir_scoped_spaceafter_out"

# scoped に見えるが壊れている入力(# の後が数字以外・owner/repo部が空)は、
# bare 番号抽出へ黙って落ちず非ゼロ終了+停止メッセージで落ちる。
_gir_broken_nondigit_out="$(cd "$ROOT" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "acme/target${HSH}abc" 2>&1)"; _gir_broken_nondigit_rc=$?
if [ "$_gir_broken_nondigit_rc" -ne 0 ]; then ok "gh-issue-resolve: # の後が数字以外の壊れた scoped 形式は非ゼロ終了(停止)"; else ng "gh-issue-resolve: # の後が数字以外の壊れた scoped 形式は非ゼロ終了(停止)"; fi
out_hasnt "gh-issue-resolve: # の後が数字以外の壊れた scoped 形式は bare 番号解決へ黙って落ちない(ghを呼ばない)" "gh issue view" "$_gir_broken_nondigit_out"

_gir_broken_space_out="$(cd "$ROOT" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "acme/target ${HSH}abc" 2>&1)"; _gir_broken_space_rc=$?
if [ "$_gir_broken_space_rc" -ne 0 ]; then ok "gh-issue-resolve: 空白入り+# の後が数字以外の壊れた scoped 形式も非ゼロ終了(停止)"; else ng "gh-issue-resolve: 空白入り+# の後が数字以外の壊れた scoped 形式も非ゼロ終了(停止)"; fi
out_hasnt "gh-issue-resolve: 空白入り+壊れた scoped 形式も bare 番号解決へ黙って落ちない(ghを呼ばない)" "gh issue view" "$_gir_broken_space_out"

_gir_broken_emptyrepo_out="$(cd "$ROOT" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "acme/${HSH}42" 2>&1)"; _gir_broken_emptyrepo_rc=$?
if [ "$_gir_broken_emptyrepo_rc" -ne 0 ]; then ok "gh-issue-resolve: owner/repo部が壊れた(repo部が空)scoped形式は非ゼロ終了(停止)"; else ng "gh-issue-resolve: owner/repo部が壊れた(repo部が空)scoped形式は非ゼロ終了(停止)"; fi
out_hasnt "gh-issue-resolve: owner/repo部が壊れたscoped形式は bare 番号解決へ黙って落ちない(ghを呼ばない)" "gh issue view" "$_gir_broken_emptyrepo_out"

# gir_find_scoped_candidate の word splitting(`set -- $args`)は unquoted のためパス名展開
# (グロブ)も一緒に起動しうる。cwd に glob マッチするファイルがあると、そのファイル名が
# トークン列に混ざり込み、無関係な "/"+"#" 隣接を誤検出して cwd 依存で --repo が化ける
# (一次レビュー指摘: `fix src/*.sh please` は cwd に src/a.sh, src/b.sh があると
# 修正前は "src/b.sh" が --repo に混入していた)。noglob を一時的に立てて展開を止めたので、
# 引数中の glob パターンは cwd のファイル一覧に関わらず常に文字どおり扱われることを固定する。
_gir_glob_ws="$(mktemp -d)"; mkdir -p "$_gir_glob_ws/src"
touch "$_gir_glob_ws/src/a.sh" "$_gir_glob_ws/src/b.sh"
_gir_glob_out="$(cd "$_gir_glob_ws" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "fix src/*.sh ${HSH}10 please" 2>&1)"
out_has   "gh-issue-resolve: 引数中の glob パターンは cwd のファイルへ展開されず文字どおり scoped 候補として扱われる" "gh issue view --repo src/*.sh 10" "$_gir_glob_out"
out_hasnt "gh-issue-resolve: 引数中の glob パターンが cwd のファイル名(src/b.sh)へ静かに化けない" "gh issue view --repo src/b.sh" "$_gir_glob_out"
out_hasnt "gh-issue-resolve: 引数中の glob パターンが cwd のファイル名(src/a.sh)へ静かに化けない" "gh issue view --repo src/a.sh" "$_gir_glob_out"
rm -rf "$_gir_glob_ws"

_gir_ws="$(mktemp -d)"; mkdir -p "$_gir_ws/.claude"
( cd "$_gir_ws" && git init -q )
_gir_bare_noworkspace_out="$(cd "$_gir_ws" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "42" 2>&1)"
out_has "gh-issue-resolve: 設定無しで bare <N> は従来どおり gh issue view <N> に解決" "gh issue view 42" "$_gir_bare_noworkspace_out"

printf '{ "workspace": true }\n' > "$_gir_ws/.claude/yosage-dev-harness.local.json"
_gir_bare_workspace_out="$(cd "$_gir_ws" && PATH="$_girbin:$PATH" bash "$H/lib/gh-issue-resolve.sh" "42" 2>&1)"; _gir_bare_workspace_rc=$?
if [ "$_gir_bare_workspace_rc" -ne 0 ]; then ok "gh-issue-resolve: workspace:true 検出時は bare <N> で非ゼロ終了(停止)"; else ng "gh-issue-resolve: workspace:true 検出時は bare <N> で非ゼロ終了(停止)"; fi
out_has   "gh-issue-resolve: workspace:true 検出時は <owner>/<repo>#<N> 形式での指定を要求するメッセージを出す" '<owner>/<repo>#' "$_gir_bare_workspace_out"
out_hasnt "gh-issue-resolve: workspace:true 検出時は gh を呼ばない(誤ったリポジトリの issue を掴まない)" "gh issue view" "$_gir_bare_workspace_out"
rm -rf "$_gir_ws" "$_girbin"

echo "== epic-cleanup.sh: epic-implement step9 クリーンアップロジックの回帰テスト =="
# step9 は破壊的操作(git worktree remove / git branch -d)を伴うため、ロジックは lib スクリプトへ
# 切り出し済み(SKILL.md 手順との二重管理を避ける)。まず SKILL.md がその lib 呼び出しを使っていて、
# 生ロジックを直書きしていないことを確認する。
file_is "lib: epic-cleanup.sh が存在" "$H/lib/epic-cleanup.sh"
_ec_body="$(cat "$H/skills/epic-implement/SKILL.md" 2>/dev/null)"
out_has   "epic-implement: step9 は lib スクリプト呼び出しを使う(二重管理防止)" 'yosage-dev-harness-epic-cleanup "epic/<epic-name>"' "$_ec_body"
out_hasnt "epic-implement: step9 に worktree 走査ロジックが直書きされていない" 'git worktree list --porcelain' "$_ec_body"
out_hasnt "epic-implement: step9 に branch 削除ループが直書きされていない"     'git branch -d "$b"'              "$_ec_body"

# 保護すべきブランチ集合の単一ホーム化。除外リストを epic-cleanup.sh の中だけに
# ハードコードしていたため `master` の欠落が起きた(base ブランチ・main・epic ブランチしか
# 除外していなかった)。単一ホーム(lib/branch-protection.sh)を source する形に切り出し、
# epic-cleanup.sh 側は直書きの除外パターンを持たないことを見る。
file_is "lib: branch-protection.sh が存在" "$H/lib/branch-protection.sh"
# ファイル全文の部分文字列一致だと、冒頭の説明コメント(「master を挙げていなかった」等)に含まれる
# main/master の文字列にも誤ってヒットしうる(配列から要素を抜いても green のまま通る空振り)。
# BP_ALWAYS_PROTECTED を実際に source して評価した値そのものを検証する。
_bp_array_vals="$(bash -c 'source "$1"; printf "%s\n" "${BP_ALWAYS_PROTECTED[@]}"' _ "$H/lib/branch-protection.sh" 2>/dev/null)"
if printf '%s\n' "$_bp_array_vals" | grep -qFx "main"; then ok "branch-protection.sh: BP_ALWAYS_PROTECTED 配列(実評価)に main を含む"; else ng "branch-protection.sh: BP_ALWAYS_PROTECTED 配列(実評価)に main を含む"; fi
if printf '%s\n' "$_bp_array_vals" | grep -qFx "master"; then ok "branch-protection.sh: BP_ALWAYS_PROTECTED 配列(実評価)に master を含む"; else ng "branch-protection.sh: BP_ALWAYS_PROTECTED 配列(実評価)に master を含む"; fi

_ec_lib_body="$(cat "$H/lib/epic-cleanup.sh" 2>/dev/null)"
out_has   "epic-cleanup.sh: branch-protection.sh を単一ホームとして source する(除外リストの二重管理防止)" "branch-protection.sh" "$_ec_lib_body"
out_hasnt "epic-cleanup.sh: 保護ブランチの除外パターンを直書きしていない(単一ホームの関数を参照)" '-e "$base_branch" -e main -e "$epic_branch"' "$_ec_lib_body"

# 破壊的操作を伴うため、隔離した使い捨ての bare remote と clone の上でロジックそのものを検証する。
# 既定ブランチは main(develop は作らない)。マージ後にリモートの Sub-issue ブランチが自動で消える
# 導入先(リモートの Sub-issue ブランチを消す)と、ローカルの Epic ブランチが古いままの状態を再現する。
# _ec_mk <dir> [epic-state]: <dir>/remote.git と <dir>/work を作る。work は main に居て、ローカルに次がある。
#   epic/demo(古いまま=Epic の分岐点)・epic-sub-merged(リモートの epic/demo へマージ済み・リモートでは削除済み)・
#   epic-sub-unmerged・epic-legacy-dir-merged・master(いずれも epic/demo へマージ済み)・unrelated/local-only。
#   作業ツリー: wt-sub-merged・wt-epic(epic/demo)・wt-unrelated・wt-detached(置き場の中)、
#   wt-legacy-merged(置き場に似た別ディレクトリ)。
#   epic-state: progress(既定。Epic は既定ブランチへ未マージ) / done(Epic を --no-ff で main へマージ済み)
_ec_mk() {
  local d="$1" state="${2:-progress}" w
  mk_bare_remote_clone "$d" --default main || return 1
  w="$d/work"
  gitc -C "$w" checkout -q -b unrelated/local-only \
    && echo x > "$w/f.txt" && gitc -C "$w" add -A && gitc -C "$w" commit -qm unrelated-change \
    && gitc -C "$w" checkout -q main \
    && gitc -C "$w" merge -q --no-ff unrelated/local-only -m merge-unrelated \
    && git -C "$w" push -q origin main \
    && gitc -C "$w" checkout -q -b epic/demo \
    && git -C "$w" push -q origin epic/demo || return 1
  local old; old="$(git -C "$w" rev-parse epic/demo)"
  local br
  for br in epic-sub-merged epic-legacy-dir-merged master; do
    gitc -C "$w" checkout -q -b "$br" epic/demo \
      && echo "$br" >> "$w/f.txt" && gitc -C "$w" add -A && gitc -C "$w" commit -qm "change-$br" \
      && gitc -C "$w" checkout -q epic/demo \
      && gitc -C "$w" merge -q --no-ff "$br" -m "merge-$br" || return 1
  done
  gitc -C "$w" checkout -q -b epic-sub-unmerged epic/demo \
    && echo z >> "$w/f.txt" && gitc -C "$w" add -A && gitc -C "$w" commit -qm change-unmerged \
    && git -C "$w" push -q origin epic/demo \
    && gitc -C "$w" checkout -q main || return 1
  if [ "$state" = done ]; then
    gitc -C "$w" merge -q --no-ff epic/demo -m "Merge epic/demo" && git -C "$w" push -q origin main || return 1
  fi
  # ローカルの Epic ブランチを古いまま(分岐点)に戻す(リモートだけが進んでいる状態)。
  git -C "$w" branch -f epic/demo "$old" || return 1
  mkdir -p "$w/.claude/worktrees" "$w/.claude/worktrees-legacy" \
    && git -C "$w" worktree add -q "$w/.claude/worktrees/wt-sub-merged" epic-sub-merged \
    && git -C "$w" worktree add -q "$w/.claude/worktrees/wt-epic" epic/demo \
    && git -C "$w" worktree add -q "$w/.claude/worktrees/wt-unrelated" unrelated/local-only \
    && git -C "$w" worktree add -q --detach "$w/.claude/worktrees/wt-detached" main \
    && git -C "$w" worktree add -q "$w/.claude/worktrees-legacy/wt-legacy-merged" epic-legacy-dir-merged || return 1
  # マージ後にリモートの Sub-issue ブランチは自動で消える(epic-sub-merged はそもそも push していない)。
  return 0
}
_ec_run() { ( cd "$1/work" && bash "$H/lib/epic-cleanup.sh" "${@:2}" 2>&1 ); }
_ec_br()  { git -C "$1/work" branch --format='%(refname:short)'; }
_ec_wt()  { git -C "$1/work" worktree list; }

# --- 途中: リモートの Epic ブランチを基準に、マージ済みの Sub-issue だけを消し、Epic ブランチと作業ツリーは残す ---
ecd="$(mktemp -d)"
_ec_mk "$ecd" progress
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
_ec_branches_after="$(_ec_br "$ecd")"
_ec_worktrees_after="$(_ec_wt "$ecd")"
exit_is "epic-cleanup(途中): 終了コード0" 0 "$_ec_rc"
out_has   "epic-cleanup(途中): 基準の出力(リモートの Epic ブランチ・途中・base・除外の基準)" "基準: origin/epic/demo@" "$_ec_out"
out_has   "epic-cleanup(途中): 途中と出す" "（途中）、base: main（指定）、除外の基準: origin/main" "$_ec_out"
out_has   "epic-cleanup(途中): (b) リモートの Epic ブランチへマージ済みの sub-issue ブランチは、ローカルの Epic ブランチが古くても -d で掃除される" "deleted: epic-sub-merged" "$_ec_out"
out_hasnt "epic-cleanup(途中): (b) 掃除後は epic-sub-merged ブランチが残らない" "epic-sub-merged" "$_ec_branches_after"
out_hasnt "epic-cleanup(途中): (b) 掃除後は wt-sub-merged worktree が残らない" "wt-sub-merged" "$_ec_worktrees_after"
out_has   "epic-cleanup(途中): Epic ブランチ(ローカル)は消さない" "epic/demo" "$_ec_branches_after"
out_hasnt "epic-cleanup(途中): Epic ブランチは deleted 行にも skip 行にも出ない" "epic/demo" "$(printf '%s\n' "$_ec_out" | grep -E '^(deleted|skip)' || true)"
out_has   "epic-cleanup(途中): Epic ブランチをチェックアウトしている作業ツリーは消さない" "wt-epic" "$_ec_worktrees_after"
out_has   "epic-cleanup: (c) 未マージの sub-issue ブランチは巻き込まれず残る" "epic-sub-unmerged" "$_ec_branches_after"
out_has   "epic-cleanup: (a) main へ既に merge 済みの無関係なローカル専用ブランチは巻き込まれず残る" "unrelated/local-only" "$_ec_branches_after"
out_has   "epic-cleanup: (a) 無関係な現役worktreeは触らず残る" "wt-unrelated" "$_ec_worktrees_after"
out_has   "epic-cleanup: detached-HEAD worktree はエラーにならず残る(空ブランチ名ガード)" "wt-detached" "$_ec_worktrees_after"
# 境界回帰: worktrees_root がプレフィックスとして重なるだけの別ディレクトリ
# (".claude/worktrees-legacy/...") は対象の置き場外なので、そこにある merge 済みブランチの
# worktree を巻き込んではいけない(部分文字列一致だと ".claude/worktrees" が
# ".claude/worktrees-legacy/..." にもマッチしてしまう境界バグの回帰)。
out_has "epic-cleanup: 境界回帰 - プレフィックス重複ディレクトリ(worktrees-legacy)のworktreeは巻き込まれず残る" "wt-legacy-merged" "$_ec_worktrees_after"
out_has "epic-cleanup: 境界回帰 - プレフィックス重複ディレクトリの merge 済みブランチも(worktree使用中のため)削除されず残る" "epic-legacy-dir-merged" "$_ec_branches_after"
# 回帰: 除外リストが base ブランチ・main・epic ブランチしか挙げておらず、`master` という名前のブランチは
# 削除候補に入り、掃除で消えてしまっていた。単一ホーム化した保護ブランチ集合には master も含まれる。
out_hasnt "epic-cleanup: master は削除候補に入らない(deleted: master が出力に出ない)" "deleted: master" "$_ec_out"
out_hasnt "epic-cleanup: master は削除候補に入らない(skip 行としても出力に出ない)" "master" "$(printf '%s\n' "$_ec_out" | grep '^skip' || true)"
out_has "epic-cleanup: master は保護され掃除後もブランチ一覧に残る" "master" "$_ec_branches_after"
# 2回目の実行: 壊れず、消したものを再び消そうとしない(置き場の外の worktree に使われている
# epic-legacy-dir-merged は skip 行として残る)。
_ec_out2="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc2=$?
exit_is "epic-cleanup(途中): 2回目の実行も終了コード0" 0 "$_ec_rc2"
out_hasnt "epic-cleanup(途中): 2回目は何も消さない" "deleted:" "$_ec_out2"
out_hasnt "epic-cleanup(途中): 2回目は消した epic-sub-merged を再び対象にしない" "epic-sub-merged" "$_ec_out2"
# base を省略したときも、origin/HEAD から解決して同じ基準で動く
_ec_out3="$(_ec_run "$ecd" epic/demo "" .claude/worktrees)"
out_has "epic-cleanup(base 省略): 出どころを出力に含める" "base: main（origin/HEAD）" "$_ec_out3"
rm -rf "$ecd"

# --- 完了: Epic ブランチが既定ブランチへマージコミットで入った後は、ローカルの Epic ブランチも消す ---
ecd="$(mktemp -d)"
_ec_mk "$ecd" done
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
_ec_branches_after="$(_ec_br "$ecd")"
_ec_worktrees_after="$(_ec_wt "$ecd")"
exit_is "epic-cleanup(完了): 終了コード0" 0 "$_ec_rc"
out_has   "epic-cleanup(完了): 完了と出し、除外の基準は取り込む前の親(origin/main ではない)" "（完了）、base: main（指定）、除外の基準: " "$_ec_out"
out_hasnt "epic-cleanup(完了): 除外の基準が origin/main ではない(全件が除外されて0件になるのを避ける)" "除外の基準: origin/main" "$_ec_out"
out_has   "epic-cleanup(完了): sub-issue ブランチを消す" "deleted: epic-sub-merged" "$_ec_out"
out_has   "epic-cleanup(完了): ローカルの Epic ブランチも消す" "deleted: epic/demo" "$_ec_out"
out_hasnt "epic-cleanup(完了): ローカルの Epic ブランチが残らない" "epic/demo" "$_ec_branches_after"
out_hasnt "epic-cleanup(完了): Epic ブランチをチェックアウトしていた作業ツリーも消す" "wt-epic" "$_ec_worktrees_after"
out_has   "epic-cleanup(完了): リモートの Epic ブランチが残っていれば報告する(消さない)" "remote に Epic ブランチが残っている: origin/epic/demo" "$_ec_out"
out_has   "epic-cleanup(完了): リモートの Epic ブランチは消していない" "epic/demo" "$(git -C "$ecd/remote.git" branch --format='%(refname:short)')"
out_has   "epic-cleanup(完了): 未マージの sub-issue ブランチは残る" "epic-sub-unmerged" "$_ec_branches_after"
out_has   "epic-cleanup(完了): 無関係なローカル専用ブランチ・master は残る" "unrelated/local-only" "$_ec_branches_after"
out_has   "epic-cleanup(完了): 無関係な現役 worktree は残る" "wt-unrelated" "$_ec_worktrees_after"
_ec_out2="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc2=$?
exit_is "epic-cleanup(完了): 2回目の実行も終了コード0" 0 "$_ec_rc2"
out_hasnt "epic-cleanup(完了): 2回目は何も消さない" "deleted:" "$_ec_out2"
out_has "epic-cleanup(完了): 2回目も完了と判定する(リモートの Epic ブランチが基準)" "（完了）" "$_ec_out2"
rm -rf "$ecd"

# 完了して、リモートの Epic ブランチも消えている(origin/<epic> が無い): ローカルの Epic ブランチを基準にする
ecd="$(mktemp -d)"
_ec_mk "$ecd" done
git -C "$ecd/work" worktree remove "$ecd/work/.claude/worktrees/wt-epic" >/dev/null 2>&1
git -C "$ecd/work" branch -f epic/demo origin/epic/demo >/dev/null 2>&1   # ローカルを最新にしてから
git -C "$ecd/work" push -q origin --delete epic/demo >/dev/null 2>&1
git -C "$ecd/work" update-ref -d refs/remotes/origin/epic/demo
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(完了・リモートの Epic ブランチ無し): 終了コード0" 0 "$_ec_rc"
out_has "epic-cleanup(完了・リモートの Epic ブランチ無し): ローカルの Epic ブランチを基準にして完了と判定する" "基準: epic/demo@" "$_ec_out"
out_has "epic-cleanup(完了・リモートの Epic ブランチ無し): ローカルの Epic ブランチを消す" "deleted: epic/demo" "$_ec_out"
rm -rf "$ecd"

# ワークスペース形(計画をコミットせず、Epic ブランチが作成時点の既定ブランチと同じ位置)で、Epic を既定ブランチへ
# マージコミットで取り込み、リモートの Epic ブランチが消え、ローカルの Epic ブランチは古い(作成時点のまま)。
# ローカルの Epic ブランチは取り込み前の親の祖先になるだけなので、基準にすると完了を検出できない。
# 既定ブランチの履歴から Epic ブランチを取り込んだマージコミットを探し、その第2親を基準にする。
ecd="$(mktemp -d)"
mk_bare_remote_clone "$ecd" --default main
_w="$ecd/work"
gitc -C "$_w" checkout -q -b epic/demo
git -C "$_w" push -q origin epic/demo
gitc -C "$_w" checkout -q -b epic-sub-merged
echo s > "$_w/s.txt"; gitc -C "$_w" add -A; gitc -C "$_w" commit -qm change-sub-merged
gitc -C "$_w" checkout -q epic/demo
gitc -C "$_w" merge -q --no-ff epic-sub-merged -m merge-sub-merged
git -C "$_w" push -q origin epic/demo
gitc -C "$_w" checkout -q -b epic-sub-unmerged epic-sub-merged
echo u > "$_w/u.txt"; gitc -C "$_w" add -A; gitc -C "$_w" commit -qm change-sub-unmerged
gitc -C "$_w" checkout -q main
gitc -C "$_w" merge -q --no-ff epic/demo -m "Merge branch 'epic/demo'"
git -C "$_w" push -q origin main
git -C "$_w" branch -f epic/demo main^1 >/dev/null 2>&1   # ローカルの Epic ブランチは作成時点のまま(古い)
git -C "$_w" push -q origin --delete epic/demo >/dev/null 2>&1
git -C "$_w" update-ref -d refs/remotes/origin/epic/demo
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(完了・計画コミット無し・リモートの Epic ブランチ削除済み・ローカルは古い): 終了コード0" 0 "$_ec_rc"
out_has   "epic-cleanup(完了・計画コミット無し・リモートの Epic ブランチ削除済み・ローカルは古い): 取り込んだマージコミットから完了と判定する" "（完了）" "$_ec_out"
out_has   "epic-cleanup(完了・計画コミット無し・リモートの Epic ブランチ削除済み・ローカルは古い): sub-issue ブランチを消す" "deleted: epic-sub-merged" "$_ec_out"
out_has   "epic-cleanup(完了・計画コミット無し・リモートの Epic ブランチ削除済み・ローカルは古い): ローカルの Epic ブランチも消す" "deleted: epic/demo" "$_ec_out"
out_hasnt "epic-cleanup(完了・計画コミット無し・リモートの Epic ブランチ削除済み・ローカルは古い): ローカルの Epic ブランチが残らない" "epic/demo" "$(_ec_br "$ecd")"
out_has   "epic-cleanup(完了・計画コミット無し・リモートの Epic ブランチ削除済み・ローカルは古い): 取り込まれていない sub-issue ブランチは残る" "epic-sub-unmerged" "$(_ec_br "$ecd")"
rm -rf "$ecd"

# リモートでは消えたが追跡 ref(origin/<epic>)が残っている(--prune なしの fetch の後と同じ状態): fetch --prune で
# 追跡 ref が消え、ローカルの Epic ブランチが基準になる(古い追跡 ref を基準にしない)。
ecd="$(mktemp -d)"
_ec_mk "$ecd" done
git -C "$ecd/work" worktree remove "$ecd/work/.claude/worktrees/wt-epic" >/dev/null 2>&1
git -C "$ecd/work" branch -f epic/demo origin/epic/demo >/dev/null 2>&1
git -C "$ecd/remote.git" update-ref -d refs/heads/epic/demo   # remote 側だけで消す(work の追跡 ref は残る)
git -C "$ecd/work" show-ref --verify -q refs/remotes/origin/epic/demo || ng "前提: 追跡 ref が残っている"
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(追跡 ref だけ残る): 終了コード0" 0 "$_ec_rc"
out_has   "epic-cleanup(追跡 ref だけ残る): prune されてローカルの Epic ブランチが基準になる" "基準: epic/demo@" "$_ec_out"
out_hasnt "epic-cleanup(追跡 ref だけ残る): 古い追跡 ref を基準にしない" "基準: origin/epic/demo@" "$_ec_out"
git -C "$ecd/work" show-ref --verify -q refs/remotes/origin/epic/demo && ng "epic-cleanup(追跡 ref だけ残る): 追跡 ref が prune される" || ok "epic-cleanup(追跡 ref だけ残る): 追跡 ref が prune される"
rm -rf "$ecd"

# --- 作ったばかりの Epic ブランチ(既定ブランチと同じ位置)は完了と取り違えず、何も消さない ---
ecd="$(mktemp -d)"
mk_bare_remote_clone "$ecd" --default main --branch epic/demo
git -C "$ecd/work" fetch -q origin
gitc -C "$ecd/work" checkout -q -b epic/demo origin/epic/demo >/dev/null 2>&1
gitc -C "$ecd/work" checkout -q -b epic-sub-new >/dev/null 2>&1
gitc -C "$ecd/work" checkout -q main >/dev/null 2>&1
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(作ったばかり): 終了コード0" 0 "$_ec_rc"
out_has   "epic-cleanup(作ったばかり): 途中と判定する" "（途中）" "$_ec_out"
out_hasnt "epic-cleanup(作ったばかり): 完了と判定しない" "（完了）" "$_ec_out"
out_hasnt "epic-cleanup(作ったばかり): 何も消さない" "deleted:" "$_ec_out"
out_has   "epic-cleanup(作ったばかり): 対象0件と出す" "対象: 0件" "$_ec_out"
out_has   "epic-cleanup(作ったばかり): Epic ブランチが残る" "epic/demo" "$(_ec_br "$ecd")"
rm -rf "$ecd"

# --- fast-forward で入っていてマージコミットが無いときは、作ったばかりと区別できないので途中として扱う ---
ecd="$(mktemp -d)"
mk_bare_remote_clone "$ecd" --default main
gitc -C "$ecd/work" checkout -q -b epic/demo
echo e > "$ecd/work/e.txt"; gitc -C "$ecd/work" add -A; gitc -C "$ecd/work" commit -qm epic-change
git -C "$ecd/work" push -q origin epic/demo
gitc -C "$ecd/work" checkout -q main
gitc -C "$ecd/work" merge -q --ff-only epic/demo && git -C "$ecd/work" push -q origin main
gitc -C "$ecd/work" checkout -q -b epic-sub-ff epic/demo
gitc -C "$ecd/work" checkout -q main
# 入った直後は Epic ブランチが既定ブランチの先端と同じ位置で、作ったばかりと履歴から区別できない
# (途中として扱い、何も消さない。位置が同じで区別できない旨を出す)。
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(fast-forward 直後・同じ位置): 終了コード0" 0 "$_ec_rc"
out_has   "epic-cleanup(fast-forward 直後・同じ位置): 作ったばかりとの区別がつかない旨を出す" "fast-forward で入った場合と区別できない" "$_ec_out"
out_hasnt "epic-cleanup(fast-forward 直後・同じ位置): 何も消さない" "deleted:" "$_ec_out"
# 既定ブランチが先へ進み、Epic ブランチが既定ブランチの履歴の中(祖先)に入ってもマージコミットが無いときは、
# 同じく途中として扱い、何も消さず、注意を出す(Sub-issue がまだ入らないうちに既定ブランチが進んだ普通の途中でも止めない)。
echo n > "$ecd/work/n.txt"; gitc -C "$ecd/work" add -A; gitc -C "$ecd/work" commit -qm next-change; git -C "$ecd/work" push -q origin main
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(祖先・マージコミット無し): 終了コード0" 0 "$_ec_rc"
out_has   "epic-cleanup(祖先・マージコミット無し): 途中と判定する" "（途中）" "$_ec_out"
out_has   "epic-cleanup(祖先・マージコミット無し): 区別できない旨の注意を出す" "fast-forward で入った場合と区別できない" "$_ec_out"
out_hasnt "epic-cleanup(祖先・マージコミット無し): 何も消さない" "deleted:" "$_ec_out"
out_has   "epic-cleanup(祖先・マージコミット無し): ブランチが残る" "epic-sub-ff" "$(_ec_br "$ecd")"
rm -rf "$ecd"

# --- 失敗するべきときに失敗する ---
# fetch の失敗(remote の URL を壊す)
ecd="$(mktemp -d)"
_ec_mk "$ecd" progress
git -C "$ecd/work" remote set-url origin "$ecd/no-such-remote.git"
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(fetch 失敗): 専用の終了コード10で止まる" 10 "$_ec_rc"
out_hasnt "epic-cleanup(fetch 失敗): 何も消さない" "deleted:" "$_ec_out"
out_has   "epic-cleanup(fetch 失敗): sub-issue ブランチが残る" "epic-sub-merged" "$(_ec_br "$ecd")"
out_has   "epic-cleanup(fetch 失敗): 作業ツリーが残る" "wt-sub-merged" "$(_ec_wt "$ecd")"
rm -rf "$ecd"
# 基準の ref が無い: origin/HEAD が実在しないブランチを指す(base を省略したとき)
ecd="$(mktemp -d)"
_ec_mk "$ecd" progress
git -C "$ecd/work" config remote.origin.followRemoteHEAD never   # fetch が origin/HEAD を直さないようにする
git -C "$ecd/work" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
_ec_out="$(_ec_run "$ecd" epic/demo)"; _ec_rc=$?
exit_is "epic-cleanup(origin/HEAD が実在しないブランチを指す): 専用の終了コード11で止まる" 11 "$_ec_rc"
out_hasnt "epic-cleanup(origin/HEAD が実在しないブランチを指す): 何も消さない" "deleted:" "$_ec_out"
out_has   "epic-cleanup(origin/HEAD が実在しないブランチを指す): 基準の ref が無いと報告する" "origin/gone が実在しない" "$_ec_out"
# 指定した base が origin に無い
_ec_out="$(_ec_run "$ecd" epic/demo nosuchbase .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(指定した base が origin に無い): 終了コード11" 11 "$_ec_rc"
out_hasnt "epic-cleanup(指定した base が origin に無い): 何も消さない" "deleted:" "$_ec_out"
rm -rf "$ecd"
# リモートの Epic ブランチが無く、ローカルの Epic ブランチも既定ブランチに取り込まれていない
ecd="$(mktemp -d)"
_ec_mk "$ecd" progress
git -C "$ecd/work" push -q origin --delete epic/demo >/dev/null 2>&1
git -C "$ecd/work" update-ref -d refs/remotes/origin/epic/demo
echo l > "$ecd/work/.claude/worktrees/wt-epic/l.txt"
gitc -C "$ecd/work/.claude/worktrees/wt-epic" add -A; gitc -C "$ecd/work/.claude/worktrees/wt-epic" commit -qm local-only-epic-change
_ec_out="$(_ec_run "$ecd" epic/demo main .claude/worktrees)"; _ec_rc=$?
exit_is "epic-cleanup(基準の Epic ブランチが無い): 終了コード11で止まる" 11 "$_ec_rc"
out_hasnt "epic-cleanup(基準の Epic ブランチが無い): 何も消さない" "deleted:" "$_ec_out"
rm -rf "$ecd"


echo "== Sub-issue の取り込み先の既定を Epic ブランチにする規則(epic-create-docs / epic-create-issues / epic-implement / epic-review) =="
_ecd_t="$(cat "$H/skills/epic-create-docs/SKILL.md" 2>/dev/null)"
out_has "epic-create-docs: 00_overview の Sub-issue 表に「取り込み先」の列がある" "| Sub-issue | 内容 | 依存 | 取り込み先 |" "$_ecd_t"
out_has "epic-create-docs: 各 Sub-issue の文書に ## 取り込み先 の節がある" "## 取り込み先" "$_ecd_t"
out_has "epic-create-docs: 取り込み先の既定は Epic ブランチ" "既定は Epic ブランチ" "$_ecd_t"
out_has "epic-create-docs: 既定ブランチへ直接入れる例外は次の両方を満たすときだけ(独立に取り込める＋先に出す事情)" "既定ブランチへ直接入れる例外**は、次の**両方**を満たすときだけ" "$_ecd_t"
out_has "epic-create-docs: 例外の条件に「先に出したい・Epic の外で先に必要とされている」事情を挙げる" "先に出したい・Epic の外で先に必要とされている" "$_ecd_t"
out_has "epic-create-docs: 取り込み先を実装の途中で変えるときは提案して記録してから従う旨を明記" "ハーネスが変更を提案し、理由とともに Sub-issue に記録してから従う。黙って変えない" "$_ecd_t"
out_has "epic-create-docs: Epic ブランチを作る条件(1つでもあれば作る)を明記" "1つでもあれば作る" "$_ecd_t"
out_has "epic-create-docs: ワークスペースで全件が既定ブランチ向けなら作らない旨を明記" "全 Sub-issue が既定ブランチ向けなら**作らない**" "$_ecd_t"
out_has "epic-create-docs: 単一リポジトリは全件が既定ブランチ向けでも作る旨を明記" "全 Sub-issue が既定ブランチ向けでも**作る**" "$_ecd_t"
_eci_t="$(cat "$H/skills/epic-create-issues/SKILL.md" 2>/dev/null)"
out_has "epic-create-issues: Sub-issue 本文の雛形に ## 取り込み先 がある" "## 取り込み先" "$_eci_t"
out_has "epic-create-issues: Epic ブランチは解決したベースから作る(実行ファイル経由)" 'yosage-dev-harness-base-branch --declared' "$_eci_t"
out_has "epic-create-issues: 単一リポジトリは起票のときに draft の Epic PR を作る" 'gh pr create --draft' "$_eci_t"
out_has "epic-create-issues: Epic の PR の base は解決したベース" '--base "$base"' "$_eci_t"
out_has "epic-create-issues: ワークスペースでは起票のとき Epic の PR を作らない理由(差分の無い PR は作れない)を明記" "差分の無い PR を" "$_eci_t"
out_has "epic-create-issues: ワークスペースは最初の取り込みで epic-implement が draft の Epic PR を作る旨を明記" "最初の Sub-issue を Epic ブランチへ" "$_eci_t"
out_has "epic-create-issues: 次の一手の案内に draft の PR の URL(単一)と最初の取り込みで作る旨(ワークスペース)を含める" "draft の PR の URL" "$_eci_t"
out_has "epic-create-issues: ワークスペースで全件が既定ブランチ向けなら Epic ブランチを作らない旨を明記" "全件の取り込み先が既定ブランチなら**作らない**" "$_eci_t"
_ei_t="$(cat "$H/skills/epic-implement/SKILL.md" 2>/dev/null)"
out_has "epic-implement: 手順1が Sub-issue ごとの取り込み先を本文から読む" "Sub-issue ごとの取り込み先" "$_ei_t"
out_has "epic-implement: フェーズ指定の実行の冒頭で取り込み済みなのに開いたままの Sub-issue を閉じる" "フェーズ（\`phaseN\`）または Sub-issue リストを明示指定して実行したときは、この時点（冒頭）で" "$_ei_t"
out_has "epic-implement: 冒頭の確認は既定ブランチ向けを origin/\$base で確かめる" 'origin/$base' "$_ei_t"
out_has "epic-implement: Epic ブランチの起点は解決したベース" 'git checkout -b epic/<epic-name> "origin/$base"' "$_ei_t"
out_has "epic-implement: ベースを実行ファイルで解決する" 'yosage-dev-harness-base-branch --declared' "$_ei_t"
out_has "epic-implement: 取り込み先が既定ブランチの Sub-issue は origin/\$base から作り --base \$base" '`origin/$base` から作り、PR は `--base "$base"`' "$_ei_t"
out_has "epic-implement: Epic ブランチ向けの PR 本文は Part of を書く" "「Part of #<epic_number>」" "$_ei_t"
out_has "epic-implement: 取り込み先を途中で変えるときの手順(提案→Sub-issue に記録→従う)" "Sub-issue にコメントで記録してから" "$_ei_t"
out_has "epic-implement: 既定ブランチ → Epic ブランチの同期は PR を人がマージする形" '--base epic/<epic-name> \' "$_ei_t"
out_has "epic-implement: 同期は直接 push しない" "直接 push しない" "$_ei_t"
out_has "epic-implement: 同期の PR は head が \$base" '--head "$base"' "$_ei_t"
out_has "epic-implement: 最初の取り込みの時点で draft の Epic PR が無ければ作る" "Epic の PR（draft）が無ければ作る" "$_ei_t"
out_has "epic-implement: 手順7は確かめた Sub-issue を PR リンク付きで明示的に閉じる" 'gh issue close <n> [--repo <owner>/<repo>] --comment' "$_ei_t"
out_has "epic-implement: 手順7は既定ブランチへ直接入れたものを origin/\$base の履歴で確かめる" 'git log "origin/$base" --format' "$_ei_t"
out_has "epic-implement: 手順7は Epic の PR を新しく作らず draft を ready にする" "Epic の PR を新しく作らない" "$_ei_t"
out_has "epic-implement: 手順7は draft の Epic PR が無ければ解決したベースへ向けて作る" "draft の Epic PR が見つからなければ" "$_ei_t"
out_hasnt "epic-implement: 手順7が Epic PR を develop 向けに新規作成する旧手順が残っていない" "Epic ブランチ → develop の **draft PR** を作成" "$_ei_t"
# 取り込み先の記載が無い Sub-issue は推測で決めず、計画の提示で一覧を示して人に確かめる
out_has "epic-implement: 取り込み先の記載が無い Sub-issue は推測で決めない" "推測で決めない" "$_ei_t"
out_has "epic-implement: 記載が無い Sub-issue の一覧を着火前の計画提示で示す" "取り込み先の記載が無い Sub-issue の一覧（あれば）" "$_ei_t"
out_hasnt "epic-implement: 取り込み先の記載が無い Sub-issue を Epic ブランチ向けとして扱う旧文言が残っていない" "Epic ブランチ向けとして扱い" "$_ei_t"
# 状態2の確認は手順9の後に1回(手順10)。リモートの ref が無くても判定できる
out_has "epic-implement: 手順10が状態2を掃除の後に1回だけ確かめる" "### 10. 状態2の最終確認 → Epic issue のクローズ" "$_ei_t"
out_has "epic-implement: リモートの Epic ブランチが prune 済みでもマージコミットで判定する" 'git log --first-parent --merges -E "origin/$base" --grep="epic/<epic-name>(\$|[^[:alnum:]_/.-])"' "$_ei_t"
out_has "epic-implement: 手順8は状態2を手順10で確かめる旨を明記(往復しない)" "手順9の後の手順10で1回だけ確かめる" "$_ei_t"
# 閉じるときにリンクする PR は、その Sub-issue 自身の PR(同期の PR・依存する側の PR を選ばない)
out_has "epic-implement: リンクする PR はその Sub-issue 自身の PR を選ぶ" "その Sub-issue 自身の PR" "$_ei_t"
out_has "epic-implement: 同期の PR・Epic の PR を除くクエリ(head が \$base・Epic ブランチを除外)" 'select(.headRefName != $base and .headRefName != $epic)' "$_ei_t"
out_hasnt "epic-implement: PR の選び方が本文の参照だけの最初の1件という旧い形に戻っていない" "select(.body | test(\"#<n>([^0-9]|\$)\"))" "$_ei_t"
out_has "epic-implement: Sub-issue 自身の PR が引けなければリンク無しでは閉じない" "リンク無しでは閉じない" "$_ei_t"
out_has "epic-implement:手順8は Epic の PR がマージ済みかを確かめ draft のままなら止めて案内する" "draft のまま残っていれば止めて案内する" "$_ei_t"
out_has "epic-implement: 手順8の完了時に必ず満たす状態1(計画ドキュメントが合流)" "計画ドキュメントが合流している" "$_ei_t"
out_has "epic-implement: 手順8の完了時に必ず満たす状態2(Epic ブランチが閉じている)" "Epic ブランチが閉じている" "$_ei_t"
out_has "epic-implement: 手順8の完了時に必ず満たす状態3(Sub-issue がすべて閉じている)" "Sub-issue がすべて閉じている" "$_ei_t"
out_has "epic-implement: 手順9は解決したベースを明示して epic-cleanup へ渡す" 'yosage-dev-harness-epic-cleanup "epic/<epic-name>" "$base"' "$_ei_t"
_er_t="$(cat "$H/skills/epic-review/SKILL.md" 2>/dev/null)"
out_has "epic-review: PR は Epic の Sub-issue の一覧から引く(base での絞り込みだけに頼らない)" "Epic の Sub-issue の一覧" "$_er_t"
out_has "epic-review: base 絞り込みだけでは積んだ PR を取りこぼす旨を明記" "取りこぼす" "$_er_t"
out_has "epic-review: PR から Sub-issue を「Part of」と Sub-issue への参照で特定する" "「Part of #<Epic>」と Sub-issue への参照" "$_er_t"
out_hasnt "epic-review: PR の集め方が base 絞り込みの gh pr list だけに戻っていない" 'gh pr list --base epic/<epic-name> --state open
```' "$_er_t"

# $base を使うコードブロックは、そのブロックの冒頭で yosage-dev-harness-base-branch を if base="$(…)" の形で解決し直している
# (別の Bash 呼び出しには残らない)。`|| exit 1` でシェルを閉じない。コメントの文言ではなくコードの行を見る。
_base_blocks_check() {  # <skill ファイル>: 違反したブロックの先頭行を出す(0件なら何も出さない)。読めなければ rc 2
  python3 - "$1" <<'PY'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError as e:
    print(e, file=sys.stderr); sys.exit(2)
bad = []
for m in re.finditer(r"```(?:bash|sh)\n(.*?)```", text, re.S):
    blk = m.group(1)
    code = "\n".join(l for l in blk.split("\n") if not l.lstrip().startswith("#"))
    uses = re.search(r"\$base\b|\$\{base\}", code)
    resolves = re.search(r'(^|\n)\s*if base="\$\(yosage-dev-harness-base-branch', code)
    has_exit = re.search(r"yosage-dev-harness-base-branch[^\n]*\|\|\s*exit", code)
    if has_exit or (uses and not resolves):
        bad.append(blk.strip().split("\n")[0][:60])
print("\n".join(bad))
PY
}
echo "== \$base を使うコードブロックは冒頭で解決し直している(|| exit 1 でシェルを閉じない) =="
for _bb_f in epic-implement epic-create-issues epic-review epic-implement-subissue issue-implement; do
  _bb_bad="$(_base_blocks_check "$H/skills/$_bb_f/SKILL.md")"; _bb_rc=$?
  if [ "$_bb_rc" -eq 0 ] && [ -z "$_bb_bad" ]; then ok "$_bb_f: \$base を使う各ブロックが冒頭で解決し直しており、|| exit が無い"; else ng "$_bb_f: \$base の持ち越し/|| exit のブロックがある(rc=$_bb_rc): $_bb_bad"; fi
done
# negative control: 解決の行を落とした写し・|| exit 1 を戻した写しで落ちる
_bb_src="$(_src_copy)"
python3 - "$_bb_src/harness/skills/epic-create-issues/SKILL.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
i=s.index('  if base="$(yosage-dev-harness-base-branch')
s=s[:i]+'  base="$(yosage-dev-harness-base-branch --declared x y)" || exit 1\n  gh pr create --base "$base"\n  ```\n'+s[s.index("  ```\n",i)+6:]
open(p,'w').write(s)
PY
_bb_bad="$(_base_blocks_check "$_bb_src/harness/skills/epic-create-issues/SKILL.md")"
[ -n "$_bb_bad" ] && ok "negative control: || exit 1 と解決の欠けた \$base ブロックを検出する" || ng "negative control: || exit 1 と解決の欠けた \$base ブロックを検出しなかった"
python3 - "$_bb_src/harness/skills/epic-implement/SKILL.md" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=s.replace('if base="$(yosage-dev-harness-base-branch','x="$(yosage-dev-harness-base-branch',1)
open(p,'w').write(s)
PY
_bb_bad="$(_base_blocks_check "$_bb_src/harness/skills/epic-implement/SKILL.md")"
[ -n "$_bb_bad" ] && ok "negative control: 解決の行を落とした epic-implement のブロックを検出する" || ng "negative control: 解決の行を落とした epic-implement のブロックを検出しなかった"
rm -rf "$_bb_src"
_base_blocks_check "$H/skills/no-such-skill/SKILL.md" >/dev/null 2>&1; exit_is "読めないファイルは失敗(2)になる(0件と同じに扱わない)" 2 "$?"

echo "== 手順のコードブロックを実際に動かして確かめる(文字列とブロックの形だけでなく挙動を見る) =="
_ei_file="$H/skills/epic-implement/SKILL.md"
# SKILL.md の節から bash ブロックを取り出し、プレースホルダを置いて写しとして書き出す
_blk_extract() {  # <file> <節の見出しの先頭> <ブロックの先頭行の正規表現> <出力先>
  python3 - "$@" <<'PY'
import re, sys
f, head, first, out = sys.argv[1:5]
t = open(f, encoding="utf-8").read()
sec = t[t.index(head):]
m = re.search(r"```bash\n(" + first + r".*?)```", sec, re.S)
b = m.group(1)
b = b.replace("--declared <明示か profile の宣言> <リポジトリのルート>", ".").replace("<epic-name>", "x")
open(out, "w").write(b)
PY
}
_run_in() { ( cd "$1" && PATH="$H/bin:$PATH" bash "$2" 2>&1; echo "rc=$?" ); }
_mk_repo() {  # <dir>: 初期コミット1つの remote.git + work(origin/HEAD=main)
  git init -q --bare -b main "$1/remote.git"; git clone -q "$1/remote.git" "$1/work" 2>/dev/null
  ( cd "$1/work" && echo a > a && git add a && gitc commit -qm init && git push -q origin main && git remote set-head origin main >/dev/null 2>&1 )
}
_x="$(mktemp -d)"
_blk_extract "$_ei_file" "### 10." 'git fetch --prune' "$_x/step10.sh"
_blk_extract "$_ei_file" "### 8." 'git fetch origin\nif base=' "$_x/step8.sh"
# (a) GitHub 形式のマージコミット・リモート削除済み・ローカル無し: 何も言わず rc 0
mkdir "$_x/a"; _mk_repo "$_x/a"
( cd "$_x/a/work" && git checkout -qb epic/x && echo 1 > 1 && git add 1 && gitc commit -qm e1 && git push -q origin epic/x && git checkout -q main \
  && gitc merge -q --no-ff epic/x -m "Merge pull request ${HSH}5 from org/epic/x" && git push -q origin main && git push -q origin :epic/x && git branch -qD epic/x )
_o="$(_run_in "$_x/a/work" "$_x/step10.sh")"
out_has   "手順10: マージコミットがあれば正常終了(終了コード0)" "rc=0" "$_o"
out_hasnt "手順10: マージコミットがあれば警報を出さない" "見つからない" "$_o"
# (b) fast-forward: 誤って「マージコミットが無い」警報ではなく、区別できない旨の注意
mkdir "$_x/b"; _mk_repo "$_x/b"
( cd "$_x/b/work" && git checkout -qb epic/x && echo 1 > 1 && git add 1 && gitc commit -qm e1 && git checkout -q main && gitc merge -q --ff-only epic/x && git push -q origin main && git branch -qD epic/x )
_o="$(_run_in "$_x/b/work" "$_x/step10.sh")"
out_has "手順10: fast-forward は区別できない旨の注意に留める" "fast-forward で入った(区別できない)" "$_o"
out_has "手順10: 注意を出しても終了コードは0(呼び出し側が失敗と読まない)" "rc=0" "$_o"
# (c) epic/x-v2 だけが取り込まれている: epic/x には当たらない
mkdir "$_x/c"; _mk_repo "$_x/c"
( cd "$_x/c/work" && git checkout -qb epic/x-v2 && echo 1 > 1 && git add 1 && gitc commit -qm e1 && git checkout -q main \
  && gitc merge -q --no-ff epic/x-v2 -m "Merge pull request ${HSH}6 from org/epic/x-v2" && git push -q origin main && git branch -qD epic/x-v2 )
_o="$(_run_in "$_x/c/work" "$_x/step10.sh")"
out_has "手順10: epic/x-v2 のマージコミットは epic/x に当たらない(語の終わりを見る)" "見つからない" "$_o"
# (d) リモート・ローカルに Epic ブランチが残っている
mkdir "$_x/d"; _mk_repo "$_x/d"
( cd "$_x/d/work" && git checkout -qb epic/x && echo 1 > 1 && git add 1 && gitc commit -qm e1 && git push -q origin epic/x && git checkout -q main && gitc merge -q --no-ff epic/x -m m && git push -q origin main )
_o="$(_run_in "$_x/d/work" "$_x/step10.sh")"
out_has "手順10: リモートに残っていれば削除を依頼する旨を出す" "リモートの Epic ブランチが残っている" "$_o"
out_has "手順10: ローカルに残っていればその旨を出す" "ローカルの Epic ブランチが残っている" "$_o"
# (e) 「Merge branch 'epic/x' into main」の形
mkdir "$_x/e"; _mk_repo "$_x/e"
( cd "$_x/e/work" && git checkout -qb epic/x && echo 1 > 1 && git add 1 && gitc commit -qm e1 && git checkout -q main && gitc merge -q --no-ff epic/x -m "Merge branch 'epic/x' into main" && git push -q origin main && git branch -qD epic/x )
_o="$(_run_in "$_x/e/work" "$_x/step10.sh")"
out_hasnt "手順10: 「Merge branch 'epic/x' into main」の形も取り込みと判定する" "見つからない" "$_o"
# 手順8の状態1: 計画が既定ブランチにあれば出力され、無ければ空(不在でも終了コード0)
mkdir "$_x/p"; _mk_repo "$_x/p"
( cd "$_x/p/work" && mkdir -p .epic_docs/x && echo p > .epic_docs/x/00.md && git add . && gitc commit -qm plan && git push -q origin main )
_o="$(_run_in "$_x/p/work" "$_x/step8.sh")"
out_has "手順8の状態1: 計画があれば ls-tree の出力にファイルが出る" ".epic_docs/x/00.md" "$_o"
mkdir "$_x/q"; _mk_repo "$_x/q"
_o="$(_run_in "$_x/q/work" "$_x/step8.sh")"
out_hasnt "手順8の状態1: 計画が無ければ出力が空(終了コードは0)" ".epic_docs" "$_o"
out_has   "手順8の状態1: 計画が無くても終了コードは0(出力の有無で判定する旨を手順に明記)" "出力の有無で判定する" "$(cat "$_ei_file")"
rm -rf "$_x"
# 手順7の PR の引き方: 一覧の取得に commits を含めない(GraphQL の上限を超える)
out_hasnt "手順7: 一覧クエリに commits を含めない" "--json url,headRefName,commits" "$(cat "$_ei_file")"
out_has   "手順7: 一覧は number,url,headRefName だけ取る" "--json number,url,headRefName" "$(cat "$_ei_file")"
out_has   "手順7: 候補の PR だけ gh pr view --json commits で見る" 'gh pr view "$_num" --json commits' "$(cat "$_ei_file")"
out_hasnt "手順8の状態1: ls-tree に -d を付けない(末尾 / との組み合わせで何も出ない)" 'ls-tree -d' "$(cat "$_ei_file")"
out_has   "手順10: Epic ブランチを作らなかった Epic ではこの確認を行わない旨を明記" "Epic ブランチを作らなかった Epic" "$(cat "$_ei_file")"
out_has   "手順10: 正常系で終了コード1にならない if 形(ローカルブランチの確認)" 'if git show-ref --verify -q refs/heads/epic/<epic-name>; then' "$(cat "$_ei_file")"

# epic-review のフィルタ(Epic の PR・同期の PR を除く)を外すと落ちる
_er_filter='select(.headRefName != $epic and .headRefName != $base)'
out_has "epic-review: Epic の PR(head が epic/<name>)と同期の PR(head が既定ブランチ)を除くフィルタがある" "$_er_filter" "$(cat "$H/skills/epic-review/SKILL.md")"
_er_src="$(_src_copy)"
python3 - "$_er_src/harness/skills/epic-review/SKILL.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('select(.headRefName != $epic and .headRefName != $base)','select(true)')
open(p,'w').write(s)
PY
case "$(cat "$_er_src/harness/skills/epic-review/SKILL.md")" in
  *"$_er_filter"*) ng "negative control: フィルタを select(true) にしても検査が通る(空振り)" ;;
  *) ok "negative control: フィルタを select(true) にすると検査が落ちる" ;;
esac
rm -rf "$_er_src"
