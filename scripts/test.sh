#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swift-module-cache"
swift test --disable-sandbox --scratch-path "$PROJECT_DIR/.build" --cache-path "$PROJECT_DIR/.build/cache" --config-path "$PROJECT_DIR/.build/configuration" --security-path "$PROJECT_DIR/.build/security"
