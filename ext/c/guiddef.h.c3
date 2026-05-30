//  guiddef.h.c3 

module c::guiddef @if(env::WIN32);

// ============================================================
// GUID
// ============================================================
//   typedef struct _GUID {
//       unsigned long  Data1;
//       unsigned short Data2;
//       unsigned short Data3;
//       unsigned char  Data4[8];
//   } GUID;

struct Guid @cname("GUID") {
    uint  data1;
    ushort data2;
    ushort data3;
    char[8] data4;
}


alias Iid     = Guid;
alias Clsid   = Guid;
alias Fmtid   = Guid;

alias RefGuid   = Guid*;
alias RefIid    = Guid*;
alias RefClsid  = Guid*;
alias RefFmtid  = Guid*;

// pointer aliases
alias PIid    = Guid*;
alias LPIid   = Guid*;
alias PClsid  = Guid*;
alias LPClsid = Guid*;

// ============================================================
// GUID_NULL
// ============================================================

const Guid GUID_NULL = { 0, 0, 0, { 0, 0, 0, 0, 0, 0, 0, 0 } };

fn bool isEqualGUID(Guid* r1, Guid* r2) @inline 
{
    if (r1.data1 != r2.data1) return false;
    if (r1.data2 != r2.data2) return false;
    if (r1.data3 != r2.data3) return false;
    for (sz i = 0; i < 8; i++) {
        if (r1.data4[i] != r2.data4[i]) {
            return false;
        }
    }
    return true;
}

fn bool isEqualIID(Guid* riid1, Guid* riid2) @inline {
    return isEqualGUID(riid1, riid2);
}

fn bool isEqualCLSID(Guid* rclsid1, Guid* rclsid2) @inline {
    return isEqualGUID(rclsid1, rclsid2);
}

fn bool isEqualFMTID(Guid* rfmtid1, Guid* rfmtid2) @inline {
    return isEqualGUID(rfmtid1, rfmtid2);
}


fn bool inlineIsEqualGUID(Guid* rguid1, Guid* rguid2) @inline {
    uint* a = (uint*)rguid1;
    uint* b = (uint*)rguid2;
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];
}

