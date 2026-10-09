#!/bin/bash
# GitHub Actions の self-hosted runner を、コンテナとして登録・起動・停止する (このイメージの ENTRYPOINT)。
# このイメージを、ホストの docker.sock を渡して実行する。ホストのことは環境変数で受け取る:
#   HOST_HOME, HOST_UID, HOST_GID   ホストのホームディレクトリと uid / gid (runner はこの uid で動かす)
#   RUNNER_REPO_URL                 runner を登録するリポジトリの URL (register)
#   RUNNER_LABELS                   runner のラベル。カンマ区切り (register)
#   RUNNER_NAME                     runner の名前 (register)
#   RUNNER_TOKEN                    登録用 / 削除用のトークン (register / unregister)
#   RUNNER_BASE                     runner が使うホストのディレクトリ (既定: $HOST_HOME/actions-runner)
#   RUNNER_CONTAINER                runner のコンテナ名 (既定: actions-runner)
#   HOST_DOCKER_CONFIG              ホストの docker の設定 (既定: $HOST_HOME/.docker/config.json)
#
# usage: <command>
#   register    runner をリポジトリに登録する
#   up          runner を起動する (バックグラウンド)
#   down        runner を止める (登録は残る)
#   status      runner のコンテナの状態を表示する
#   logs        runner のログを表示する
#   unregister  runner の登録を消す
set -euo pipefail

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

CONTAINER="${RUNNER_CONTAINER:-actions-runner}"

# ホストのディレクトリを使うコマンドの準備
init_host() {
  : "${HOST_HOME:?HOST_HOME (ホストの \$HOME) を渡してください}"
  : "${HOST_UID:?HOST_UID (ホストの uid) を渡してください}"
  : "${HOST_GID:?HOST_GID (ホストの gid) を渡してください}"
  RUNNER_BASE="${RUNNER_BASE:-$HOST_HOME/actions-runner}"
  HOST_DOCKER_CONFIG="${HOST_DOCKER_CONFIG:-$HOST_HOME/.docker/config.json}"
  local p
  for p in "$RUNNER_BASE" "$HOST_DOCKER_CONFIG"; do
    if [[ "$p" != /* ]]; then
      echo "error: $p は絶対パスにしてください" >&2
      exit 1
    fi
  done
  # 自分 (このコンテナ) のイメージ。runner のコンテナも、作業用のコンテナも同じイメージで動かす
  IMAGE="$(docker inspect --format '{{.Image}}' "$HOSTNAME")"
}

# runner が使うディレクトリを、作業用のコンテナで用意する。ホストのホーム全体はマウントせず、必要なところだけをマウントする。
# runner の中の docker が読む設定 (docker-config/config.json) には、ホストの docker の設定からプロキシ (proxies) だけを写す。
# docker は proxies に従って、起動するコンテナやビルドに HTTP(S)_PROXY などを渡すので、job から起動したコンテナも
# ホストと同じプロキシを通る。レジストリの認証情報などは写さない (job から読めてしまうため)
prepare_host() {
  local proxies='{"proxies": {}}' config_mount="type=bind,src=$HOST_DOCKER_CONFIG,dst=/host-docker-config.json,readonly"
  # --mount は、-v と違ってホストに無いファイルを作らずに失敗するので、ホストの docker の設定があるかの確認に使う
  if docker run --rm --mount "$config_mount" --entrypoint true "$IMAGE" 2>/dev/null; then
    proxies="$(docker run --rm --mount "$config_mount" --entrypoint jq "$IMAGE" '{proxies: (.proxies // {})}' /host-docker-config.json)"
  fi
  # RUNNER_BASE が無ければ、docker が root で作るので、ホストのユーザーのものにする
  printf '%s\n' "$proxies" | docker run --rm -i -v "$RUNNER_BASE:$RUNNER_BASE" --entrypoint bash "$IMAGE" -c '
    set -euo pipefail
    base="$1" owner="$2"
    mkdir -p "$base/work" "$base/state" "$base/config" "$base/docker-config"
    cat >"$base/docker-config/config.json"
    chown "$owner" "$base" "$base/work" "$base/state" "$base/config" "$base/docker-config" "$base/docker-config/config.json"
    chmod 700 "$base/config"
  ' _ "$RUNNER_BASE" "$HOST_UID:$HOST_GID"
}

# runner のコンテナを起動する。
# runner の中から docker.sock 経由でコンテナを起動すると、-v に書いたパスは runner ではなく Docker のホストで解決される。
# そのため、job が -v に使うディレクトリ (checkout 先の work/、job をまたいで残す state/) は、ホストと同じ絶対パスでマウントする。
# runner はホストと同じ uid で動かし (作るファイルの所有者を揃える)、docker.sock のグループを足して docker を使えるようにする
runner_docker() {
  docker run --user "$HOST_UID:$HOST_GID" --group-add "$(stat -c %g /var/run/docker.sock)" -e HOME=/home/runner \
    -e RUNNER_REPO_URL -e RUNNER_NAME -e RUNNER_LABELS -e RUNNER_TOKEN \
    -e RUNNER_WORK_DIR="$RUNNER_BASE/work" \
    -e PERSISTENT_STATE_ROOT="$RUNNER_BASE/state" \
    -e DOCKER_CONFIG=/runner-docker-config \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$RUNNER_BASE/work:$RUNNER_BASE/work" \
    -v "$RUNNER_BASE/state:$RUNNER_BASE/state" \
    -v "$RUNNER_BASE/config:/runner-config" \
    -v "$RUNNER_BASE/docker-config:/runner-docker-config" \
    --entrypoint /usr/local/bin/runner-entrypoint \
    "$@"
}

cmd="${1:-}"
case "$cmd" in
  register | unregister)
    : "${RUNNER_TOKEN:?RUNNER_TOKEN にトークンを渡してください}"
    if [[ "$cmd" == register ]]; then
      : "${RUNNER_REPO_URL:?RUNNER_REPO_URL (登録するリポジトリの URL) を渡してください}"
      : "${RUNNER_LABELS:?RUNNER_LABELS (runner のラベル。カンマ区切り) を渡してください}"
      : "${RUNNER_NAME:?RUNNER_NAME (runner の名前) を渡してください}"
    fi
    init_host
    prepare_host
    runner_docker --rm "$IMAGE" "$cmd"
    ;;
  up)
    init_host
    prepare_host
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    RUNNER_TOKEN="" runner_docker -d --name "$CONTAINER" --restart no "$IMAGE" run >/dev/null
    echo "runner を起動しました (コンテナ: $CONTAINER)"
    ;;
  down)
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    echo "runner を止めました"
    ;;
  status)
    docker ps -a --filter "name=^${CONTAINER}$" --format '{{.Names}}: {{.Status}}'
    ;;
  logs)
    exec docker logs -f "$CONTAINER"
    ;;
  *)
    usage
    exit 1
    ;;
esac
