# Gamewatcher
Query information from various game servers. Watch their current state via web interface or REST api.

[![Build Status](https://travis-ci.org/FreeSlave/gamewatcher.svg?branch=master)](https://travis-ci.org/FreeSlave/gamewatcher)

## Supported game servers

* Games by Valve, both GoldSource and Source based
* Xash3D servers by [FWGS](https://github.com/FWGS)
* Quake
* Quake II

## Dependencies

* D compiler, e.g. dmd
* dub
* [vibe.d](https://github.com/rejectedsoftware/vibe.d) dependcies
* redis-server

## How to run

```
cp config_example/config.json . # copy example config
nano config.json # edit config
dub build --build=release
dub run
xdg-open http://127.0.0.1:27080/servers # open web interface in browser
curl http://127.0.0.1:27080/api/servers | python -m json.tool # get JSON formatted info via REST api
```

Note: redis-server should be running.

## Run in docker

### Build and run in docker container:

Container will download D compiler and dub package manager and build the project by itself.
No need to install D compiler and dub on the host.

```
cp config_example/config.json . # copy example config
nano config.json # edit config
docker build -t gamewatcher .
docker run -p 27080:27080 gamewatcher
```

### Build on host and run in docker container:

You build the project on the host environment and it's copied to the container. 
Faster than the former method, but requires D tools on the host and produced binary file to be compatible with container environment.

```
cp config_example/config.json . # copy example config
nano config.json # edit config
dub build
docker build -t gamewatcher-local -f Dockerfile-local .
docker run -p 27080:27080 gamewatcher-local
```
