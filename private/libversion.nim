import parsecfg, streams, strutils

const licenceFile = slurp("../LICENCE")
const nimbleFile = slurp("../nwsync.nimble")
const buildGitHash = staticExec("git rev-parse --short HEAD")

let cfg = loadConfig(newStringStream(nimbleFile), "nwsync.nimble")

proc getGitHash(): string = buildGitHash

proc getVersion(): string = getSectionValue(cfg, "", "version").strip()

proc getLicenceText(): string = licenceFile.strip()

proc handleVersion*() =
  echo getVersion(), ", git: ", getGitHash()
  echo ""
  echo getLicenceText()
  quit()
