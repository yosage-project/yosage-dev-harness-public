# よくある詰まり

症状から引く。上から順に、よくあるもの。

## Claude の操作が「この場では実行できません」で止まった

ガードが止めている。どのガードかは Claude の報告に出る。

- 進め方を変えれば通るもの（保護ブランチへの直接コミット・`git commit -a`・`/tmp` のスクリプトの
  直接実行・グローバルなインストールなど）は、Claude に指示し直す。
- 本当に必要な操作（force push・PR のマージ・秘密ファイルの読み取りなど）は、**人が自分のターミナルで
  行う**。ガードを切る方法は無い。

止まるものの一覧と理由は [ガードと機密](guard-and-sensitive-data.md)。

特定の止まり方への対処は次のとおり。

| 止められた操作 | 対処 |
|---|---|
| 保護ブランチ（`main` / `master` / 既定ブランチ）への `git commit` | `git checkout -b <type>/<name>` で作業ブランチを切ってからコミットし、PR にする |
| `git commit -a` / パス指定つきのコミット | `git add` で明示的にステージしてから `git commit` する |
| ステージした内容に秘密 | 該当ファイルから値を取り除くか、`.claude/yosage-dev-harness.local.json` のような追跡されない場所へ退避する。報告には一致した値は出ない |
| ステージしたファイルが300を超える | `git reset HEAD <path>` で一部を外し、意図した範囲だけにする |
| `/tmp` のスクリプトの直接実行 | `.claude/tmp/` に置いて実行するか、使い捨てコンテナ（`yosage-dev-harness-scratch`）経由で実行する |
| `pip install` などのグローバルなインストール | プロジェクト内に閉じる指定にするか、`uv run --with <パッケージ>` や `npx`、使い捨てコンテナを使う |
| `compose.yml` のあるリポジトリでのホスト実行 | `make` や `docker compose exec` を使う |
| PR や issue の本文に `../` | 内容を本文にそのまま書くか、耐久性のある URL を使う |
| Grep の検索範囲に秘密ファイルが入っている | 検索の対象を、秘密ファイルを含まないパスや拡張子に絞る |

## すべてのガードが「判定できない」で止まる

ガードは、`jq` か `python3` のどちらかが無いと判定できず、安全側に倒して止まる。どちらかを
入れる（[README の前提](../README.md#前提)）。セッション開始時にも、前提を確かめて問題があれば
知らせる。

## 更新したのに反映されない

- マーケットプレイス経由の更新は、プラグインの版（`version`）が上がったリリースのときだけ届く。
- 常時適用される規律（ルール）は、セッション開始時とサブエージェントの起動時に注入される。
  更新したあとは、**新しいセッション**から効く。
- 導入先の `.gitignore` の不足行と推奨設定の見本を今の版に合わせるには、
  `/yosage-dev-harness:update` を打つ（設定ファイルの項目は書き足さない。初回は `/yosage-dev-harness:setup`）。
- 導入先の状態は `/yosage-dev-harness:status` で確かめられる（書き込まない）。設定・`.gitignore` の
  不足行・`.claude/worktrees/.gitignore`・推奨設定の見本の版・スキーマに無い項目が表で出る。
- 同じ名前のプラグイン `yosage-dev-harness` を、2つのマーケットプレイスから同時に有効にしない
  （[README の注意](../README.md#注意)）。

## 知見が引けない・共有ストアが同期されない

**ローカルの知見の一覧が出ない**: 一覧の取得コマンドの結果は、終了コードと出力の組で読む。

| 状況 | 終了コード | 意味 |
|---|---|---|
| `.claude/knowledge/` があり、該当が0件 | 0（出力なし） | 該当する知見が無い |
| `.claude/knowledge/` が無く、同じ `.claude/` に設定ファイルがある | 0（出力なし） | まだ1件も書いていない導入先 |
| `.claude/knowledge/` も設定ファイルも無い・権限が無い・`.claude/` 自体が無い | 0以外 | **失敗**。置き場の解決に失敗している可能性がある |

0以外の終了を「関連する知見なし」とみなして進まない。そのときは止まって人に報告する、という
決まりになっている。コマンドは Claude が実行する。

```bash
yosage-dev-harness-knowledge-index .claude/knowledge --list <ドメイン>
```

**共有ストアが届かない**:

1. `.claude/yosage-dev-harness.local.json` に `knowledge.enabled: true` と `knowledge.source` が
   あるか（無効のときは何もせず進む）。設定ファイルが壊れた JSON のときも、同期はスキップされる。
2. `knowledge.source` の URL を、この環境で `git clone` できるか（オフライン・権限・URL の誤りだと
   取得に失敗し、前回の写しがそのまま使われる）。
3. 同期は、セッション開始時に背景で行う。開始した直後はまだ届いていないことがある。
4. 同期の記録は `.claude/knowledge/.sync-log`、反映済みのストアの版は
   `.claude/knowledge/.global-sync`。`.claude/knowledge/global/` が写し本体。

**写しを手で直した**: 次の同期で置き換わる。共有ストアを直すときは `/yosage-dev-harness:promote-knowledge`
を使う（[知見](knowledge.md)）。

## 実装役が「隔離されていない」と報告して止まった

実装役は着手時に、自分の作業ディレクトリが `.claude/worktrees/<id>` の下かを確かめる。共有の
チェックアウトそのものにいるときは、編集もコミットもブランチ切り替えもせず、自分で作業ツリーを
作って直そうともせずに止まる。作業ツリーを用意するのは Claude 本体（メイン）の役目なので、
メインが作業ツリーを用意し直して、もう一度任せる。

作業ツリーの置き場が `.claude/worktrees/<id>` から外れると、隔離のガードも後始末も働かない。
`.claude/worktrees/.gitignore` が無い・追跡されている場合は `/yosage-dev-harness:status` に出る。
`/yosage-dev-harness:setup`（初回）か `/yosage-dev-harness:update` で整う。

## PR のベースブランチが決まらない（`epic-implement` や `issue-implement` が止まる）

ベースは、次の順で決まる。投入時に指示されたもの → 導入先の profile（`.claude/rules/<名前>/profile.md`）の
宣言 → GitHub の既定ブランチ（`origin/HEAD`）。どれでも決まらないと止まって人に聞く。

- GitHub の既定ブランチが取れない: `git remote set-head origin --auto` を実行する。
- 既定ブランチとは別のブランチへ取り込む導入先: profile に次の1行を書く。

  ```
  - **base ブランチ: `<名前>`**
  ```

- 宣言したブランチが `origin` に無い: 宣言の誤り。profile を直す。

## `epic-implement` が止まる

| 止まり方 | 原因と対処 |
|---|---|
| 計画ドキュメントが見つからない | `.epic_docs/<epic-name>/` がどこにも無い。今から作るか、計画なしで進めるかを決める。Epic ブランチの上にだけある場合は、`git fetch origin` のあとで見つかる |
| 指定したフェーズが見つからない | フェーズ名の誤り、または未作成。見つかった計画の場所と探した名前が示されるので確かめる |
| Sub-issue の一覧に `(要確認)` が付く | 本文から取り出した一覧が、GitHub のネイティブな紐づけと食い違う。一覧が空や不完全の恐れがあるので、警告を読んで直す（`epic-create-issues` の紐づけのやり直しなど） |
| issue を解決できない | 引数の形（`<owner>/<repo>#<N>`）の誤り、またはワークスペースでの番号だけの指定。[ワークスペース](workspace.md) |
| 取り込み先の記載が無い Sub-issue がある | 古い形で起票された Epic。推測では決めず、人に取り込み先を確かめる |

## GitHub のラベルが無い

`/yosage-dev-harness:issue-create` は、種別ラベル（`feat` / `fix` / `refactor` / `chore` / `docs` /
`test` / `perf`）が無ければ、`yosage-dev-harness-sync-labels` で作ってから起票する。Epic の
ラベル `epic` などを含め、標準のラベルを事前に揃えたいときは、対象リポジトリのルートを渡して
Claude に実行させる（`gh` でログイン済みであること）。GitHub が最初から持つラベル（`bug` や
`documentation` など）は残るので、起票するときは標準のラベルから選ぶ。

```bash
yosage-dev-harness-sync-labels <リポジトリのルート>
```

## コミットの `Co-Authored-By` 署名について知らされた

コミットの末尾に付ける AI の署名は、**コミット先のリポジトリが自社の所有か**で扱いが変わる。
自社のリポジトリは付けるのが既定。自社でないリポジトリは、AI を使うことを相手に伝えてあると
profile に宣言があるときだけ付け、宣言がなければ付けない。知らせは止めはせず、気づかせるだけ。
squash しない運用では、push 済みの署名は後から消せないため、コミットの時点で判断する。

## まだ解決しないとき

- 今の導入状態: `/yosage-dev-harness:status`
- 今できること・この作業の進め方: `/yosage-dev-harness:harness-help`
- 設定: [README の設定](../README.md#設定)
