# NWSync Serverside Utilities

This repository contains the full source code for all the utilities needed to create and maintain a serverside NWSync repository.

NWSync is a mechanism for Neverwinter Nights: Enhanced Edition, with which game server owners can send down content data to connecting clients without them having to manually download and manage files.

This is the first iteration, which only supports persistent worlds and has some important caveats.

## Downloads/Prebuilt Binaries

To download the most recent release, click "Releases" and find the newest corresponding to the game version you run.

### Building manually

To build these tools, first install the most recent nim compiler. The suggested way to this is via choosenim: https://github.com/dom96/choosenim

After nim is installed and available on your path, simply clone this repository and type `nimble build -d:release`.

## Documentation

There is a technical user manual available at https://docs.google.com/document/d/1eYRTd6vzk7OrLpr2zlwnUk7mgUsyiZzLoR6k54njBVI.
