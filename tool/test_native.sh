#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
javac -d "$out" android/app/src/main/java/app/yubbly/yubbly_app/MixerMath.java test/native/MixerMathTest.java
java -cp "$out" app.yubbly.yubbly_app.MixerMathTest
