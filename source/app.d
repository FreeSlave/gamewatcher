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

import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.path;
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

class Server
{
    this(Watcher myWatcher) {
        watcher = myWatcher;
    }
    Watcher watcher;
    ServerInfo info;
    const(Player)[] players;
    string icon;
    string iconPath;

    @property string address() const {
        return watcher.host;
    }
    @property ushort port() {
        return watcher.port;
    }
}

Watcher createWatcher(string type, string name, string address, ushort port)
{
    switch(type) {
        case "valve":
            return new ValveWatcher(name, address, port);
        case "xash":
            return new XashWatcher(name, address, port);
        case "quake":
            return new QuakeWatcher(name, address, port);
        case "quake2":
            return new Quake2Watcher(name, address, port);
        default:
            return null;
    }
}

shared static this()
{
    version(linux) {
        import etc.linux.memoryerror;
        static if (is(typeof(registerMemoryErrorHandler)))
            registerMemoryErrorHandler();
    }

    Server[] servers;

    string bindAddress = "0.0.0.0";
    ushort httpPort = 27080;
    string configFileName = "config.json";
    string logFile;
    long dbIndex = 0;

    readOption("bindaddress", &bindAddress, "assign address to http server socket");
    readOption("port", &httpPort, "port to run server on");
    readOption("config", &configFileName, "path to configuration json file");
    readOption("logfile", &logFile, "path to log file");

    if (logFile.length) {
        setLogFile(logFile);
    }

    Server* findServerByName(string name) {
        auto foundServer = find!((a,b) => a.watcher.name == b)(servers, name);
        if (!foundServer.empty) {
            return &foundServer.front;
        } else {
            return null;
        }
    }

    auto onServerInfoReceived = delegate(Watcher watcher, const ServerInfo serverInfo) {
        logTrace("%s: got server info %s", watcher.name, serverInfo);
        auto foundServer = findServerByName(watcher.name);
        if (foundServer) {
            foundServer.info = serverInfo;
        } else {
            logWarn("%s: could not find server when getting server info", watcher.name);
        }
    };

    auto onPlayersReceived = delegate(Watcher watcher, const Player[] players) {
        logTrace("%s: got players %s", watcher.name, players);
        auto foundServer = findServerByName(watcher.name);
        if (foundServer) {
            foundServer.players = players;
        } else {
            logWarn("%s: could not find server when getting players", watcher.name);
        }
    };

    auto onConnectionError = delegate(Watcher watcher, Exception e) {
        logError("%s: connection to server lost: %s", watcher.name, e.msg);
    };

    auto onConnectionRestored = delegate(Watcher watcher) {
        logInfo("%s: connection restored", watcher.name);
    };

    auto readConfig(string configFileName) {
        auto configString = readFile(configFileName).assumeUnique.assumeUTF;
        return deserializeJson!Config(configString);
    }

    auto prepareServers(ref const Config config) {
        Server[] servers;
        foreach(serverConfig; config.servers) {
            auto watcher = createWatcher(serverConfig.type, serverConfig.name, serverConfig.address, serverConfig.port);
            if (!watcher) {
                logError("Unknown server type %s", serverConfig.type);
                continue;
            }

            watcher.onServerInfoReceived = onServerInfoReceived;
            watcher.onPlayersReceived = onPlayersReceived;
            watcher.onConnectionError = onConnectionError;
            watcher.onConnectionRestored = onConnectionRestored;

            auto server = new Server(watcher);
            server.icon = serverConfig.icon;
            servers ~= server;
        }
        return servers;
    }

    auto config = readConfig(configFileName);
    servers = prepareServers(config);

    auto startServerTasks(Server[] servers) {
        foreach(server; servers) {
            runTask(delegate(Server server) {
                while(server.watcher !is null) {
                    try {
                        server.watcher.handleResponse(dur!"msecs"(config.recv_timeout));
                    } catch(Exception e) {
                        logError("%s: unknown error: %s", server.watcher.name, e);
                    }
                }
            }, server);
        }
    }

    runTask(delegate() {
        auto baseConfigFileName = baseName(configFileName);
        auto directoryWatcher = watchDirectory(dirName(configFileName), false);
        DirectoryChange[] changes;
        while(true) {
            directoryWatcher.readChanges(changes, dur!"seconds"(-1));
            foreach(change; changes) {
                if ((change.type == DirectoryChangeType.modified || change.type == DirectoryChangeType.added) && change.path.head.name == baseConfigFileName) {
                    logWarn("%s changed", configFileName);
                    try {
                        auto newConfig = readConfig(configFileName);
                        auto newServers = prepareServers(newConfig);
                        config = newConfig;
                        foreach(newServer; newServers) {
                            auto server = findServerByName(newServer.watcher.name);
                            if (server) {
                                newServer.info = server.info;
                                newServer.players = server.players;
                            }
                        }
                        foreach(server; servers) {
                            server.watcher = null;
                        }
                        servers = newServers;
                        startServerTasks(servers);
                    } catch(Exception e) {
                        logError("Could not parse config changes: %s", e.msg);
                    }
                }
            }
        }
    });

    runTask(delegate () {
        while(true) {
            foreach(server; servers) {
                server.watcher.requestInfo();
            }
            sleep(dur!"msecs"(config.refresh_time));
        }
    });

    startServerTasks(servers);

    auto router = new URLRouter;
    router.get("/api/servers", delegate(HTTPServerRequest req, HTTPServerResponse res) {
        Json toRespond = Json.emptyArray;
        foreach(const server; servers) {
            try {
                Json j = Json.emptyObject;
                j["serverInfo"] = serverInfoToJson(server.info);
                j["players"] = playersToJson(server.players);
                j["host"] = server.watcher.host;
                j["port"] = server.watcher.port;
                j["ok"] = server.watcher.isOk;
                toRespond ~= j;
            } catch(Exception e) {
                logError("%s", e);
            }
        }
        res.writeJsonBody(toRespond);
    });

    router.get("/servers", delegate(HTTPServerRequest req, HTTPServerResponse res) {
        foreach(ref server; servers) {
            if (!server.icon.length || server.iconPath.length) {
                continue;
            }
            string iconPath = format("public/icons/%s.png", server.icon);
            if (existsFile(iconPath)) {
                server.iconPath = format("icons/%s.png", server.icon);
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
