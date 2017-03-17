/**
 * Authors: 
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
import vibe.core.log;
import vibe.core.net;

import core.time;
import std.bitmanip;
import std.conv;
import std.format;
import std.exception;
import std.range;
import std.string;

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
    
    abstract void requestPlayers();
    abstract void requestServerInfo();
    abstract void handleResponse(Duration timeout);
    
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
        setOk();
        if (onServerInfoReceived) {
            onServerInfoReceived(this, serverInfo);
        }
    }
    
    final void callOnPlayersReceived(const Player[] players) {
        setOk();
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
    
    override void requestPlayers()
    {
        immutable playersRequest = "\xff\xff\xff\xffU".representation ~ nativeToLittleEndian!int(challenge)[].assumeUnique;
        send(playersRequest);
    }
    
    override void requestServerInfo()
    {
        immutable infoRequest = "\xff\xff\xff\xffTSource Engine Query\0".representation;
        send(infoRequest);
    }
    
    override void handleResponse(Duration timeout)
    {
        const(ubyte)[] pack; 
        try {
            pack = receive(timeout);
        } catch(Exception e) {
            setNotOk(e);
            return;
        }
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
        for (int i=0; i<playerCount; ++i) {
            Player player;
            player.index = read!ubyte(data);
            player.name = readStringZ(data);
            player.score = read!(int, Endian.littleEndian)(data);
            player.duration = read!(float, Endian.littleEndian)(data);
            players ~= player;
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
    
    override void requestPlayers()
    {
        immutable playersRequest = "\xff\xff\xff\xffnetinfo 48 0 3\0".representation;
        socket.send(playersRequest);
    }
    
    override void requestServerInfo()
    {
        immutable infoRequest = "\xff\xff\xff\xffnetinfo 48 0 4\0".representation;
        socket.send(infoRequest);
    }
    
    override void handleResponse(Duration timeout)
    {
        const(ubyte)[] pack; 
        try {
            pack = receive(timeout);
        } catch(Exception e) {
            setNotOk(e);
            return;
        }
        
        auto header = read!(int, Endian.littleEndian)(pack);
        if (header == -1) {
            string command;
            string packStr = cast(string)pack;
            formattedRead(packStr, "%s ", &command);
            if (command == "netinfo") {
                int context, type;
                formattedRead(packStr, " %s %s", &context, &type);
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
            auto playerChunks = packStr.chomp().split('\\').dropBack(1).chunks(4);
            foreach(playerChunk; playerChunks) {
                try {
                    Player player;
                    
                    enforce(!playerChunk.empty);
                    if (playerChunk.front.length == 1 && playerChunk.front[0] < '0') {
                        // support versions before this fix https://github.com/FWGS/xash3d/commit/83868b1cad7df74998ebf2d958de222731241627
                        player.index = cast(ubyte)playerChunk.front[0];
                    } else {
                        player.index = playerChunk.front.to!ubyte;
                    }
                    playerChunk.popFront();
                    
                    enforce(!playerChunk.empty);
                    player.name = playerChunk.front;
                    playerChunk.popFront();
                    
                    enforce(!playerChunk.empty);
                    player.score = playerChunk.front.to!int;
                    playerChunk.popFront();
                    
                    enforce(!playerChunk.empty);
                    player.duration = playerChunk.front.to!float;
                    playerChunk.popFront();
                    
                    players ~= player;
                } catch(Exception e) {
                    logError("%s: player parse error: %s", name, e.msg);
                }
            }
        } catch(Exception e) {
            logError("%s: players parse error: %s", name, e.msg);
        }
        
        return players;
    }
}
