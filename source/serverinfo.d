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
    char serverTypeC;
    char environmentC;
    ubyte visibility;
    ubyte VAC;
    
    bool requiresPassword() const {
        return visibility != 0;
    }
    bool isSecured() const {
        return VAC != 0;
    }
    
    Type serverType() const {
        switch (serverTypeC) {
            case 'd':
                return Type.Dedicated;
            case 'l':
                return Type.NonDedicated;
            case 'p':
                return Type.SourceTV;
            default:
                return Type.Unknown;
        }
    }
    
    OS environment() const {
        switch(environmentC) {
            case 'l':
                return OS.Linux;
            case 'w':
                return OS.Windows;
            case 'm':
            case 'o':
                return OS.OSX;
            default:
                return OS.Unknown;
        }
    }
}
