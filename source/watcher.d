/**
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
module watcher;
import vibe.core.log;
import vibe.core.net;

import core.time;
import std.algorithm;
import std.bitmanip;
import std.conv;
import std.format;
import std.exception;
import std.range;
import std.string;
import std.utf;

import player;
import serverinfo;
import utils;

class Watcher
{
    this(string name, string host, ushort port) {
        this.name = name;
        this.host = host;
        this.port = port;
        isOk = true;
        socket = listenUDP(0);
        socket.connect(host, port);
    }

    final void requestInfo() {
        try {
            requestInfoImpl();
        } catch(Exception e) {
            setNotOk(e);
        }
    }

    final void handleResponse(Duration timeout) {
        try {
            auto data = receive(timeout);
            handleResponseImpl(data);
            setOk();
        } catch(Exception e) {
            setNotOk(e);
        }
    }
    protected abstract void handleResponseImpl(const(ubyte)[] pack);
    protected abstract void requestInfoImpl();

    bool supportsSteamUrl() const {
        return false;
    }

    void delegate(Watcher watcher, const ServerInfo serverInfo) onServerInfoReceived;
    void delegate(Watcher watcher, const Player[] players) onPlayersReceived;
    void delegate(Watcher wathcer, Exception e) onConnectionError;
    void delegate(Watcher wathcer) onConnectionRestored;

    string name;
    string icon;
    string host;
    ushort port;

protected:
    bool isOk;

    final void send(const(ubyte)[] toSend) {
        socket.send(toSend);
    }
    final const(ubyte)[] receive(Duration timeout) {
        return socket.recv(timeout);
    }
    final void setNotOk(Exception e) {
        if (isOk) {
            isOk = false;
            if (onConnectionError) {
                onConnectionError(this, e);
            }
        }
    }
    final void setOk() {
        if (!isOk) {
            isOk = true;
            if (onConnectionRestored) {
                onConnectionRestored(this);
            }
        }
    }

    final void callOnServerInfoReceived(const ServerInfo serverInfo) {
        if (onServerInfoReceived) {
            onServerInfoReceived(this, serverInfo);
        }
    }

    final void callOnPlayersReceived(const Player[] players) {
        if (onPlayersReceived) {
            onPlayersReceived(this, players);
        }
    }
private:
    UDPConnection socket;
}

final class ValveWatcher : Watcher
{
    this(string name, string host, ushort port) {
        super(name, host, port);
        challenge = -1;
    }

    protected override void requestInfoImpl() {
        immutable playersRequest = "\xff\xff\xff\xffU".representation ~ nativeToLittleEndian!int(challenge)[].assumeUnique;
        send(playersRequest);
        immutable infoRequest = "\xff\xff\xff\xffTSource Engine Query\0".representation;
        send(infoRequest);
    }

    protected override void handleResponseImpl(const(ubyte)[] pack)
    {
        auto header = read!(int, Endian.littleEndian)(pack);
        if (header == -1) {
            ubyte payloadHeader = read!ubyte(pack);
            switch(payloadHeader) {
                case 'I':
                    callOnServerInfoReceived(parseServerInfo(pack));
                    break;
                case 'D':
                    callOnPlayersReceived(parsePlayers(pack));
                    break;
                case 'A':
                    challenge = read!(int, Endian.littleEndian)(pack);
                    setOk();
                    logTrace("%s: got challenge", name);
                    break;
                default:
                    logWarn("%s: unknown payload header: %s", name, payloadHeader);
                    break;
            }
        } else if (header == -2) {
            logWarn("%s: can't handle multiple package queries yet", name);
        } else {
            logWarn("%s: invalid response header: %s", name, header);
        }
    }

    override bool supportsSteamUrl() const {
        return true;
    }

private:
    final ServerInfo parseServerInfo(const(ubyte)[] data)
    {
        ServerInfo info;
        info.protocol = readByte(data);
        info.serverName = readStringZ(data);
        info.mapName = readStringZ(data);
        info.gamedir = readStringZ(data);
        info.game = readStringZ(data);

        info.steamAppId = read!(short, Endian.littleEndian)(data);
        info.playersCount = readByte(data);
        info.maxPlayersCount = readByte(data);
        info.botsCount = readByte(data);
        info.serverTypeC = readByte(data);
        info.environmentC = readByte(data);
        info.visibility = readByte(data);
        info.VAC = readByte(data);
        return info;
    }

    final Player[] parsePlayers(const(ubyte)[] data) {
        ubyte playerCount = read!ubyte(data);
        Player[] players;
        players.length = playerCount;
        for (int i=0; i<playerCount; ++i) {
            Player player;
            player.index = read!ubyte(data);
            player.name = readStringZ(data);
            player.score = read!(int, Endian.littleEndian)(data);
            player.duration = read!(float, Endian.littleEndian)(data);
            players[i] = player;
        }
        return players;
    }

    int challenge;
}

final class XashWatcher : Watcher
{
    this(string name, string host, ushort port) {
        super(name, host, port);
    }

    protected override void requestInfoImpl() {
        immutable playersRequest = "\xff\xff\xff\xffnetinfo 48 0 3\0".representation;
        send(playersRequest);

        immutable infoRequest = "\xff\xff\xff\xffnetinfo 48 0 4\0".representation;
        send(infoRequest);
    }

    override void handleResponseImpl(const(ubyte)[] pack)
    {
        if (pack.length && pack[$-1] == '\0') {
            pack = pack[0..$-1];
        }
        auto header = read!(int, Endian.littleEndian)(pack);
        if (header == -1) {
            string command;
            string packStr = cast(string)pack;
            if (!formattedRead(packStr, "%s ", &command)) {
                logWarn("%s: Could not match command from input: %s", name, packStr);
                return;
            }
            if (command == "netinfo") {
                int context, type;
                if (formattedRead(packStr, " %s %s", &context, &type) != 2) {
                    logWarn("%s: Could not match context and type from input: %s", name, packStr);
                }
                packStr = packStr.stripLeft;
                if (type == 3) {
                    callOnPlayersReceived(parsePlayers(packStr));
                } else if (type == 4) {
                    callOnServerInfoReceived(parseServerInfo(packStr));
                } else {
                    logWarn("%s: don't know how to handle response of type %s", type);
                }
            }
        } else {
            logWarn("%s: invalid response header: %s", name, header);
        }
    }

private:
    final ServerInfo parseServerInfo(string packStr)
    {
        ServerInfo serverInfo;
        foreach(pair; packStr.chomp().split('\\').drop(1).chunks(2)) {
            try {
                auto key = pair.front;
                enforce(!pair.empty);
                pair.popFront();
                auto value = pair.front;
                enforce(!pair.empty);
                pair.popFront();
                switch(key) {
                    case "hostname":
                        serverInfo.serverName = value;
                        break;
                    case "gamedir":
                        serverInfo.gamedir = value;
                        break;
                    case "current":
                        serverInfo.playersCount = value.to!ubyte;
                        break;
                    case "max":
                        serverInfo.maxPlayersCount = value.to!ubyte;
                        break;
                    case "map":
                        serverInfo.mapName = value;
                        break;
                    default:
                        break;
                }
            } catch(Exception e) {
                logError("%s: error: %s", name, e.msg);
            }
        }
        serverInfo.game = "Half-Life";
        serverInfo.serverTypeC = ' ';
        serverInfo.environmentC = ' ';
        return serverInfo;
    }
    final Player[] parsePlayers(string packStr)
    {
        Player[] players;
        try {
            auto splitted = packStr.chomp().splitter('\\').filter!(s => !s.empty).array;
            auto playerChunks = splitted.chunks(4);
            foreach(playerChunk; playerChunks) {
                try {
                    Player player;

                    enforce(!playerChunk.empty, "empty index");
                    if (playerChunk.front.length == 1 && playerChunk.front[0] < 32) {
                        // support versions before this fix https://github.com/FWGS/xash3d/commit/83868b1cad7df74998ebf2d958de222731241627
                        player.index = cast(ubyte)playerChunk.front[0];
                    } else {
                        player.index = playerChunk.front.to!ubyte;
                    }
                    playerChunk.popFront();

                    enforce(!playerChunk.empty, "empty name");
                    player.name = playerChunk.front;
                    playerChunk.popFront();

                    enforce(!playerChunk.empty, "empty score");
                    player.score = playerChunk.front.to!int;
                    playerChunk.popFront();

                    enforce(!playerChunk.empty, "empty duration");
                    player.duration = playerChunk.front.to!float;
                    playerChunk.popFront();

                    players ~= player;
                } catch(Exception e) {
                    logError("%s: player parse error: %s. playerChunk: %s", name, e.msg, playerChunk);
                }
            }
        } catch(Exception e) {
            logError("%s: players parse error: %s", name, e.msg);
        }

        return players;
    }
}

final class QuakeWatcher : Watcher
{
    this(string name, string host, ushort port) {
        super(name, host, port);
    }

    protected override void requestInfoImpl() {
        immutable infoRequest = "\xff\xff\xff\xffstatus\0".representation;
        send(infoRequest);
    }

    protected override void handleResponseImpl(const(ubyte)[] pack)
    {
        if (pack.length && pack[$-1] == '\0') {
            pack = pack[0..$-1];
        }
        auto header = read!(int, Endian.littleEndian)(pack);
        if (header == -1) {
            auto payloadHeader = read!(ubyte)(pack);
            if (payloadHeader == 'n') {
                auto lines = pack.split('\n').map!(line => cast(string)line);
                if (!lines.empty) {
                    auto kvList = lines.front.splitter('\\').map!(s => cast(string)s);
                    if (!kvList.empty && kvList.front.empty) {
                        kvList.popFront();
                    }
                    ServerInfo serverInfo;
                    serverInfo.game = "Quake";
                    serverInfo.gamedir = "baseq";
                    serverInfo.serverTypeC = ' ';
                    serverInfo.environmentC = ' ';

                    while(!kvList.empty) {
                        auto key = kvList.front;
                        kvList.popFront();
                        if (!kvList.empty) {
                            auto value = kvList.front;
                            kvList.popFront();

                            switch(key)
                            {
                                case "maxclients":
                                    serverInfo.maxPlayersCount = value.to!ubyte;
                                    break;
                                case "map":
                                    serverInfo.mapName = value;
                                    break;
                                case "hostname":
                                    serverInfo.serverName = value;
                                    break;
                                case "*gamedir":
                                    serverInfo.gamedir = value;
                                    break;
                                default:
                                    break;
                            }
                        }
                    }
                    lines.popFront();

                    Player[] players;
                    foreach(line; lines) {
                        if (line.empty) {
                            continue;
                        }
                        Player player;
                        uint ping;
                        string skin;
                        uint color1, color2;
                        try {
                            auto byUnit = line.byCodeUnit;
                            string name;
                            formattedRead(byUnit, "%s %s %s %s \"%s\" \"%s\" %s %s",
                                &player.index, &player.score, &player.duration, &ping, &name, &skin, &color1, &color2);
                            player.name = name;
                            players ~= player;
                        } catch(Exception e) {
                            logError("%s: player parse error: %s. line : %s", line);
                        }
                    }

                    serverInfo.playersCount = cast(ubyte)players.length;
                    callOnServerInfoReceived(serverInfo);
                    callOnPlayersReceived(players);
                }
            } else {
                logWarn("%s: unknown payload header: %s", name, payloadHeader);
            }
        } else {
            logWarn("%s: invalid response header: %s", name, header);
        }
    }
}

final class Quake2Watcher : Watcher
{
    this(string name, string host, ushort port) {
        super(name, host, port);
    }

    protected override void requestInfoImpl() {
        immutable infoRequest = "\xff\xff\xff\xffstatus\0".representation;
        send(infoRequest);
    }

    protected override void handleResponseImpl(const(ubyte)[] pack)
    {
        if (pack.length && pack[$-1] == '\0') {
            pack = pack[0..$-1];
        }
        auto header = read!(int, Endian.littleEndian)(pack);
        if (header == -1) {
            auto lines = pack.split('\n').map!(line => cast(string)line);
            if (!lines.empty && lines.front == "print") {
                lines.popFront();
            } else {
                return;
            }

            if (!lines.empty) {
                auto kvList = lines.front.splitter('\\').map!(s => cast(string)s);
                if (!kvList.empty && kvList.front.empty) {
                    kvList.popFront();
                }
                ServerInfo serverInfo;
                serverInfo.game = "Quake II";
                serverInfo.gamedir = "baseq2";
                serverInfo.serverTypeC = ' ';
                serverInfo.environmentC = ' ';

                while(!kvList.empty) {
                    auto key = kvList.front;
                    kvList.popFront();
                    if (!kvList.empty) {
                        auto value = kvList.front;
                        kvList.popFront();

                        switch(key)
                        {
                            case "maxclients":
                                serverInfo.maxPlayersCount = value.to!ubyte;
                                break;
                            case "mapname":
                                serverInfo.mapName = value;
                                break;
                            case "hostname":
                                serverInfo.serverName = value;
                                break;
                            case "gamename":
                                serverInfo.gamedir = value;
                                break;
                            default:
                                break;
                        }
                    }
                }
                lines.popFront();

                Player[] players;
                ubyte i = 0;
                foreach(line; lines) {
                    if (line.empty) {
                        continue;
                    }
                    Player player;
                    player.index = i++;
                    player.duration = 0;
                    uint ping;
                    try {
                        auto byUnit = line.byCodeUnit;
                        string name;
                        formattedRead(byUnit, "%s %s \"%s\"", &player.score, &ping, &name);
                        player.name = name;
                        players ~= player;
                    } catch(Exception e) {
                        logError("%s: player parse error: %s. line : %s", line);
                    }
                }

                serverInfo.playersCount = cast(ubyte)players.length;
                callOnServerInfoReceived(serverInfo);
                callOnPlayersReceived(players);
            }
        } else {
            logWarn("%s: invalid response header: %s", name, header);
        }
    }
}
