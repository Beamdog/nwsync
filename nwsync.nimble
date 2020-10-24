import sequtils, ospaths, strutils

version       = "0.3.0"
author        = "Bernhard Stöckner <niv@beamdog.com>"
description   = "NWSync Repository Management utilities"
license       = "MIT"

requires "nim >= 1.0.8"
requires "neverwinter >= 1.3.0"

skipExt = @["nim"]
binDir = "bin"
bin = listFiles(thisDir()).
  mapIt(it.extractFilename()).
  filterIt(it.startsWith("nwsync_") and it.endsWith(".nim")).
  mapIt(it.splitFile.name)

task clean, "Remove compiled binaries and temporary data":
  for b in bin: rmFile(binDir / b)
  for b in bin: rmFile(binDir / b & ".exe")
