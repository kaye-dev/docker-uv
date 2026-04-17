# docker-uv

`docker-uv` は、macOS に `uv` をインストールせずに `uv` と `uvx` を使いたいときのための、小さな Docker ベースのラッパーです。

[English README](./README.md)

## 概要

このリポジトリには、次のようなものが入っています。

- Astral 公式の `uv` イメージを使う Docker Compose 設定
- コンテナ内の `uv` / `uvx` を呼び出すホスト側ラッパースクリプト
- 再実行を速くする cache と、`uv tool install` 用の永続保存先

`uv` と `uvx` の実体は Docker の中にだけあり、macOS 側へネイティブインストールする必要はありません。

## 前提

利用前の前提は次の通りです。

- macOS
- `docker compose` が使える Docker Desktop、Colima、または同等の Docker 環境
- `zsh` や `sh` などの POSIX 互換シェル

## 仕組み

リポジトリ直下の `./uv` と `./uvx` は、次の流れで動きます。

- リポジトリルートを解決する
- `ghcr.io/astral-sh/uv:python3.12-trixie-slim` を Docker Compose で起動する
- 現在位置から最も近い project root または git root を探し、どちらも無ければ current directory をそのまま使ってコンテナへ bind mount する
- 今いる相対パスをコンテナ内でも保ったまま実行する
- 見つかった project root、git root、または current directory ごとに cache を `.docker/projects/` 配下へ分離して保存する
- `uv tool install` で入れた tool は `.docker/uv-tools/` に保存する

そのため、作業中のディレクトリ感覚をあまり変えずに、Docker ベースの `uv` / `uvx` を使えます。

## この構成でできること

この構成で実現していることは、主に次の 4 つです。

- macOS ホストに `uv` や `uvx` をインストールせずに利用できる
- cache と tool データを、ホスト全体の `uv` 管理領域ではなく、このリポジトリ配下の `.docker/` にまとめられる
- project root、git root、または current directory ごとに cache を分けられるため、このラッパー経由では無関係なプロジェクト同士で cache を共有しにくい
- Compose 設定で `UV_LINK_MODE=copy` を明示しているため、cache から環境へリンクせずコピーする構成になっている

特に、cache 分離と `UV_LINK_MODE=copy` の組み合わせは、cache と各プロジェクト環境の結びつきを弱めたいときに意味があります。この構成では、ある環境内でインストール済みパッケージを直接編集しても、共有 cache や共有リンク経由で別の環境へ波及しにくくなります。

ただし、ここで言っているのはあくまで「波及しにくくなる」という範囲です。`uv` の cache 自体を無効化するものではありませんし、インストール済みパッケージを直接編集してよい、という意味でもありません。

## セットアップ

まずはリポジトリルートで、`~/bin` に symlink を作成します。

```sh
mkdir -p "$HOME/bin"
ln -sf "$(pwd)/uv" "$HOME/bin/uv"
ln -sf "$(pwd)/uvx" "$HOME/bin/uvx"
ln -sf "$(pwd)/uv-refresh" "$HOME/bin/uv-refresh"
ln -sf "$(pwd)/uv-cache-clean" "$HOME/bin/uv-cache-clean"
```

`~/bin` が `PATH` に入っていない場合は、`~/.zshrc` に次を追加してください。

```sh
export PATH="$HOME/bin:$PATH"
```

追加後は、シェルを読み直します。

```sh
source ~/.zshrc
```

## 使い方

セットアップが済めば、任意の作業ディレクトリで `uv` や `uvx` を実行できます。

```sh
uv --version
uv init
uv sync
uv run python -V
uvx --version
uvx ruff --version
```

補助コマンドも用意しています。

```sh
uv-refresh
uv-cache-clean
uv-cache-clean ruff
```

- `uv-refresh` は `uv sync --refresh` のショートカットです
- `uv-cache-clean` は、その project に分離された cache に対する `uv cache clean` のショートカットです

`uvx` を前提とする MCP クライアントや、各種ローカル自動化設定でも、このラッパーをホストの `uvx` の代わりとして利用できます。
ただし、MCP の設定形式はクライアントごとに異なるため、このリポジトリでは特定の設定ファイル形式までは固定していません。

`uv tool install` で入れた tool は永続化されます。

```sh
uv tool install ruff
uv tool dir
uv tool dir --bin
```

初回実行時は Docker イメージの pull が入ります。

## アンインストールと掃除

利用をやめるだけなら、まずは symlink を削除します。

```sh
rm -f "$HOME/bin/uv" "$HOME/bin/uvx" "$HOME/bin/uv-refresh" "$HOME/bin/uv-cache-clean"
```

このリポジトリが持っている cache や install 済み tool も削除したい場合は、次を実行してください。

```sh
rm -rf .docker/projects .docker/uv-tools .docker/uv-cache
mkdir -p .docker/projects .docker/uv-tools .docker/uv-cache
touch .docker/projects/.gitkeep .docker/uv-tools/.gitkeep .docker/uv-cache/.gitkeep
```

さらに、このプロジェクト用の Docker リソースまで片付ける場合は次です。

```sh
docker compose down --remove-orphans
docker image rm ghcr.io/astral-sh/uv:python3.12-trixie-slim
```

## 制約

このリポジトリで解決しないこと、前提になることもあります。

- 実行前に Docker が起動している必要があります
- 目的はホストに `uv` を入れないことであり、Docker 自体を不要にするものではありません
- install された tool は macOS ネイティブではなく、`.docker/uv-tools/` 配下の Docker 管理領域に保存されます

## ファイル構成

主なファイルは次の通りです。

- `compose.yaml`: `uv` コンテナ用の Docker Compose 定義
- `docker-uv-common.sh`: project 検出と cache 分離に使う共通ロジック
- `uv`: `uv` 用のホスト側ラッパースクリプト
- `uvx`: `uvx` 用のホスト側ラッパースクリプト
- `uv-refresh`: `uv sync --refresh` 用の補助ラッパー
- `uv-cache-clean`: `uv cache clean` 用の補助ラッパー
- `.docker/projects/`: project ごとの cache ディレクトリ
- `.docker/uv-tools/`: `uv tool install` の永続データと実行ファイル置き場

## ライセンス

このプロジェクトは MIT License で配布しています。詳しくは [LICENSE](./LICENSE) を参照してください。
