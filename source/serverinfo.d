/**
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
module serverinfo;

import std.exception;
import std.bitmanip;

struct ServerInfo
{
    enum Type : ubyte {
        Unknown,
        Dedicated,
        NonDedicated,
        SourceTV
    }

    enum OS : ubyte {
        Unknown,
        Linux,
        Windows,
        OSX
    }

    string serverName;
    string mapName;
    string gamedir;
    string game;

    short steamAppId;
    ubyte protocol;
    ubyte playersCount;
    ubyte maxPlayersCount;
    ubyte botsCount;
    Type serverType;
    OS environment;
    bool requiresPassword;
    bool isSecured;
}
