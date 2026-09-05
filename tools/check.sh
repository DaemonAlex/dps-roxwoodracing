#!/usr/bin/env bash
# Syntax-check every Lua file, then run unit tests. Run from repo root on the fivem VM.
set -e
fail=0
while IFS= read -r f; do
  if ! luac5.4 -p "$f" 2>/tmp/luac.err; then echo "SYNTAX $f: $(cat /tmp/luac.err)"; fail=1; fi
done < <(find . -name '*.lua' -not -path './.git/*')
[ $fail -eq 0 ] || exit 1
echo "syntax ok"
lua5.4 tests/run.lua
