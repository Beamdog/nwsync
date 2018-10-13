#!/bin/bash

binaries="update prune"

set -e

# mac
echo "Building: mac"
rm -v macos.zip || true
for bin in $binaries; do
  echo "  Building: " $bin
  nim c -d:release $bin
  zip -vr9 macos.zip $bin
  rm -v $bin
done

# linux
echo "Building: linux"
rm -v linux.zip || true
for bin in $binaries; do
  echo "  Building: " $bin
  docker run --rm -it -v `pwd`:/pwd -w /pwd nimlang/nim:latest \
    nim c -d:release $bin
  zip -vr9 linux.zip $bin
  rm -v $bin
done

# windows
echo "Building: windows"
rm -v windows.zip || true
for bin in $binaries; do
  echo "  Building: " $bin
  WINEPREFIX=`pwd`/wine wine \
    nim c -d:release $bin
  zip -vr9 windows.zip "${bin}.exe"
  rm -v "${bin}.exe"
done
