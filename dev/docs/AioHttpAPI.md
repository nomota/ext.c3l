# aiohttp API Reference

## Client

### `ClientSession`

```python
session = aiohttp.ClientSession(
    connector=TCPConnector(...),
    timeout=ClientTimeout(...),
    json_serialize=ujson.dumps,
    cookie_jar=aiohttp.DummyCookieJar(),
    headers={...},           # default headers
    auth=aiohttp.BasicAuth("user", "pass"),
    raise_for_status=False,  # auto-raise on 4xx/5xx
)
```

**HTTP Methods** — all return `ClientResponse` (use as async context manager)

```python
async with session.get(url, params={}, headers={}, ssl=None) as resp: ...
async with session.post(url, data=b"...", json={}, headers={}) as resp: ...
async with session.put(url, data=...) as resp: ...
async with session.patch(url, json={}) as resp: ...
async with session.delete(url) as resp: ...
async with session.head(url) as resp: ...
async with session.options(url) as resp: ...
async with session.request("GET", url, **kwargs) as resp: ...
```

**State**

```python
session.closed          # bool
await session.close()

---

### `ClientTimeout`

```python
timeout = aiohttp.ClientTimeout(
    total=30,       # entire request (connect + read), seconds
    connect=5,      # connection pool wait + socket connect
    sock_connect=5, # socket connect only
    sock_read=10,   # per read() call
)
```

---

### `TCPConnector` (extends `BaseConnector`)

```python
connector = aiohttp.TCPConnector(
    limit=100,           # total concurrent connections (0 = unlimited)
    limit_per_host=0,    # per-host limit (0 = unlimited)
    ssl=None,            # None | False | ssl.SSLContext
    read_bufsize=2**16,  # per-connection read buffer (bytes)
    use_dns_cache=True,
    ttl_dns_cache=10,    # DNS cache TTL (seconds)
    keepalive_timeout=15,
    enable_cleanup_closed=True,
)

connector.limit            # total limit
connector.limit_per_host   # per-host limit
connector.total_conns      # active connection count
# connector.host_probs     # internal: host connection stats
await connector.close()
connector.closed           # bool
```

**`BaseConnector`** (base class)

```python
await connector.connect(request, traces, timeout)  # -> Connection
connector.force_close   # bool — close after each request
connector.closed        # bool
connector.limit
connector.limit_per_host
await connector.close()
```

---

### `ClientResponse`

```python
resp.status              # int, e.g. 200
resp.reason              # str, e.g. "OK", "Not Found"
resp.url                 # yarl.URL
resp.headers             # CIMultiDictProxy
resp.headers.get("Content-Type")
resp.cookies             # SimpleCookie
resp.history             # tuple[ClientResponse, ...] — redirect chain

resp.raise_for_status()  # raises ClientResponseError on 4xx/5xx

# Body reading (choose one)
data   = await resp.read()              # bytes
text   = await resp.text(encoding=None) # str
obj    = await resp.json(content_type="application/json")

# Streaming
async for chunk in resp.content.iter_chunked(1024): ...
async for line  in resp.content:        ...

resp.content             # StreamReader
await resp.release()     # free connection back to pool (auto on ctx-manager exit)

# Low-level
resp.connection          # Connection object
resp.connection.transport
```

---

### Cookie Jars

```python
# Ignore all cookies (e.g. for APIs)
jar = aiohttp.DummyCookieJar()

# Standard cookie jar
jar = aiohttp.CookieJar(unsafe=True)  # unsafe=True allows IP-address cookies

jar.filter_cookies(url)                    # -> SimpleCookie for url
jar.update_cookies(cookies, response_url)

for cookie in jar:
    print(cookie.key, cookie.value)
```

---

### WebSocket Client

```python
async with session.ws_connect(
    url,
    heartbeat=30.0,          # auto-ping interval (seconds)
    receive_timeout=30.0,    # max wait for a message
    compress=15,             # per-message deflate (0 = off)
    protocols=("chat", "json-rpc"),
    ssl=None,
) as ws:
    ...
```

**`ClientWebSocketResponse`**

```python
# Send
await ws.send_str(data)
await ws.send_bytes(data)
await ws.send_json(obj)
await ws.ping(message=b"keep-alive")
await ws.pong(message=b"ack")

# Receive
msg = await ws.receive()          # WSMessage
msg = await ws.receive_str()      # str
msg = await ws.receive_bytes()    # bytes
obj = await ws.receive_json()     # Any

# WSMessage
msg.type   # WSMsgType.TEXT | BINARY | PING | PONG | CLOSE | ERROR
msg.data   # str | bytes | None
msg.extra  # str — close reason, or error string

# Close
await ws.close(
    code=aiohttp.WSCloseCode.NORMAL_CLOSURE,  # 1000
    message=b"service restart",
)
# WSCloseCode: NORMAL_CLOSURE(1000), GOING_AWAY(1001), UNSUPPORTED_DATA(1003)

ws.closed               # bool
ws.protocol             # negotiated sub-protocol string
ws.compress             # negotiated per-message deflate level
ws.get_extra_info("peername")  # (host, port)
ws.exception()          # last exception or None
```

---

## Server

### Application Setup

```python
app = web.Application(
    middlewares=[auth_middleware],
    client_max_size=1024**2,
)

# Lifecycle hooks
app.on_startup.append(on_startup)   # async def on_startup(app)
app.on_shutdown.append(on_shutdown)
app.on_cleanup.append(on_cleanup)

# Cleanup contexts (startup + teardown in one generator)
app.cleanup_ctx.append(db_context)
# async def db_context(app):
#     app['db'] = await create_pool(...)
#     yield
#     await app['db'].close()

# App-level state (shared across handlers)
app['db'] = db_pool
app['config'] = config
```

---

### Routing

```python
# Option A — RouteTableDef (decorator style)
routes = web.RouteTableDef()

@routes.get("/")
@routes.post("/users")
@routes.view("/resource")         # class-based view
async def handler(request): ...

app.add_routes(routes)

# Option B — inline
app.router.add_get("/", handler)
app.router.add_post("/users", handler)
app.router.add_static("/static", Path("./static"))

# Path parameters
web.get("/post/{id}", handler)               # request.match_info["id"]
web.get(r"/api/{version:\d+}/", handler)     # regex constraint

# Named routes (for URL generation)
app.router.add_get("/user/{id}", handler, name="user_detail")
app.router["user_detail"].url_for(id="42")   # -> URL('/user/42')
```

---

### `web.Request`

```python
request.method           # "GET", "POST", ...
request.url              # yarl.URL
request.path             # "/api/users"
request.query            # MultiDict — ?key=val
request.query.get("page", "1")
request.headers          # CIMultiDictProxy
request.match_info["id"] # path parameter
request.match_info.get("name", "default")

request.app              # Application instance
request.app["db"]        # access shared state
request.query()
# Body
body   = await request.read()        # bytes
text   = await request.text()        # str
obj    = await request.json()        # Any
fields = await request.post()        # MultiDict (form / multipart)
reader = await request.multipart()   # MultipartReader

request.cookies          # Mapping[str, str]
request.can_read_body    # bool
```

---

### `web.Response` / `web.StreamResponse`

```python
# Simple responses
return web.Response(text="Hello")
return web.Response(body=b"\x00\x01", content_type="application/octet-stream")
return web.json_response({"key": "value"}, status=201)
return web.Response(status=204)

# File response
return web.FileResponse(Path("./file.bin"))

# Streaming response
resp = web.StreamResponse(status=200, headers={"X-Custom": "value"})
await resp.prepare(request)
await resp.write(b"chunk1")
await resp.write(b"chunk2")
await resp.write_eof()
return resp

# Redirect
raise web.HTTPFound("/new-location")    # 302
raise web.HTTPMovedPermanently("/new")  # 301

# Error shortcuts
raise web.HTTPBadRequest(text="invalid input")   # 400
raise web.HTTPUnauthorized()                     # 401
raise web.HTTPForbidden()                        # 403
raise web.HTTPNotFound()                         # 404
raise web.HTTPInternalServerError()              # 500

# WebSocket Serverside

app.add_routes([web.get('/ws', websocket_handler)])
async def websocket_handler(request):
    # 1. Initialize the WebSocket response
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    # 2. Iterate over incoming messages
    async for msg in ws:
        await ws.send_str(f"Server received: {msg.data}")
    await ws.close()
    return ws


```

---

### Running the Server

```python
web.run_app(app)
runner = web.AppRunner(app)
await runner.setup()

site = web.TCPSite(
    runner,
    host="0.0.0.0",
    port=8080,
    shutdown_timeout=60.0,
    ssl_context=ssl_ctx,       # None for plain HTTP
    backlog=128,
)
await site.start()

# Graceful shutdown
await runner.cleanup()

# runner.addresses  -> list of bound (host, port)
# runner.server     -> aiohttp Server instance
```

---

### Middleware

```python
@web.middleware
async def auth_middleware(request, handler):
    token = request.headers.get("Authorization")
    if not token:
        raise web.HTTPUnauthorized()
    response = await handler(request)
    response.headers["X-Processed-By"] = "auth"
    return response
```

---

## Transport / Protocol (Low-level)

### `asyncio.Transport`

```python
transport.write(data: bytes)
transport.write_eof()
transport.close()
transport.abort()                               # discard buffer, close immediately
transport.get_extra_info("peername")            # (host, port) remote address
transport.get_extra_info("sockname")            # (host, port) local address
transport.get_extra_info("socket")              # raw socket
transport.set_write_buffer_limits(high, low)
transport.pause_reading()
transport.resume_reading()
```

### `ResponseHandler` (asyncio Protocol)

```python
handler.connection_made(transport)
handler.data_received(data)       # feeds HTTP parser
handler.connection_lost(exc)
handler.set_response_params(...)  # timeout, read buffer limit
handler.pause_reading()           # called when buffer full
```

---

## Common Patterns

```python
# Session as context manager (auto-close)
async with aiohttp.ClientSession() as session:
    async with session.get(url) as resp:
        data = await resp.json()

# Upload file
with open("file.bin", "rb") as f:
    async with session.post(url, data={"file": f}) as resp: ...

# Multipart upload
data = aiohttp.FormData()
data.add_field("file", open("report.csv"), filename="report.csv", content_type="text/csv")
async with session.post(url, data=data) as resp: ...

# Chunked streaming download
async with session.get(large_url) as resp:
    with open("out.bin", "wb") as f:
        async for chunk in resp.content.iter_chunked(65536):
            f.write(chunk)

# Basic auth
auth = aiohttp.BasicAuth("user", "password")
async with session.get(url, auth=auth) as resp: ...

# Custom SSL
import ssl
ctx = ssl.create_default_context(cafile="ca.pem")
ctx.load_cert_chain("client.crt", "client.key")
async with session.get(url, ssl=ctx) as resp: ...
```
