# Gamewatcher
Query information from various game servers. Watch their current state via web interface or REST api.
[![Build Status](https://travis-ci.org/FreeSlave/gamewatcher.svg?branch=master)](https://travis-ci.org/FreeSlave/gamewatcher)

## Supported game servers

* Games by Valve, both GoldSource and Source based
* Xash3D servers by [FWGS](https://github.com/FWGS)

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

## Run in docker

```
cp config_example/config.json . # copy example config
nano config.json # edit config
dub build --build=release
sudo docker build -t gamewatcher .
sudo docker run gamewatcher -p 27080:27080
```

Note: redis-server is automatically installed and started in docker container.
