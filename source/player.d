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
    @safe @property string name() const nothrow pure {
        return _name;
    }
    @trusted @property string name(string n) nothrow {
        import std.utf;
        import std.typecons;
        try {
            validate(n);
            _name = n;
        } catch(Exception e) {
            dstring result;
            size_t index = 0;
            while(index != n.length) {
                result ~= decode!(Yes.useReplacementDchar)(n, index);
            }
            _name = result.toUTF8;
        }
        return _name;
    }
    int score;
    float duration;
private:
    string _name;
}
