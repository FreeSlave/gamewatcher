# Gamewatcher
Query information from various game servers. Watch their current state via web interface or REST api.

[![Build Status](https://github.com/FreeSlave/gamewatcher/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/FreeSlave/gamewatcher/actions/workflows/ci.yml)

## Supported game servers

* Games by Valve, both GoldSource and Source based
* Xash3D servers by [FWGS](https://github.com/FWGS)
* Quake
* Quake II

## Dependencies

* D compiler, e.g. dmd
* dub
* [vibe.d](https://github.com/rejectedsoftware/vibe.d) dependencies

## How to run

```
cp config_example/config.json . # copy example config
nano config.json # edit config
dub run --build=release
xdg-open http://127.0.0.1:27080/servers # open web interface in browser
curl http://127.0.0.1:27080/api/servers | python -m json.tool # get JSON formatted info via REST api
```

## Run in docker

### Build and run in docker container:

Container will download D compiler and dub package manager and build the project by itself.
No need to install D compiler and dub on the host.

```
cp config_example/config.json . # copy example config
nano config.json # edit config
docker build -t gamewatcher .
docker run -v "$(pwd)/config.json":/opt/gamewatcher/config.json -v "$(pwd)/public":/opt/gamewatcher/public -p 27080:27080 gamewatcher
```
