#!/bin/bash
# runner のコンテナの entrypoint (launcher.sh が、このイメージから runner のコンテナを起動するときに使う)。
# runner は登録情報 (.runner, .credentials, .credentials_rsaparams) を /home/runner に置くが、
# コンテナは毎回作り直すので、ホストのディレクトリ (/runner-config にマウント) との間でコピーして残す。
set -euo pipefail

cd /home/runner
files=(.runner .credentials .credentials_rsaparams)

restore() {
  for f in "${files[@]}"; do
    if [[ ! -f "/runner-config/$f" ]]; then
      echo "error: runner が登録されていません。先に register を実行してください" >&2
      exit 1
    fi
    cp "/runner-config/$f" "$f"
  done
}

case "${1:-run}" in
  register)
    ./config.sh --unattended --replace --disableupdate \
      --url "$RUNNER_REPO_URL" --token "$RUNNER_TOKEN" \
      --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --work "$RUNNER_WORK_DIR"
    for f in "${files[@]}"; do cp "$f" "/runner-config/$f"; done
    ;;
  run)
    restore
    exec ./run.sh
    ;;
  unregister)
    restore
    ./config.sh remove --token "$RUNNER_TOKEN"
    for f in "${files[@]}"; do rm -f "/runner-config/$f"; done
    ;;
  *)
    echo "usage: $0 register|run|unregister" >&2
    exit 1
    ;;
esac
