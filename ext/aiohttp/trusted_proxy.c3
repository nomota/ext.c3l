// trusted_proxy.c3

// Trusted proxy support for ext::aio::http.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::aio::http;

import ext::mem;
import c::errno;
import ext::debug;

// Limits

const sz MAX_TRUSTED_PROXIES = 32;
const sz MAX_FORWARDED_ADDRESSES = 64;


// Configuration

struct TrustedProxyConfig
{
    String[MAX_TRUSTED_PROXIES] entries;
    sz count;
}

tlocal TrustedProxyConfig trusted_proxy_config;


// Configuration API

fn void trusted_proxy_clear()
{
    for (sz i = 0; i < trusted_proxy_config.count; i++) {
        str_free(trusted_proxy_config.entries[i]);
        trusted_proxy_config.entries[i] = "";
    }

    trusted_proxy_config.count = 0;
}

fn void? trusted_proxy_add(String value)
{
    String entry = value.trim();

    if (entry.len == 0) return errno::E_INVALID_ARG~;

    if (trusted_proxy_config.count >= MAX_TRUSTED_PROXIES) {
        return REQUEST_TOO_LARGE~;
    }

    trusted_proxy_config.entries[trusted_proxy_config.count++] = str_clone(entry);
}

fn void? trusted_proxy_set(String[] values)
{
    trusted_proxy_clear();

    foreach (String value : values) {
        trusted_proxy_add(value)!;
    }
}

fn sz trusted_proxy_count()
{
    return trusted_proxy_config.count;
}


// IPv4 parsing

fn bool trusted_proxy_parse_ipv4(String value, uint* result)
{
    if (result == null) return false;

    String text = value.trim();

    uint address = 0;
    sz pos = 0;

    for (sz part = 0; part < 4; part++) {
        String octet_text;

        if (part < 3) {
            sz separator = text[pos..].index_of(".") ?? -1;
            if (separator < 0) return false;

            octet_text = text[pos:separator];
            pos += separator + 1;
        } else {
            if (pos > text.len) return false;

            octet_text = text[pos..];
            pos = text.len;
        }

        if (octet_text.len == 0) return false;

        uint octet = octet_text.to_uint() ?? 256;
        if (octet > 255) return false;

        address = (address << 8) | octet;
    }

    if (pos != text.len) return false;

    *result = address;
    return true;
}

fn bool trusted_proxy_parse_cidr(String value, uint* network, uint* mask)
{
    if (network == null || mask == null) return false;

    sz slash = value.index_of("/") ?? -1;
    if (slash <= 0) return false;

    String address_text = value[0:slash].trim();
    String prefix_text = value[slash + 1..].trim();

    uint address;

    if (!trusted_proxy_parse_ipv4(address_text, &address)) {
        return false;
    }

    uint prefix = prefix_text.to_uint() ?? 33;
    if (prefix > 32) return false;

    uint network_mask;

    if (prefix == 0) {
        network_mask = 0;
    } else {
        network_mask = 0xffffffffu << (32 - prefix);
    }

    *network = address & network_mask;
    *mask = network_mask;

    return true;
}


// Address matching

fn bool trusted_proxy_is_loopback(String address)
{
    String ip = address.trim();

    if (ip == "::1") return true;

    uint ipv4;

    if (!trusted_proxy_parse_ipv4(ip, &ipv4)) {
        return false;
    }

    return (ipv4 & 0xff000000u) == 0x7f000000u;
}

fn bool trusted_proxy_is_private(String address)
{
    String ip = address.trim();

    if (
        ip.starts_with("fc") ||
        ip.starts_with("fd") ||
        ip.starts_with("FC") ||
        ip.starts_with("FD")
    ) {
        return true;
    }

    uint ipv4;

    if (!trusted_proxy_parse_ipv4(ip, &ipv4)) {
        return false;
    }

    if ((ipv4 & 0xff000000u) == 0x0a000000u) {
        return true;
    }

    if ((ipv4 & 0xfff00000u) == 0xac100000u) {
        return true;
    }

    if ((ipv4 & 0xffff0000u) == 0xc0a80000u) {
        return true;
    }

    return false;
}

fn bool trusted_proxy_entry_matches(String entry, String address)
{
    String rule = entry.trim();
    String ip = address.trim();

    if (rule == "loopback") {
        return trusted_proxy_is_loopback(ip);
    }

    if (rule == "private") {
        return trusted_proxy_is_private(ip);
    }

    if (!rule.contains("/")) {
        return str_iequals(rule, ip);
    }

    uint network;
    uint mask;
    uint ipv4;

    if (!trusted_proxy_parse_cidr(rule, &network, &mask)) {
        return false;
    }

    if (!trusted_proxy_parse_ipv4(ip, &ipv4)) {
        return false;
    }

    return (ipv4 & mask) == network;
}

fn bool trusted_proxy_is_trusted(String address)
{
    String ip = address.trim();

    if (ip.len == 0) return false;

    for (sz i = 0; i < trusted_proxy_config.count; i++) {
        if (trusted_proxy_entry_matches(trusted_proxy_config.entries[i], ip)) {
            return true;
        }
    }

    return false;
}


// Forwarded address parsing

fn sz trusted_proxy_parse_x_forwarded_for(String value, String[] addresses)
{
    if (addresses.len == 0) return 0;

    sz count = 0;
    sz pos = 0;

    while (pos <= value.len && count < addresses.len) {
        sz comma = value[pos..].index_of(",") ?? -1;

        String address;

        if (comma < 0) {
            address = value[pos..].trim();
            pos = value.len + 1;
        } else {
            address = value[pos:comma].trim();
            pos += comma + 1;
        }

        if (address.len == 0) continue;

        addresses[count++] = address;
    }

    return count;
}


// Client IP resolution

fn String Request.client_ip(&self)
{
    String peer_ip = self.remote_ip.trim();

    if (peer_ip.len == 0) return "";

    if (!trusted_proxy_is_trusted(peer_ip)) {
        return peer_ip;
    }

    String? forwarded = self.header("X-Forwarded-For");

    if (catch err = forwarded) {
        String? real_ip = self.header("X-Real-IP");

        if (catch real_err = real_ip) {
            return peer_ip;
        }

        String candidate = real_ip.trim();

        if (candidate.len == 0) {
            return peer_ip;
        }

        return candidate;
    }

    String[MAX_FORWARDED_ADDRESSES] addresses;
    sz count = trusted_proxy_parse_x_forwarded_for(forwarded, addresses[..]);

    if (count == 0) return peer_ip;

    for (sz i = count; i > 0; i--) {
        String candidate = addresses[i - 1];

        if (!trusted_proxy_is_trusted(candidate)) {
            return candidate;
        }
    }

    return addresses[0];
}

fn String Context.ip(&self)
{
    if (self.req == null) return "";

    return self.req.client_ip();
}

// eof