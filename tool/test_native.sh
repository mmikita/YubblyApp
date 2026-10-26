#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
if command -v javac >/dev/null 2>&1 && javac -version >/dev/null 2>&1 \
  && command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
  javac -d "$out" android/app/src/main/java/app/yubbly/yubbly_app/MixerMath.java test/native/MixerMathTest.java
  java -cp "$out" app.yubbly.yubbly_app.MixerMathTest
else
  echo "SKIP: javac/java not found; Android mixer test not run."
fi
if [[ "$(uname -s)" == "Darwin" ]] && command -v swiftc >/dev/null 2>&1; then
  swiftc -O apple/YubblyPlaybackEngine.swift test/native/AppleMixerMathTest.swift \
    -o "$out/apple_mixer" -framework AVFoundation
  "$out/apple_mixer"
fi
