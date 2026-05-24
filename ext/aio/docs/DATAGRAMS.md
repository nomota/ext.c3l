# ext::aio Datagram

UDP datagram support for `ext::aio`.

This module provides a small async UDP API built on top of `ext::aio::io` and `ext::aio::net`.


## Open and bind

### `datagram_bind`

```c3
fn Datagram*? aio::datagram_bind(String host, ushort port)
```

Creates a UDP socket and binds it to `host:port`.

```c3
Datagram* d = aio::datagram_bind("127.0.0.1", 9000)!;
defer d.free();
```

### `open_datagram`

```c3
fn Datagram*? open_datagram()
```

Creates an unbound UDP socket.

Use this for clients that only need to send datagrams, or for sockets that will be configured separately.

```c3
Datagram* d = aio::open_datagram()!;
defer d.free();

char[] msg = "hello";
d.sendto(msg, "127.0.0.1", 9000)!;
```

## State and lifetime

### `Datagram.is_closed`

```c3
fn bool Datagram.is_closed(&self) @inline
```

Returns `true` when the datagram socket is closed or its file descriptor is invalid.

```c3
if (d.is_closed()) return aio::DATAGRAM_CLOSED~;
```

### `Datagram.close`

```c3
fn void Datagram.close(&self)
```

Closes the underlying socket.

Calling `close()` more than once is safe.

```c3
d.close();
```

### `Datagram.free`

```c3
fn void Datagram.free(&self)
```

Closes the socket if needed and releases the `Datagram` object.

```c3
Datagram* d = aio::datagram_bind("127.0.0.1", 9000)!;
defer d.free();
```

## Send and receive

### `Datagram.sendto`

```c3
fn usz? Datagram.sendto(&self, char[] data, String ip, ushort port)
```

Sends `data` to the remote UDP endpoint `ip:port`.

Returns the number of bytes sent.

```c3
char[] msg = "ping";
usz n = d.sendto(msg, "127.0.0.1", 9000)!;
```

If the socket is closed, `DATAGRAM_CLOSED` is returned.

### `Datagram.recvfrom`

```c3
fn usz? Datagram.recvfrom(&self, char[] data, DatagramAddr* from)
```

Receives one UDP datagram into `data`.

Returns the number of bytes received and fills `from` with the sender address.

```c3
char[1500] buf;
DatagramAddr from;

usz n = d.recvfrom(buf[..], &from)!;
String msg = (String)buf[0:n];
```

The sender IP is stored in `from.ip`, with its length in `from.ip_len`.

```c3
String ip = (String)from.ip[0:from.ip_len];
ushort port = from.port;
```

## Example: UDP echo server

```c3
import ext::aio;
import ext::debug;

fn void? main_task(void* arg)
{
    Datagram* server = aio::datagram_bind("127.0.0.1", 9000)!;
    defer server.free();

    char[1500] buf;
    DatagramAddr from;

    while (true)
    {
        usz n = server.recvfrom(buf[..], &from)!;

        String ip = (String)from.ip[0:from.ip_len];
        String msg = (String)buf[0:n];

        warn("[server] recv from %s:%d: %s", ip, from.port, msg);

        server.sendto(buf[0:n], ip, from.port)!;
    }
}
```

## Example: UDP client

```c3
import ext::aio;
import ext::debug;

fn void? main_task(void* arg)
{
    Datagram* client = aio::open_datagram()!;
    defer client.free();

    char[] msg = "hello datagram";
    client.sendto(msg, "127.0.0.1", 9000)!;

    char[1500] buf;
    DatagramAddr from;

    usz n = client.recvfrom(buf[..], &from)!;

    String ip = (String)from.ip[0:from.ip_len];
    String reply = (String)buf[0:n];

    warn("[client] reply from %s:%d: %s", ip, from.port, reply);
}
```

## Error handling

`sendto()` and `recvfrom()` store the last error in `d.error` before returning the fault.

```c3
if (catch err = d.sendto(data, ip, port))
{
    warn("sendto failed: %s", err);
    return err~;
}
```

Closed sockets return `DATAGRAM_CLOSED`.

```c3
d.close();

if (catch err = d.recvfrom(buf[..], &from))
{
    if (err == aio::DATAGRAM_CLOSED)
    {
        warn("datagram is closed");
    }

    return err~;
}
```

## Notes

- UDP is message-oriented. Each `recvfrom()` receives at most one datagram.
- If the receive buffer is smaller than the incoming datagram, the datagram may be truncated by the platform socket API.
- `sendto()` does not guarantee delivery. UDP has no connection-level acknowledgement.
- Use `datagram_bind()` for servers.
- Use `open_datagram()` for simple UDP clients.
