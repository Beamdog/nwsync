import options, logging, critbits, std/sha1, strutils, sequtils,
  os, ospaths, algorithm, math, times, json, sets, tables

import neverwinter/erf, neverwinter/resfile, neverwinter/resdir,
  neverwinter/gff, neverwinter/resman, neverwinter/key

import manifest
import libshared

let GobalResTypeSkipList = [getResType("nss")]

proc allowedToExpose(it: ResRef): bool =
  not GobalResTypeSkipList.contains(it.resType)

proc reindex*(rootDirectory: string,
    entries: seq[string],
    forceWriteIfExists: bool,
    description: string,
    withModuleContents: bool): string =
  ## Reindexes the given module.

  if not dirExists(rootDirectory):
    abort "Target sync directory does not exist."

  if fileExists(rootDirectory / "latest"):
    info "Directory already has `latest` manifest, that's OK. Updating!"

  createDir(rootDirectory / "manifests")
  createDir(rootDirectory / "data")
  createDir(rootDirectory / "data" / "sha1")

  info "Reindexing"
  let resman = newResMan(entries, withModuleContents)

  info "Preparing data set to expose"
  let entriesToExpose = toSeq(resman.contents.items).filterIt(allowedToExpose(it))

  let totalfiles = entriesToExpose.len

  if totalfiles == 0:
    raise newException(ValueError, "You gave me no files to index (nothing contained)")

  var moduleName = ""
  let ifo = resman["module.ifo"]
  if ifo.isSome:
    let rr = ifo.get()
    rr.seek()
    let g = readGffRoot(rr.io(), false)
    let nm = g["Mod_Name", GffCExoLocString].entries
    if nm.hasKey(0):
      moduleName = nm[0]
      info "Module name: ", moduleName

  info "Reading existing data in storage"
  var writtenHashes = getFilesInStorage(rootDirectory)

  info "Calculating complete manifest size"
  let totalbytes = entriesToExpose.mapIt(resman[it].get().len).sum()
  info "Generating data for ", totalfiles, " resrefs, ",
    formatSize(totalbytes), " (This might take a while, we need to checksum it all)"

  let manifest = newManifest()

  var dedupbytes = 0

  for idx, resRef in entriesToExpose:
    let res = resman[resRef].get()
    let size = res.len

    let data = res.readAll(useCache=false)
    let sha1 = secureHash(data)
    let sha1str = toLowerAscii($sha1)

    manifest.entries.add ManifestEntry(sha1: sha1str, size: uint32 size, resref: resRef)

    let alreadyWrittenOut = writtenHashes.contains(sha1str)

    if alreadyWrittenOut:
      dedupbytes += size
      debug "Exists: ", sha1str, " (", $resRef, ")"

    else:
      # Not in storage yet, write it to disk.
      var path = rootDirectory / "data" / "sha1"
      for i in 0..<manifest.hashTreeDepth:
        let pfx = sha1str[i*2..<(i*2+2)]
        path = path / pfx
        createDir path

      path = path / sha1str
      let percent = idx div (entriesToExpose.len div 100)
      info "[", percent, "%] Writing: ", path, " (", $resRef, ")"
      writeFile(path, data)

  doAssert(manifest.entries.len == totalfiles)

  info "Writing new binary manifest"
  let strim = newStringStream()
  writeManifest(strim, manifest)
  strim.setPosition(0)
  let newManifestData = strim.readAll()
  let newManifestSha1 = toLowerAscii($secureHash(newManifestData))

  if fileExists(rootDirectory / "latest"):
    info "Updating `latest` to point to ", newManifestSha1
  writefile(rootDirectory / "latest", newManifestSha1)
  writeFile(rootDirectory / "manifests" / newManifestSha1, newManifestData)

  let retInfo = pretty(%*{
      "version": %int manifest.version,
      "sha1": %newManifestSha1,
      "hash_tree_depth": %int manifest.hashTreeDepth,
      "description": description,
      "module_name": moduleName,
      "includes_module_contents": withModuleContents,
      "total_files": totalfiles,
      "total_bytes": totalbytes,
      "created": %int epochTime()
    }) & "\c\L"

  writeFile(rootDirectory / "manifests" / newManifestSha1 & ".json", retinfo)

  info "Reindex done, manifest version ", manifest.version, " written: ", newManifestSha1
  info "Manifest contains ", formatsize(totalbytes), " in ", totalfiles, " files"
  info "We wrote ", formatSize(totalbytes - dedupbytes), " of new data"

  result = retinfo
