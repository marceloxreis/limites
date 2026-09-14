#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed, swift-testing lives
# outside the default search paths, so they are passed explicitly.
set -euo pipefail
cd "${0:A:h}/.."

tools=/Library/Developer/CommandLineTools/Library/Developer
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* && -d $tools/Frameworks/Testing.framework ]]; then
  swift test \
    -Xswiftc -F -Xswiftc $tools/Frameworks \
    -Xlinker -F -Xlinker $tools/Frameworks \
    -Xlinker -rpath -Xlinker $tools/Frameworks \
    -Xlinker -rpath -Xlinker $tools/usr/lib "$@"
else
  swift test "$@"
fi
