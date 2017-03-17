/**
 * Authors: 
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 */
module player;

import std.exception;
import std.bitmanip;

struct Player
{
    ubyte index;
    string name;
    int score;
    float duration;
}
