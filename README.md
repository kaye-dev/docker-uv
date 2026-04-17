# docker-uv

`uv` を macOS にインストールせず、Docker コンテナ内だけで実行するための最小構成です。

## 使い方

前提:
- Docker Desktop など、`docker compose` が使えること

このリポジトリ直下の `uv` は、Docker Compose 経由で `ghcr.io/astral-sh/uv:python3.12-trixie-slim` を起動するラッパーです。

リポジトリ配下のどこからでも `uv` と打てるようにするには、1 回だけシンボリックリンクを張ります。

```sh
mkdir -p "$HOME/bin"
ln -sf "$(pwd)/uv" "$HOME/bin/uv"
```

`~/bin` が `PATH` に入っていなければ、`~/.zshrc` に次を追加します。

```sh
export PATH="$HOME/bin:$PATH"
```

反映:

```sh
source ~/.zshrc
```

## 動作

- `uv` 本体は macOS に入りません
- 実体は Docker コンテナ内の `uv` です
- カレントディレクトリがこのリポジトリ配下のときだけ動きます
- 作業ディレクトリは現在位置に追従します
- `uv` のキャッシュは `.docker/uv-cache/` に保存されます

## 例

```sh
uv --version
uv init
uv sync
uv run python -V
```

初回実行時は Docker イメージの pull が走ります。
