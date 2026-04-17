# docker-uv

macOS に `uv` をインストールせず、Docker コンテナ内だけで `uv` と `uvx` を実行するための最小構成です。

[English README](./README.md)

## 概要

このリポジトリには次のものが含まれます。

- Astral 公式 `uv` イメージを使う Docker Compose 設定
- コンテナ内の `uv` / `uvx` を呼び出す薄いラッパースクリプト
- 再実行を速くする cache と `uv tool install` 用の永続保存先

`uv` と `uvx` の実体は Docker 内にだけ存在します。macOS 側に `uv` をネイティブインストールする必要はありません。

## 前提

- macOS
- `docker compose` が使える Docker Desktop、Colima、または同等の Docker 環境
- `zsh` や `sh` などの POSIX 互換シェル

## 仕組み

リポジトリ直下の `./uv` と `./uvx` は次を行います。

- リポジトリルートを解決する
- `ghcr.io/astral-sh/uv:python3.12-trixie-slim` を Docker Compose で起動する
- 現在位置から最も近い project root または git root を見つけてコンテナに bind mount する
- 現在の相対作業ディレクトリをコンテナ内でも維持する
- cache と tool 環境をこのリポジトリ配下の `.docker/` に永続化する

これにより、任意の作業ディレクトリから project 相対の挙動を保ったまま、Docker ベースの `uv` / `uvx` を共通状態で利用できます。

## セットアップ

リポジトリルートで次を実行します。

```sh
mkdir -p "$HOME/bin"
ln -sf "$(pwd)/uv" "$HOME/bin/uv"
ln -sf "$(pwd)/uvx" "$HOME/bin/uvx"
```

`~/bin` が `PATH` に入っていなければ、`~/.zshrc` に次を追加してください。

```sh
export PATH="$HOME/bin:$PATH"
```

シェルに反映します。

```sh
source ~/.zshrc
```

## アンインストールと掃除

ラッパーの利用をやめるだけなら、symlink を削除します。

```sh
rm -f "$HOME/bin/uv" "$HOME/bin/uvx"
```

このリポジトリが保持している cache と install 済み tool も削除する場合は、次を実行します。

```sh
rm -rf .docker/uv-cache .docker/uv-tools
mkdir -p .docker/uv-cache .docker/uv-tools
touch .docker/uv-cache/.gitkeep .docker/uv-tools/.gitkeep
```

さらに、このプロジェクト用の Docker リソースも片付けたい場合は次です。

```sh
docker compose down --remove-orphans
docker image rm ghcr.io/astral-sh/uv:python3.12-trixie-slim
```

## 使い方

任意の作業ディレクトリで `uv` や `uvx` を実行できます。

```sh
uv --version
uv init
uv sync
uv run python -V
uvx --version
uvx ruff --version
```

`uvx` を前提とする MCP クライアントや各種ローカル自動化設定でも、このラッパーをホストの `uvx` 代わりに利用できます。

ただし、MCP の設定形式はクライアントごとに異なるため、このリポジトリでは特定の設定ファイル形式までは固定していません。

`uv tool install` で入れた tool は永続化されます。

```sh
uv tool install ruff
uv tool dir
uv tool dir --bin
```

初回実行時は Docker イメージの pull が発生します。

## 制約

- `uv` 実行前に Docker が起動している必要があります。
- 目的はホストに `uv` を入れないことであり、Docker 自体を不要にするものではありません。
- install された tool は macOS ネイティブではなく、`.docker/uv-tools/` 配下の Docker 管理領域に保存されます。

## ファイル構成

- `compose.yaml`: `uv` コンテナ用の Docker Compose 定義
- `uv`: `uv` 用のホスト側ラッパースクリプト
- `uvx`: `uvx` 用のホスト側ラッパースクリプト
- `.docker/uv-cache/`: 永続 cache ディレクトリ
- `.docker/uv-tools/`: `uv tool install` の永続データと実行ファイル置き場

## ライセンス

このプロジェクトは MIT License で配布しています。詳細は [LICENSE](./LICENSE) を参照してください。
