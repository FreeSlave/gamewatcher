/**
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
module json;
import vibe.data.json;

import serverinfo;
import player;

Json serverInfoToJson(const ServerInfo info)
{
    Json j = Json.emptyObject;
    j["serverName"] = info.serverName;
    j["game"] = info.game;
    j["gamedir"] = info.gamedir;
    j["map"] = info.mapName;
    j["requiresPassword"] = info.requiresPassword();
    j["isSecured"] = info.isSecured();
    string type;
    final switch(info.serverType) {
        case ServerInfo.Type.Dedicated:
            type = "dedicated";
            break;
        case ServerInfo.Type.NonDedicated:
            type = "non-dedicated";
            break;
        case ServerInfo.Type.SourceTV:
            type = "sourceTV";
            break;
        case ServerInfo.Type.Unknown:
            type = "unknown";
            break;
    }
    j["serverType"] = type;
    string os;
    final switch(info.environment()) {
        case ServerInfo.OS.Linux:
            os = "linux";
            break;
        case ServerInfo.OS.Windows:
            os = "windows";
            break;
        case ServerInfo.OS.OSX:
            os = "osx";
            break;
        case ServerInfo.OS.Unknown:
            os = "unknown";
            break;
    }
    j["environment"] = os;
    j["playersCount"] = info.playersCount;
    j["maxPlayersCount"] = info.maxPlayersCount;
    return j;
}

Json playersToJson(const(Player[]) players)
{
    return serializeToJson(players);
}
