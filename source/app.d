/**
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */

import vibe.appmain;
import vibe.core.args;
import vibe.core.core;
import vibe.core.file;
import vibe.core.log;
import vibe.core.net;
import vibe.http.router;
import vibe.http.server;
import vibe.http.fileserver;
import vibe.data.json;
import vibe.db.redis.redis;

import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.string;
import std.typecons;

import serverinfo;
import player;
import json;
import watcher;

struct ServerConfig
{
    string name;
    string address;
    ushort port;
    string type;
    string icon;
}

struct Config
{
    ServerConfig[] servers;
    string page_title;
    uint refresh_time;
    uint recv_timeout;
}

shared static this()
{
    version(linux) {
        import etc.linux.memoryerror;
        static if (is(typeof(registerMemoryErrorHandler)))
            registerMemoryErrorHandler();
    }

    Watcher[] watchers;

    string bindAddress = "0.0.0.0";
    ushort httpPort = 27080;
    string redisHost = "127.0.0.1";
    ushort redisPort = 6379u;
    string configFileName = "config.json";
    string logFile;
    long dbIndex = 0;

    readOption("bindaddress", &bindAddress, "assign address to http server socket");
    readOption("port", &httpPort, "port to run server on");
    readOption("config", &configFileName, "path to configuration json file");
    readOption("logfile", &logFile, "path to log file");
    readOption("redishost", &redisHost, "redis server ip address");
    readOption("redisport", &redisPort, "redist server port");

    if (logFile.length) {
        setLogFile(logFile);
    }

    auto redis = new RedisClient(redisHost, redisPort);
    redis.getDatabase(dbIndex).deleteAll();

    auto configString = readFile(configFileName).assumeUnique.assumeUTF;
    auto config = deserializeJson!Config(configString);

    auto onServerInfoReceived = delegate(Watcher watcher, const ServerInfo serverInfo) {
        logTrace("%s: got server info %s", watcher.name, serverInfo);

        auto redisDb = redis.getDatabase(dbIndex);
        redisDb.set(format("%s:serverinfo", watcher.name), serverInfoToJson(serverInfo).toString());
    };

    auto onPlayersReceived = delegate(Watcher watcher, const Player[] players) {
        logTrace("%s: got players %s", watcher.name, players);

        auto redisDb = redis.getDatabase(dbIndex);
        redisDb.set(format("%s:players", watcher.name), playersToJson(players).toString());
    };

    auto onConnectionError = delegate(Watcher watcher, Exception e) {
        logError("%s: connection to server lost: %s", watcher.name, e.msg);
        auto redisDb = redis.getDatabase(dbIndex);
        redisDb.set(format("%s:ok", watcher.name), false);
    };

    auto onConnectionRestored = delegate(Watcher watcher) {
        logInfo("%s: connection restored", watcher.name);
        auto redisDb = redis.getDatabase(dbIndex);
        redisDb.set(format("%s:ok", watcher.name), true);
    };

    foreach(serverConfig; config.servers) {
        auto name = serverConfig.name;
        auto address = serverConfig.address;
        auto port = serverConfig.port;

        Watcher watcher;

        switch(serverConfig.type) {
            case "valve":
                watcher = new ValveWatcher(name, address, port);
                break;
            case "xash":
                watcher = new XashWatcher(name, address, port);
                break;
            case "quake":
                watcher = new QuakeWatcher(name, address, port);
                break;
            case "quake2":
                watcher = new Quake2Watcher(name, address, port);
                break;
            default:
                logError("Unknown server type %s", serverConfig.type);
                break;
        }

        watcher.onServerInfoReceived = onServerInfoReceived;
        watcher.onPlayersReceived = onPlayersReceived;
        watcher.onConnectionError = onConnectionError;
        watcher.onConnectionRestored = onConnectionRestored;
        watcher.icon = serverConfig.icon;

        auto redisDb = redis.getDatabase(dbIndex);
        redisDb.set(format("%s:address", name), address);
        redisDb.set(format("%s:port", name), format("%u", port));
        redisDb.set(format("%s:icon", name), format("%s", watcher.icon));
        redisDb.set(format("%s:ok", name), true);

        watchers ~= watcher;
    }

    runTask(delegate (Watcher[] watchers) {
        while(true) {
            foreach(watcher; watchers) {
                watcher.requestInfo();
            }
            sleep(dur!"msecs"(config.refresh_time));
        }
    }, watchers);

    foreach(w; watchers) {
        runTask(delegate(Watcher watcher) {
            while(true) {
                try {
                    watcher.handleResponse(dur!"msecs"(config.recv_timeout));
                } catch(Exception e) {
                    logError("%s: unknown error: %s", watcher.name, e);
                }
            }
        }, w);
    }

    auto router = new URLRouter;
    router.get("/api/servers", delegate(HTTPServerRequest req, HTTPServerResponse res) {
        auto redisDb = redis.getDatabase(dbIndex);
        Json toRespond = Json.emptyArray;
        foreach(const watcher; watchers) {
            try {
                Json j = Json.emptyObject;
                auto serverInfo = redisDb.get!string(format("%s:serverinfo", watcher.name));
                auto players = redisDb.get!string(format("%s:players", watcher.name));

                if (serverInfo !is null) {
                    if (players !is null) {
                        j["players"] = players.parseJsonString();
                    } else {
                        j["player"] = Json.emptyArray;
                    }

                    j["serverInfo"] = serverInfo.parseJsonString();
                    j["host"] = redisDb.get!string(format("%s:address", watcher.name));
                    j["port"] = redisDb.get!string(format("%s:port", watcher.name)).to!ushort;
                    j["ok"] = redisDb.get!bool(format("%s:ok", watcher.name));
                    toRespond ~= j;
                }
            } catch(Exception e) {
                logError("%s", e);
            }
        }
        res.writeJsonBody(toRespond);
    });

    static struct Server
    {
        string address;
        ushort port;
        string serverName;
        string mapName;
        string gameName;
        string iconPath;
        string steamUrl;
        ubyte playersCount;
        ubyte maxPlayersCount;
        bool isOk;
        Player[] players;
    }

    router.get("/servers", delegate(HTTPServerRequest req, HTTPServerResponse res) {
        Server[] servers;
        auto redisDb = redis.getDatabase(dbIndex);

        foreach(const watcher; watchers) {
            Server server;
            server.address = redisDb.get!string(format("%s:address", watcher.name));
            server.port = redisDb.get!string(format("%s:port", watcher.name)).to!ushort;
            server.isOk = redisDb.get!bool(format("%s:ok", watcher.name));
            auto serverInfoString = redisDb.get!string(format("%s:serverinfo", watcher.name));
            auto playersString = redisDb.get!string(format("%s:players", watcher.name));

            if (watcher.supportsSteamUrl()) {
                server.steamUrl = format("steam://connect/%s:%s", server.address, server.port);
            }

            if (serverInfoString !is null && playersString !is null) {
                auto serverInfoJson = serverInfoString.parseJsonString();
                server.serverName = serverInfoJson["serverName"].to!string;
                server.mapName = serverInfoJson["map"].to!string;
                server.playersCount = serverInfoJson["playersCount"].to!ubyte;
                server.maxPlayersCount = serverInfoJson["maxPlayersCount"].to!ubyte;
                server.players = jsonToPlayers(playersString.parseJsonString());
                server.gameName = serverInfoJson["game"].to!string;
                string gamedir = serverInfoJson["gamedir"].to!string;
                if (gamedir.length) {
                    string iconPath = format("public/icons/%s.png", watcher.icon);
                    if (existsFile(iconPath)) {
                        server.iconPath = format("icons/%s.png", watcher.icon);
                    }
                }
                servers ~= server;
            }
        }

        string pageTitle = config.page_title.length ? config.page_title : "Game servers";
        res.render!("servers.dt", servers, pageTitle);
    });

    router.get("*", serveStaticFiles("./public/"));

    auto settings = new HTTPServerSettings;
    settings.bindAddresses = [bindAddress];
    settings.port = httpPort;

    listenHTTP(settings, router);
}
