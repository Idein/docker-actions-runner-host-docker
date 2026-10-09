# GitHub Actions の self-hosted runner をコンテナで動かすためのイメージ。公式の runner のイメージに、次の 2 つを足したもの。
# - launcher.sh (ENTRYPOINT): ホストの docker.sock を渡して実行すると、runner を登録し、runner のコンテナを起動・停止する
# - entrypoint.sh: runner のコンテナの entrypoint。登録情報をホストのディレクトリに残す
# runner の自動更新は止めている (--disableupdate) ので、ベースのイメージを Dependabot で更新する
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807

# GitHub Container Registry で、パッケージをこのリポジトリにつなぐ (ベースのイメージの actions/runner は引き継がない)
LABEL org.opencontainers.image.source="https://github.com/Idein/docker-actions-runner-host-docker" \
      org.opencontainers.image.description="GitHub Actions self-hosted runner in a container, using the host Docker with same-path mounts"

COPY launcher.sh /usr/local/bin/runner-launcher
COPY entrypoint.sh /usr/local/bin/runner-entrypoint
# launcher は docker.sock を使うので root で動かす。runner のコンテナは、launcher がホストの uid を指定して起動する
USER root
ENTRYPOINT ["/usr/local/bin/runner-launcher"]
