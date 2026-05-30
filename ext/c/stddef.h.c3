// stddef.h.c3

module c::stddef;

alias Size = sz;
alias SSize = sz;

alias UIntPtr = uptr;
alias PtrDiff = sz;
alias WChar = uint;

alias UInt8 = char;
alias UInt16 = ushort;
alias UInt32 = uint;
alias UInt64 = ulong;

alias Int8 = ichar;
alias Int16 = short;
alias Int32 = int;
alias Int64 = long;

macro sz @offsetof($Type, #field)
{
    $Type* t = null;
    return (sz)(iptr)&t.#field;
}