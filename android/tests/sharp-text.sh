#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ -z "${JAVA_HOME:-}" ] && [ -d /opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home ]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@11/libexec/openjdk.jdk/Contents/Home
fi
mkdir -p build/sharp-text-tests
"${JAVA_HOME:+$JAVA_HOME/bin/}javac" -d build/sharp-text-tests \
    app/src/main/java/com/graph89/emulationcore/SharpTextRecognizer.java \
    app/src/main/java/com/graph89/emulationcore/RomGlyphOutline.java \
    android/tests/RomGlyphOutlineTest.java \
    android/tests/SmallLabelITest.java \
    android/tests/PrettyPrintTest.java \
    android/tests/SharpTextRecognizerTest.java
"${JAVA_HOME:+$JAVA_HOME/bin/}java" -cp build/sharp-text-tests SharpTextRecognizerTest
"${JAVA_HOME:+$JAVA_HOME/bin/}java" -cp build/sharp-text-tests RomGlyphOutlineTest

"${JAVA_HOME:+$JAVA_HOME/bin/}java" -cp build/sharp-text-tests SmallLabelITest

"${JAVA_HOME:+$JAVA_HOME/bin/}java" -cp build/sharp-text-tests PrettyPrintTest
