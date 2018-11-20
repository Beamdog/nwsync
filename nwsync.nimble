import sequtils, ospaths, strutils

version       = "0.2.1"
author        = "Bernhard Stöckner <niv@beamdog.com>"
description   = "NWSync Repository Management utilities"
license       = "MIT"

requires "nim >= 0.18.0"
requires "zip >= 0.2.1"
requires "neverwinter >= 1.2.0"

skipExt = @["nim"]
binDir = "bin"
bin = @["update", "prune", "print"]

task clean, "Remove compiled binaries and temporary data":
  for b in bin: rmFile(binDir / b)
  for b in bin: rmFile(binDir / b & ".exe")
