# docker-uv

macOS に `uv` をインストールせず、Docker コンテナ内だけで `uv` を実行するための最小構成です。

[English README](./README.md)

## 概要

このリポジトリには次のものが含まれます。

- Astral 公式 `uv` イメージを使う Docker Compose 設定
- コンテナ内の `uv` を呼び出す薄いラッパースクリプト
- 再実行を速くするためのローカルキャッシュ保存先

`uv` の実体は Docker 内にだけ存在します。macOS 側に `uv` をネイティブインストールする必要はありません。

## 前提

- macOS
- `docker compose` が使える Docker Desktop、Colima、または同等の Docker 環境
- `zsh` や `sh` などの POSIX 互換シェル

## 仕組み

リポジトリ直下の `./uv` は次を行います。

- リポジトリルートを解決する
- 現在の作業ディレクトリがこのリポジトリ配下か確認する
- `ghcr.io/astral-sh/uv:python3.12-trixie-slim` を Docker Compose で起動する
- 現在の作業ディレクトリに対応する場所をコンテナ内の作業ディレクトリにする

プロジェクトは `/workspace` に mount され、`uv` のキャッシュは `.docker/uv-cache/` に保存されます。

## セットアップ

リポジトリルートで次を実行します。

```sh
mkdir -p "$HOME/bin"
ln -sf "$(pwd)/uv" "$HOME/bin/uv"
```

`~/bin` が `PATH` に入っていなければ、`~/.zshrc` に次を追加してください。

```sh
export PATH="$HOME/bin:$PATH"
```

シェルに反映します。

```sh
source ~/.zshrc
```

## 使い方

このリポジトリ配下であれば、どこからでも `uv` を実行できます。

```sh
uv --version
uv init
uv sync
uv run python -V
```

初回実行時は Docker イメージの pull が発生します。

## 制約

- ラッパーは、このリポジトリ配下にいるときだけ動作します。
- `uv` 実行前に Docker が起動している必要があります。
- 目的はホストに `uv` を入れないことであり、Docker 自体を不要にするものではありません。

## ファイル構成

- `compose.yaml`: `uv` コンテナ用の Docker Compose 定義
- `uv`: ホスト側のラッパースクリプト
- `.docker/uv-cache/`: コンテナ内 `uv` が使うローカルキャッシュ

## ライセンス

このプロジェクトは MIT License で配布しています。詳細は [LICENSE](./LICENSE) を参照してください。
