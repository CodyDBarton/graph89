#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${JAVA_HOME:-}" ] && [ -d /opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home ]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home
fi
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
./gradlew :app:assembleArm64Release --no-daemon -Djava.net.preferIPv4Stack=true "$@"
