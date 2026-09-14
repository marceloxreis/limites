#!/bin/sh
# Codex hook: tells Limites that this tab needs attention.
# Stays silent and succeeds when the app is not installed, so Codex never sees an error.
helper=/Applications/Limites.app/Contents/MacOS/limites-signal
[ -x "$helper" ] && "$helper" codex
exit 0
