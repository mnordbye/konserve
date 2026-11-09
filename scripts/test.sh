#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
swift test --package-path "$ROOT_DIR/Packages/SMBConnectorCore"
