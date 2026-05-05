# Sanic API Reference

## Application

### `Sanic`

```python
from sanic import Sanic

app = Sanic(
    name="MyApp",
    config=None,                  # Config object or dict
    ctx=None,                     # custom app context object
    router=None,                  # custom Router
    signal_router=None,
    error_handler=None,           # custom ErrorHandler
    env_prefix="SANIC_",          # env var prefix for config
    request_class=None,           # custom Request class
    strict_slashes=False,
    log_config=None,              # logging.config dict; None = default
    configure_logging=True,
)

# App-level state / context
app.ctx.db   = db_pool            # arbitrary attributes on app.ctx
app.config.DEBUG = True

# Named app registry
app = Sanic.get_app("MyApp")      # retrieve by name
```

### Config

```python
app.config.DB_HOST = "localhost"
app.config.update({"DB_PORT": 5432})
app.config.update_config("./config.py")     # load from file
app.config.update_config(MyConfigClass)     # load from class
app.config.load_environment_vars(prefix="SANIC_")

# Built-in config keys
app.config.DEBUG                  # bool
app.config.ACCESS_LOG             # bool
app.config.KEEP_ALIVE             # bool
app.config.KEEP_ALIVE_TIMEOUT     # int (seconds)
app.config.REQUEST_MAX_SIZE       # int (bytes, default 100MB)
app.config.REQUEST_TIMEOUT        # int (seconds)
app.config.RESPONSE_TIMEOUT       # int (seconds)
app.config.CORS_ORIGINS           # str | list
app.config.WEBSOCKET_MAX_SIZE     # int (bytes)
app.config.WEBSOCKET_PING_INTERVAL # float
app.config.WEBSOCKET_PING_TIMEOUT  # float
app.config.GRACEFUL_SHUTDOWN_TIMEOUT # float
app.config.PROXIES_COUNT          # int — trusted proxy hops
app.config.REAL_IP_HEADER         # str — e.g. "X-Real-IP"
app.config.FORWARDED_FOR_HEADER   # str — e.g. "X-Forwarded-For"
```

---

## Running

```python
app.run(
    host="0.0.0.0",
    port=8000,
    debug=False,
    auto_reload=False,         # reload on file change (dev only)
    workers=1,                 # number of worker processes
    access_log=True,
    ssl=None,                  # ssl.SSLContext | dict(cert=, key=)
    unix=None,                 # unix socket path
    loop=None,
    protocol=None,             # custom asyncio.Protocol class
    backlog=100,
    fast=False,                # use all available CPU cores
    motd=True,                 # print startup banner
    verbosity=0,
)

# Programmatic (ASGI / testing)
import asyncio
asyncio.run(app.create_server(host="0.0.0.0", port=8000, return_asyncio_server=True))

# CLI
# sanic myapp:app --host=0.0.0.0 --port=8000 --workers=4 --debug
```

---

## Routing

### Decorators

```python
@app.get("/items/<id:int>")
@app.post("/items")
@app.put("/items/<id:int>")
@app.patch("/items/<id:int>")
@app.delete("/items/<id:int>")
@app.head("/items")
@app.options("/items")
@app.websocket("/ws")

@app.route("/items", methods=["GET", "POST"])
```

### Route Parameters

```python
@app.get(
    "/items/<id:int>",
    name="item_detail",              # named route
    version=1,                       # URL versioning: /v1/items/<id>
    strict_slashes=False,
    stream=False,                    # enable request body streaming
    ignore_body=False,
    hosts=["example.com"],           # host-based routing
)
async def get_item(request, id: int): ...
```

### Path Parameter Types

```python
<name>          # str (default)
<name:str>      # str
<name:int>      # int
<name:float>    # float
<name:alpha>    # alphabetic string
<name:slug>     # slug string (letters, numbers, hyphens)
<name:path>     # path segment (includes /)
<name:uuid>     # UUID
<name:ymd>      # date YYYY-MM-DD -> datetime.date
<name:regex(pattern)>   # custom regex
```

### `Blueprint`

```python
from sanic import Blueprint

bp = Blueprint(
    "items",
    url_prefix="/items",
    version=1,               # /v1/items/...
    strict_slashes=False,
)

@bp.get("/<id:int>")
async def get_item(request, id: int): ...

app.blueprint(bp)

# Blueprint Group
from sanic import Blueprint, BlueprintGroup

bp1 = Blueprint("auth", url_prefix="/auth")
bp2 = Blueprint("users", url_prefix="/users")

group = BlueprintGroup(url_prefix="/api", version=1)
group.blueprint(bp1)
group.blueprint(bp2)
app.blueprint(group)
```

### URL Building

```python
url = app.url_for("item_detail", id=1)                # "/items/1"
url = app.url_for("item_detail", id=1, _external=True) # "http://host/items/1"
url = app.url_for("static", name="app.static", filename="style.css")
```

---

## Request Object

```python
async def handler(request: Request):
    request.method           # "GET" | "POST" | ...
    request.url              # full URL string
    request.scheme           # "http" | "https"
    request.host             # "example.com"
    request.path             # "/items/1"
    request.query_string     # "foo=bar&baz=1"
    request.args             # RequestParameters (multi-value dict)
    request.args.get("q")
    request.args.getlist("tags")   # list[str]

    request.match_info       # dict — path params
    # or directly: request.param_name (auto-injected as handler arg)

    request.headers          # Header (case-insensitive dict)
    request.headers.get("Content-Type")
    request.cookies          # dict[str, str]
    request.ip               # str — remote IP
    request.port             # int — remote port
    request.socket           # (ip, port)
    request.conn_info        # ConnectionInfo

    # Body
    request.body             # bytes (fully buffered)
    request.json             # Any — parsed JSON
    request.form             # RequestParameters — application/x-www-form-urlencoded
    request.files            # dict[str, list[File]] — multipart
    request.text             # str — decoded body

    # App / context
    request.app              # Sanic instance
    request.ctx              # per-request context object (set in middleware)

    # Streaming
    async for data in request.stream:   # async generator of body chunks
        process(data)

    # Forwarded info (requires PROXIES_COUNT > 0)
    request.forwarded        # dict
```

### `File` object (from multipart)

```python
file = request.files["upload"][0]
file.name        # original filename
file.type        # MIME type
file.body        # bytes
```

---

## Response

### Response Helpers

```python
from sanic.response import (
    json, text, html, file, file_stream,
    redirect, stream, raw, empty,
    HTTPResponse,
)

return json({"key": "value"}, status=200, headers={}, indent=None)
return text("hello", status=200, headers={}, content_type="text/plain")
return html("<h1>Hello</h1>", status=200)
return empty(status=204)
return raw(b"\x00\x01", status=200, content_type="application/octet-stream")

# Redirect
return redirect("/new-path", status=302)
return redirect("https://example.com", status=301, headers={})

# File response
return await file(
    "path/to/file.pdf",
    filename="download.pdf",      # Content-Disposition name
    mime_type="application/pdf",
    headers={},
)

# Large file streaming
return await file_stream(
    "path/to/large.bin",
    chunk_size=1024*1024,
    filename="large.bin",
    mime_type="application/octet-stream",
)

# Streaming response (custom generator)
async def gen(response):
    await response.write("chunk1")
    await response.write("chunk2")

return stream(gen, content_type="text/plain")

# HTTPResponse (manual)
return HTTPResponse(
    body="hello",
    status=200,
    headers={"X-Custom": "value"},
    content_type="text/plain",
)
```

### Cookies

```python
response = json({"ok": True})

response.add_cookie(
    "session",
    "abc123",
    max_age=3600,
    expires=datetime(...),
    domain="example.com",
    path="/",
    secure=True,
    httponly=True,
    samesite="Lax",      # "Strict" | "Lax" | "None"
)
response.delete_cookie("session")
response.cookies["session"] = "value"   # simple set
del response.cookies["session"]         # delete
```

---

## Middleware

```python
# Request middleware (runs before handler)
@app.on_request
async def before(request):
    request.ctx.start_time = time.time()

# Response middleware (runs after handler)
@app.on_response
async def after(request, response):
    elapsed = time.time() - request.ctx.start_time
    response.headers["X-Process-Time"] = f"{elapsed:.4f}"
    return response              # must return response

# Blueprint-scoped middleware
@bp.on_request
async def bp_before(request): ...

# Order: app.on_request → bp.on_request → handler → bp.on_response → app.on_response
```

---

## Listeners (Lifecycle Hooks)

```python
@app.before_server_start
async def setup(app, loop):
    app.ctx.db = await create_db_pool()

@app.after_server_start
async def notify_ready(app, loop):
    logger.info("Server ready")

@app.before_server_stop
async def shutdown(app, loop):
    await app.ctx.db.close()

@app.after_server_stop
async def cleanup(app, loop):
    logger.info("Server stopped")

# Blueprint listeners
@bp.listener("before_server_start")
async def bp_setup(app, loop): ...

# Priorities (lower = earlier)
@app.before_server_start(priority=5)
async def high_priority_setup(app, loop): ...
```

---

## Error Handling

### `ErrorHandler`

```python
@app.exception(NotFound)
async def handle_404(request, exc):
    return json({"error": "not found"}, status=404)

@app.exception(Exception)
async def handle_all(request, exc):
    return json({"error": str(exc)}, status=500)

@app.exception(SanicException)
async def sanic_error(request, exc):
    return json({"error": exc.message}, status=exc.status_code)

# Custom exception class
from sanic.exceptions import SanicException

class PaymentRequired(SanicException):
    status_code = 402
    message = "Payment required"

raise PaymentRequired("upgrade your plan")
```

### Built-in Exceptions

```python
from sanic.exceptions import (
    SanicException,
    NotFound,            # 404
    Forbidden,           # 403
    Unauthorized,        # 401
    BadRequest,          # 400
    MethodNotAllowed,    # 405
    RequestTimeout,      # 408
    PayloadTooLarge,     # 413
    HeaderNotFound,      # 400
    InvalidHeader,       # 400
    ServiceUnavailable,  # 503
    ServerError,         # 500
    abort,               # raise by status code
)

abort(403, "Access denied")
abort(404)
raise NotFound("Page not found")
raise Unauthorized("Login required", scheme="Bearer", challenges={"realm": "API"})
```

---

## WebSocket

```python
@app.websocket("/ws/<room:str>")
async def ws_handler(request, ws, room: str):
    # Send
    await ws.send("text message")
    await ws.send(b"binary data")

    # Receive
    data = await ws.recv()              # str | bytes
    msg  = await ws.receive()           # WebSocketMessage object

    # Ping / Pong
    await ws.ping()
    await ws.pong()

    # Close
    await ws.close(code=1000, reason="done")

    ws.closed        # bool
    ws.connection    # underlying connection

# Event-based WebSocket
@app.on_message("ws/<id>")
async def on_message(request, ws, message): ...
```

---

## Signals

```python
# Built-in signal namespaces:
# http.lifecycle.begin, http.lifecycle.read_head, http.lifecycle.request,
# http.lifecycle.complete, http.lifecycle.response.before/after
# server.init.before/after, server.shutdown.before/after

# Dispatch a signal
await app.dispatch("my.custom.signal", context={"value": 42})

# Listen to a signal
@app.signal("my.custom.signal")
async def on_signal(value):          # context keys become kwargs
    print(value)

# Wildcard
@app.signal("http.lifecycle.<event>")
async def on_http(event): ...

# Wait for a signal
event = await app.event("my.custom.signal")
```

---

## Static Files

```python
app.static(
    "/static",
    "./static",                     # directory or file path
    name="static",
    strict_slashes=False,
    content_type=None,
    use_modified_since=True,
    use_content_range=False,        # enable Range header support
    stream_large_files=False,       # True | int (threshold in bytes)
    directory_view=False,           # show directory listing
    index="index.html",             # default index file
)

# URL for static file
url = app.url_for("static", name="app.static", filename="js/app.js")
```

---

## Streaming

### Request Streaming

```python
@app.post("/upload", stream=True)
async def upload(request):
    results = b""
    async for data in request.stream:
        results += data
    return text(f"received {len(results)} bytes")
```

### Response Streaming

```python
@app.get("/stream")
async def stream_response(request):
    async def gen(response):
        for i in range(10):
            await response.write(f"chunk {i}\n")
            await asyncio.sleep(0.1)
    return stream(gen, content_type="text/plain")

# Server-Sent Events
from sanic.response import ResponseStream

@app.get("/sse")
async def sse(request):
    async def event_gen(response):
        for i in range(5):
            await response.write(f"data: event {i}\n\n")
            await asyncio.sleep(1)
    return stream(event_gen, content_type="text/event-stream")
```

---

## Dependency Injection (Sanic Extensions)

```python
# Requires sanic-ext
from sanic_ext import Extend
Extend(app)

# Inject via type annotation
@app.get("/items")
async def list_items(request, db: Database): ...

# Register dependency
@app.ext.dependency(Database())
# or
app.ext.add_dependency(Database, factory=create_db)
```

---

## Testing

```python
from sanic.testing import SanicTestClient

# Sync test client
_, response = app.test_client.get("/items")
_, response = app.test_client.post("/items", json={"name": "foo"})
_, response = app.test_client.get("/items", headers={"Authorization": "Bearer token"})
_, response = app.test_client.get("/items", params={"q": "foo"})

response.status               # int
response.json                 # Any
response.text                 # str
response.headers              # dict
response.cookies              # dict

# Async test client
async def test_items():
    _, response = await app.asgi_client.get("/items")
    assert response.status == 200

# pytest-sanic
@pytest.fixture
def app():
    return create_app()

async def test_get_item(app):
    _, response = await app.asgi_client.get("/items/1")
    assert response.status == 200

# WebSocket testing
async def test_ws(app):
    _, ws = await app.asgi_client.websocket("/ws")
    await ws.send("hello")
    msg = await ws.receive()
```

---

## CORS (sanic-ext)

```python
from sanic_ext import Extend

Extend(app)
app.config.CORS_ORIGINS = "https://example.com"
app.config.CORS_METHODS = ["GET", "POST"]
app.config.CORS_ALLOW_HEADERS = ["Authorization", "Content-Type"]
app.config.CORS_EXPOSE_HEADERS = ["X-Custom"]
app.config.CORS_SUPPORTS_CREDENTIALS = True
app.config.CORS_MAX_AGE = 3600
```

---

## OpenAPI / Swagger (sanic-ext)

```python
from sanic_ext import openapi

@app.get("/items/<id:int>")
@openapi.summary("Get item by ID")
@openapi.description("Returns a single item")
@openapi.tag("items")
@openapi.response(200, {"application/json": ItemSchema}, "Success")
@openapi.response(404, description="Not found")
@openapi.parameter("id", int, "path", required=True)
@openapi.secured("bearerAuth")
@openapi.deprecated()
async def get_item(request, id: int): ...

# Schema definition
@openapi.component
class ItemSchema:
    id:    int
    name:  str
    price: float
```

---

## Common Patterns

```python
# Per-request context (attach data in middleware, read in handler)
@app.on_request
async def attach_user(request):
    token = request.headers.get("Authorization", "").removeprefix("Bearer ")
    request.ctx.user = await get_user_by_token(token)

@app.get("/me")
async def me(request):
    return json(request.ctx.user.to_dict())

# Database pool (lifespan via listener)
@app.before_server_start
async def setup_db(app, loop):
    app.ctx.db = await asyncpg.create_pool(app.config.DATABASE_URL)

@app.after_server_stop
async def close_db(app, loop):
    await app.ctx.db.close()

# Versioned blueprints
v1 = Blueprint("v1", url_prefix="/api/v1")
v2 = Blueprint("v2", url_prefix="/api/v2")

# Background task
@app.get("/trigger")
async def trigger(request):
    app.add_task(background_job(request.ctx.user))
    return json({"status": "queued"})

async def background_job(user):
    await asyncio.sleep(5)
    await notify(user)

# Streaming large file upload
@app.post("/ingest", stream=True)
async def ingest(request):
    async with aiofiles.open("output.bin", "wb") as f:
        async for chunk in request.stream:
            await f.write(chunk)
    return json({"ok": True})

# Rate limiting via middleware
@app.on_request
async def rate_limit(request):
    key = f"rl:{request.ip}"
    count = await redis.incr(key)
    if count == 1:
        await redis.expire(key, 60)
    if count > 100:
        raise ServiceUnavailable("rate limit exceeded")

# Custom request class
class MyRequest(Request):
    @property
    def locale(self):
        return self.headers.get("Accept-Language", "en")[:2]

app = Sanic("MyApp", request_class=MyRequest)
```
