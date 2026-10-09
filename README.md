# docker-actions-runner-host-docker

GitHub Actions の self-hosted runner を、コンテナで動かすための Docker イメージです。
runner は**ホストの Docker をそのまま使います** (ホストの `docker.sock` を渡す。runner の中に別の Docker デーモンは動かさない)。ホストでは `docker` しか実行しません。

```
ghcr.io/idein/actions-runner-host-docker:latest
```

タグは `latest` (main の最新) と `sha-<コミット>` です。amd64 と arm64 があります。

## 特徴

- このイメージを、ホストの `docker.sock` を渡して実行すると、launcher ([launcher.sh](launcher.sh)) が runner の登録と、runner のコンテナの起動・停止をします
- job から起動したコンテナも、ホストの Docker で動きます。そのため `docker run -v` に書いたパスはホストで解決されます。job が使うディレクトリ (checkout 先と、job をまたいで残すディレクトリ) は、runner のコンテナにホストと同じ絶対パスでマウントしているので、job の中のパスをそのまま `-v` に使えます
- runner はホストと同じ uid で動かし、`docker.sock` のグループを足して docker を使えるようにします。job が作るファイルは、ホストのユーザーのものになります
- ホストの docker の設定 (`~/.docker/config.json`) にプロキシ (`proxies`) があれば、それだけを runner の中の docker に写します。job から起動したコンテナやビルドも、ホストと同じプロキシを通ります。レジストリの認証情報などは写しません
- runner の登録情報はホストのディレクトリに残すので、runner のコンテナは起動のたびに作り直します。必要なときだけ起動し、終わったら止める使い方を想定しています
- runner の自動更新は止めています (`--disableupdate`)。ベースのイメージ (`ghcr.io/actions/actions-runner`) を Dependabot で更新し、main にマージするとイメージを push します

## 使い方

次のようなシェル関数を用意しておくと便利です。`RUNNER_REPO_URL` や `RUNNER_LABELS` は、使うリポジトリに合わせて変えてください。

```bash
actions-runner() {
  docker run --rm -i --init --pull always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e HOST_HOME="$HOME" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -e RUNNER_REPO_URL=https://github.com/OWNER/REPO \
    -e RUNNER_LABELS=my-label \
    -e RUNNER_NAME="${RUNNER_NAME:-$(hostname)}" \
    -e RUNNER_BASE="$HOME/actions-runner" \
    -e RUNNER_TOKEN \
    ghcr.io/idein/actions-runner-host-docker:latest "$@"
}
```

```bash
# 登録する (登録用のトークンは、リポジトリの Settings → Actions → Runners → New self-hosted runner で発行する)
read -rs RUNNER_TOKEN && export RUNNER_TOKEN && actions-runner register && unset RUNNER_TOKEN

actions-runner up        # 起動する (バックグラウンド)
actions-runner status    # 状態を表示する
actions-runner logs      # ログを表示する
actions-runner down      # 止める (登録は残る)

# 登録を消す (削除用のトークンは、Settings → Actions → Runners → (runner) → Remove で発行する)
read -rs RUNNER_TOKEN && export RUNNER_TOKEN && actions-runner unregister && unset RUNNER_TOKEN
```

`--pull always` を付けると、実行のたびに最新のイメージを使います。固定したいときは、`sha-<コミット>` のタグや digest を指定してください。

### 環境変数

| 変数 | 内容 |
| --- | --- |
| `HOST_HOME`, `HOST_UID`, `HOST_GID` | ホストのホームディレクトリと uid / gid (必須) |
| `RUNNER_REPO_URL` | runner を登録するリポジトリの URL (register で必須) |
| `RUNNER_LABELS` | runner のラベル。カンマ区切り (register で必須) |
| `RUNNER_NAME` | runner の名前 (register で必須) |
| `RUNNER_TOKEN` | 登録用 / 削除用のトークン (register / unregister で必須) |
| `RUNNER_BASE` | runner が使うホストのディレクトリ (既定: `$HOST_HOME/actions-runner`) |
| `RUNNER_CONTAINER` | runner のコンテナ名 (既定: `actions-runner`) |
| `HOST_DOCKER_CONFIG` | ホストの docker の設定 (既定: `$HOST_HOME/.docker/config.json`) |

### `RUNNER_BASE` の中身

| ディレクトリ | 内容 |
| --- | --- |
| `work/` | checkout 先 (runner の作業ディレクトリ) |
| `state/` | job をまたいで残すディレクトリ。job には環境変数 `PERSISTENT_STATE_ROOT` で渡す |
| `config/` | runner の登録情報 |
| `docker-config/` | runner の中の docker の設定 (ホストの設定からプロキシだけを写したもの) |

`work/` と `state/` は、runner のコンテナにホストと同じ絶対パスでマウントしています。

## セキュリティ

- runner は `docker.sock` を使うので、**job はホストの Docker を root 相当で操作できます**。信頼できるリポジトリにだけ登録してください。public リポジトリに登録する場合は、fork からの PR で job が動かないようにしてください
- launcher は `docker.sock` を使うので root で動きます。ホストのディレクトリは、`RUNNER_BASE` とホストの docker の設定ファイル (読み取り専用) だけをマウントします
- `latest` を pull して使う場合、このリポジトリの main に入った変更は、各ホストの次の起動から動きます

## 開発

```bash
docker build -t actions-runner-host-docker:local .
```

上のシェル関数のイメージを `actions-runner-host-docker:local` に替えると、手元でビルドしたイメージで試せます (runner のコンテナには、launcher と同じイメージを使います)。

main に push すると、ワークフロー [publish](.github/workflows/publish.yml) がイメージをビルドして push します。
