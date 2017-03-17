module utils;

import std.bitmanip;
 
ubyte readByte(ref const(ubyte)[] data)
{
    return read!ubyte(data);
}

string readStringZ(ref const(ubyte)[] data)
{
    for (size_t i=0; i<data.length; ++i) {
        if (data[i] == '\0') {
            auto toReturn = cast(const(char)[])data[0..i];
            data = data[i+1..$];
            return toReturn.idup;
        }
    }
    throw new Exception("Expected null terminated string");
}
