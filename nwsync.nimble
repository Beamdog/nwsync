import sequtils, ospaths, strutils

version       = "0.2.4"
author        = "Bernhard Stöckner <niv@beamdog.com>"
description   = "NWSync Repository Management utilities"
license       = "MIT"

requires "nim >= 0.20.2"
requires "zip >= 0.2.1"
requires "neverwinter >= 1.2.7"

skipExt = @["nim"]
binDir = "bin"
bin = listFiles(thisDir()).
  mapIt(it.extractFilename()).
  filterIt(it.startsWith("nwsync_") and it.endsWith(".nim")).
  mapIt(it.splitFile.name)

task clean, "Remove compiled binaries and temporary data":
  for b in bin: rmFile(binDir / b)
  for b in bin: rmFile(binDir / b & ".exe")
