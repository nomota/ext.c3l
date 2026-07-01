// ws_handshake.c3

// WebSocket HTTP upgrade handshake.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import std::hash::sha1;
import std::encoding::base64;
import ext::mem;


// Faults

faultdef WS_BAD_HANDSHAKE;
faultdef WS_UNSUPPORTED_VERSION;
faultdef WS_INVALID_KEY;


// Constants

const String WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const String WS_VERSION = "13";


// Header helpers


fn sz ws_header_count(Request* req, String name) @local
{
    if (req == null) return 0;

    sz count = 0;

    for (sz i = 0; i < req.headers.items.len(); i++) {
        Header* header = &req.headers.items[i];

        if (str_iequals(header.name, name)) {
            count++;
        }
    }

    return count;
}


// WebSocket key validation

fn bool ws_key_valid(String key) @local
{
    key = key.trim();

    if (key.len == 0) return false;

    char[]? decoded = base64::decode(localmem, (char[])key);
    if (catch decoded) return false;
    defer localmem.free(decoded);

    return decoded.len == 16;
}


// Request validation

fn bool Request.is_websocket_upgrade(&self)
{
    if (self.method != "GET") return false;
    if (!self.is_http_11()) return false;

    String upgrade = self.header("Upgrade") ?? "";
    String connection = self.header("Connection") ?? "";

    if (!header_has_token(upgrade, "websocket")) return false;
    if (!header_has_token(connection, "Upgrade")) return false;

    return true;
}

fn void? Request.validate_websocket_upgrade(&self)
{
    if (!self.is_websocket_upgrade()) return WS_BAD_HANDSHAKE~;

    if (ws_header_count(self, "Sec-WebSocket-Version") != 1) {
        return WS_BAD_HANDSHAKE~;
    }

    String version = self.header("Sec-WebSocket-Version") ?? "";

    if (version.trim() != WS_VERSION) {
        return WS_UNSUPPORTED_VERSION~;
    }

    if (ws_header_count(self, "Sec-WebSocket-Key") != 1) {
        return WS_INVALID_KEY~;
    }

    String key = self.header("Sec-WebSocket-Key") ?? "";

    if (!ws_key_valid(key)) {
        return WS_INVALID_KEY~;
    }
}

fn String? Request.websocket_key(&self)
{
    self.validate_websocket_upgrade()!;

    String key = self.header("Sec-WebSocket-Key") ?? "";
    return key.trim();
}


// Accept key

fn String? ws_accept_key(String key)
{
    key = key.trim();

    if (!ws_key_valid(key)) return WS_INVALID_KEY~;

    sz input_len = key.len + WS_GUID.len;
    char[] input = localmem.alloc_array(char, input_len)!;
    defer localmem.free(input);

    input[0:key.len] = key[..];
    input[key.len:WS_GUID.len] = WS_GUID[..];

    char[20] digest = sha1::hash(input);

    return base64::encode(localmem, digest[..]);
}


// Handshake response

fn Response*? websocket_handshake_response(Request* req)
{
    if (req == null) return WS_BAD_HANDSHAKE~;

    String key = req.websocket_key()!;
    String accept = ws_accept_key(key)!;
    defer localmem.free(accept);

    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_status(101)!;
    res.header("Upgrade", "websocket")!;
    res.header("Connection", "Upgrade")!;
    res.header("Sec-WebSocket-Accept", accept)!;

    return res;
}


// Unsupported-version response

fn Response*? websocket_version_response()
{
    Response* res = response_new()!;
    defer catch response_free(res);

    res.set_status(426)!;
    res.header("Upgrade", "websocket")!;
    res.header("Sec-WebSocket-Version", WS_VERSION)!;
    res.set_text("426 Upgrade Required")!;

    return res;
}

// eof