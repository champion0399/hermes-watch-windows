#!/bin/bash
echo "HOME=$HOME"
for d in "$HOME/Developer"/xtool* "$HOME"/xtool*; do
  echo "dir: $d"
  find "$d" -path '*/.build/*/xtool' -type f -executable 2>/dev/null
done
echo '--- second pattern ---'
for d in "$HOME/Developer"/xtool*; do
  for cfg in release debug; do
    b="$d/.build/$cfg/xtool"
    [ -x "$b" ] && echo "found: $b"
  done
done
