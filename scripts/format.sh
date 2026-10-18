#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift-format format -i -r Wirt WirtExtension
bun --cwd WirtExtension/WebExtension prettier --write ../.. 2>&1 | grep -v '(unchanged)' || true
