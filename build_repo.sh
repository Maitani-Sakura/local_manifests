#!/bin/bash

set -e

# PATCH URL（指定された最新版）
PATCH_URL="https://raw.githubusercontent.com/Maitani-Sakura/local_manifests/refs/heads/lineage-22.1/idevicerestore.patch"

# 一時作業ディレクトリ
WORKDIR=$(mktemp -d)
echo "Working directory: $WORKDIR"

# 単一リポジトリ処理関数
process_repo() {
    local repo="$1"
    local tag="$2"
    local name
    name=$(basename "$repo" .git)
    local path="$WORKDIR/${name}-${tag}"

    echo "[$tag] Cloning: $repo"
    git clone "$repo" "$path" > /dev/null 2>&1 || return 1

    cd "$path" || return 1

    # 条件に該当する場合だけパッチを適用
    if [[ "$repo" =~ (^|/)idevicerestore(\.git)?$ ]] && [[ ! "$repo" =~ libidevicerestore ]]; then
        echo "[$tag] Applying idevicerestore patch..."
        curl -fsSL "$PATCH_URL" -o patch.diff || return 1
        git apply patch.diff || return 1
    fi

    echo "[$tag] Running build..."
    PKG_CONFIG_PATHS=/usr/local/lib/pkgconfig/ ./autogen.sh && \
    make -j"$(nproc)" && \
    sudo make install
}

# 引数チェック
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <git_repo_url1> [git_repo_url2 ...]"
    exit 1
fi

REPOS=("$@")
FAILED_REPOS=("${REPOS[@]}")
ATTEMPT=1

# 成功するまで再試行
while [ "${#FAILED_REPOS[@]}" -gt 0 ]; do
    echo ""
    echo "=== Attempt #$ATTEMPT ==="
    NEXT_FAILED=()

    for repo in "${FAILED_REPOS[@]}"; do
        if process_repo "$repo" "try${ATTEMPT}"; then
            echo "[Success] $repo"
        else
            echo "[Fail] $repo"
            NEXT_FAILED+=("$repo")
        fi
    done

    if [ "${#NEXT_FAILED[@]}" -eq 0 ]; then
        echo ""
        echo "✅ All repositories built successfully."
        break
    else
        echo ""
        echo "🔁 Retrying ${#NEXT_FAILED[@]} failed repositories..."
        FAILED_REPOS=("${NEXT_FAILED[@]}")
        ((ATTEMPT++))
    fi
done

echo ""
echo "✔ All done."
