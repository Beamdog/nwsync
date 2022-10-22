import sequtils, ospaths, strutils

version       = "0.4.3"
author        = "Bernhard Stöckner <niv@beamdog.com>"
description   = "NWSync Repository Management utilities"
license       = "MIT"

requires "nim >= 1.6.0"
requires "neverwinter >= 1.5.7"
requires "docopt >= 0.6.8"

skipExt = @["nim"]
binDir = "bin"
bin = listFiles(thisDir()).
  mapIt(it.extractFilename()).
  filterIt(it.startsWith("nwsync_") and it.endsWith(".nim")).
  mapIt(it.splitFile.name)

task clean, "Remove compiled binaries and temporary data":
  for b in bin: rmFile(binDir / b)
  for b in bin: rmFile(binDir / b & ".exe")
