# Falcon API Reference

## Application

### `falcon.App` / `falcon.asgi.App`

```python
import falcon
import falcon.asgi

# WSGI (sync)
app = falcon.App(
    media_type=falcon.MEDIA_JSON,       # default request/response media type
    req_options=None,                   # RequestOptions
    resp_options=None,                  # ResponseOptions
    middleware=[],                      # list of middleware objects
    router=None,                        # custom Router
    independent_middleware=True,        # True = run all middleware even if handler raises
    cors_enable=False,                  # enable built-in CORS handler
    sink_before_static_route=True,
    error_serializer=None,              # custom error serializer fn
)

# ASGI (async)
app = falcon.asgi.App(
    media_type=falcon.MEDIA_JSON,
    middleware=[],
    router=None,
    cors_enable=False,
)
```

### Media Types

```python
falcon.MEDIA_JSON        # "application/json"
falcon.MEDIA_MSGPACK     # "application/msgpack"
falcon.MEDIA_YAML        # "application/yaml"
falcon.MEDIA_XML         # "application/xml"
falcon.MEDIA_HTML        # "text/html"
falcon.MEDIA_JS          # "application/javascript"
falcon.MEDIA_TEXT        # "text/plain"
falcon.MEDIA_JPEG        # "image/jpeg"
falcon.MEDIA_PNG         # "image/png"
falcon.MEDIA_GIF         # "image/gif"
```

---

## Routing

### Adding Routes

```python
app.add_route("/items", ItemResource())
app.add_route("/items/{id}", ItemResource())
app.add_route("/items/{id:int}", ItemResource())

app.add_route(
    "/items/{id}",
    ItemResource(),
    suffix="v2",                  # disambiguate same class on multiple routes
)

# Static route (no path params)
app.add_static_route("/healthz", HealthResource())

# Sink — catch-all for unmatched paths
app.add_sink(sink_fn, prefix="/legacy")
async def sink_fn(req, resp):
    resp.text = "legacy endpoint"
```

### Path Parameter Converters

```python
{name}          # str (default)
{name:int}      # int
{name:float}    # float
{name:uuid}     # uuid.UUID
{name:dt}       # datetime (ISO 8601)
{name+}         # remainder path segment (greedy, includes /)
```

### Custom Converter

```python
class SlugConverter:
    PATTERN = r"[a-z0-9\-]+"

    def convert(self, value):
        return value.lower()

app.router.register_converter("slug", SlugConverter)
# usage: /posts/{slug:slug}
```

### URL Building

```python
uri = app.uri_template_for(ItemResource)   # -> "/items/{id}"
```

---

## Resource Classes

### WSGI Resource

```python
class ItemResource:
    def on_get(self, req, resp, **params):
        resp.media = {"id": params["id"]}

    def on_post(self, req, resp):
        data = req.get_media()            # sync
        resp.status = falcon.HTTP_201
        resp.media = {"created": True}

    def on_put(self, req, resp, id):
        ...

    def on_patch(self, req, resp, id):
        ...

    def on_delete(self, req, resp, id):
        resp.status = falcon.HTTP_204

    def on_head(self, req, resp):
        ...

    def on_options(self, req, resp):
        ...

    # Method-not-allowed is handled automatically for undefined methods
```

### ASGI Resource

```python
class ItemResource:
    async def on_get(self, req, resp, **params):
        resp.media = await req.get_media()

    async def on_post(self, req, resp):
        data = await req.get_media()
        resp.status = falcon.HTTP_201

    async def on_websocket(self, req, ws):    # WebSocket handler (ASGI only)
        await ws.accept()
        ...
```

### Method Suffixes (multiple routes, same class)

```python
class ItemResource:
    def on_get_list(self, req, resp):        # suffix="list"
        ...
    def on_get_detail(self, req, resp, id):  # suffix="detail"
        ...

app.add_route("/items",      ItemResource(), suffix="list")
app.add_route("/items/{id}", ItemResource(), suffix="detail")
```

---

## Request — `falcon.Request`

```python
req.method            # "GET" | "POST" | ...
req.path              # "/items/1"
req.prefix            # URL prefix
req.url               # full URL string
req.uri               # alias for url
req.forwarded_uri     # URL accounting for X-Forwarded-* headers
req.scheme            # "http" | "https"
req.host              # "example.com"
req.port              # int
req.netloc             # "example.com:8080"
req.query_string      # "foo=bar&baz=1"
req.remote_addr       # str — client IP
req.access_route      # list[str] — IPs through proxies

# Query params
req.params            # dict[str, str] — last value wins for duplicates
req.get_param("q")                           # str | None
req.get_param("q", required=True)            # raises MissingParam if absent
req.get_param("q", default="default")
req.get_param_as_int("page", min_value=1, max_value=100)
req.get_param_as_float("score")
req.get_param_as_bool("active")              # "true"/"false"/"1"/"0"/"yes"/"no"
req.get_param_as_list("tags")                # "a,b,c" -> ["a", "b", "c"]
req.get_param_as_date("start", format_string="%Y-%m-%d")
req.get_param_as_datetime("ts")              # ISO 8601
req.get_param_as_uuid("id")

# Headers
req.headers           # dict (uppercase, hyphen-normalized)
req.get_header("Content-Type")
req.get_header("X-Token", required=True)
req.content_type      # str | None
req.content_length    # int | None
req.accept            # str
req.auth              # Authorization header value
req.user_agent        # str | None
req.referer           # str | None
req.if_modified_since # datetime | None
req.range             # (start, end) tuple | None

# Cookies
req.cookies           # dict[str, str]
req.get_cookie_values("session")   # list[str] (all values)

# Body
data   = req.bounded_stream.read()                # bytes (WSGI)
data   = await req.stream.read()                  # bytes (ASGI)
media  = req.get_media()                          # WSGI — parsed body
media  = await req.get_media()                    # ASGI — parsed body
req.media                                         # cached alias (WSGI)

# Multipart
form = req.get_media()                            # RequestBody (multipart)
for part in form:
    part.name
    part.filename
    part.content_type
    part.data                                     # bytes
    part.text                                     # str
    await part.get_data()                         # bytes (ASGI)

# Context
req.context                # dict-like (RequestContext) — per-request storage
req.context.user = user    # set arbitrary attributes
```

### `RequestOptions`

```python
app.req_options.media_handlers             # MediaHandlers
app.req_options.default_media_type        # str
app.req_options.auto_parse_form_urlencoded = True
app.req_options.auto_parse_qs_csv         = True   # "a,b" -> ["a", "b"]
app.req_options.keep_blank_qs_values      = False
app.req_options.strip_url_path_trailing_slash = False
app.req_options.max_receive_queue         = 4      # ASGI stream buffer
```

---

## Response — `falcon.Response`

```python
# Status
resp.status = falcon.HTTP_200       # "200 OK"
resp.status = falcon.HTTP_201
resp.status = falcon.HTTP_204
resp.status = falcon.HTTP_400
resp.status = falcon.HTTP_401
resp.status = falcon.HTTP_403
resp.status = falcon.HTTP_404
resp.status = falcon.HTTP_422
resp.status = falcon.HTTP_500
resp.status = "418 I'm a Teapot"    # custom

# Body
resp.media = {"key": "value"}       # auto-serialized (JSON by default)
resp.text  = "plain text"           # sets Content-Type: text/plain
resp.data  = b"\x00\x01"           # raw bytes
resp.content_type = falcon.MEDIA_JSON

# Headers
resp.set_header("X-Custom", "value")
resp.append_header("Vary", "Accept-Encoding")
resp.delete_header("X-Powered-By")
resp.get_header("Content-Type")

# Cookies
resp.set_cookie(
    "session",
    "abc123",
    max_age=3600,
    expires=datetime(...),
    domain="example.com",
    path="/",
    secure=True,
    http_only=True,
    same_site="Lax",           # "Strict" | "Lax" | "None"
)
resp.unset_cookie("session")

# Caching headers
resp.cache_control = ["no-cache", "no-store"]
resp.etag = "abc123"
resp.last_modified = datetime.utcnow()
resp.expires = datetime(...)
resp.vary = ["Accept", "Accept-Encoding"]

# Content negotiation
resp.content_type = "application/json; charset=utf-8"

# Streaming
resp.stream = my_async_generator()             # ASGI — async generator of bytes
resp.set_stream(sync_gen, content_length=1024) # WSGI — sync generator

# Download
resp.downloadable_as = "report.pdf"           # sets Content-Disposition: attachment

# Redirect helpers
raise falcon.HTTPFound("/new-path")           # 302
raise falcon.HTTPMovedPermanently("/new")     # 301
raise falcon.HTTPSeeOther("/other")           # 303
raise falcon.HTTPTemporaryRedirect("/tmp")    # 307
raise falcon.HTTPPermanentRedirect("/perm")   # 308
```

### `ResponseOptions`

```python
app.resp_options.media_handlers             # MediaHandlers
app.resp_options.default_media_type        # str
app.resp_options.secure_cookies_by_default = False
app.resp_options.static_media_type        = None
app.resp_options.suffixes                  # tuple — content-type suffix map
```

---

## Error Handling

### Built-in HTTP Exceptions

```python
from falcon import (
    HTTPError,
    HTTPBadRequest,           # 400
    HTTPUnauthorized,         # 401
    HTTPForbidden,            # 403
    HTTPNotFound,             # 404
    HTTPMethodNotAllowed,     # 405
    HTTPNotAcceptable,        # 406
    HTTPConflict,             # 409
    HTTPGone,                 # 410
    HTTPLengthRequired,       # 411
    HTTPPreconditionFailed,   # 412
    HTTPPayloadTooLarge,      # 413
    HTTPUnsupportedMediaType, # 415
    HTTPUnprocessableEntity,  # 422
    HTTPTooManyRequests,      # 429
    HTTPInternalServerError,  # 500
    HTTPNotImplemented,       # 501
    HTTPBadGateway,           # 502
    HTTPServiceUnavailable,   # 503
)

raise HTTPNotFound(title="Item not found", description="No item with that ID")
raise HTTPUnauthorized(
    title="Auth required",
    description="Provide a valid token",
    challenges=["Bearer realm='API'"],
    headers={"WWW-Authenticate": "Bearer"},
)
raise HTTPTooManyRequests(
    title="Rate limit exceeded",
    retry_after=60,            # Retry-After header (int seconds or datetime)
)
raise HTTPError(
    status=falcon.HTTP_422,
    title="Validation failed",
    description="...",
    headers={},
    href="https://docs.example.com/errors/422",
    code=40001,                # app-specific error code
)
```

### Custom Error Handler

```python
def handle_value_error(req, resp, ex, params):
    raise falcon.HTTPBadRequest(description=str(ex))

async def async_handle_value_error(req, resp, ex, params):
    raise falcon.HTTPBadRequest(description=str(ex))

app.add_error_handler(ValueError, handle_value_error)
app.add_error_handler(Exception, catch_all_handler)

# Custom error serializer
def error_serializer(req, resp, exception):
    resp.content_type = falcon.MEDIA_JSON
    resp.data = json.dumps({
        "error": exception.title,
        "detail": exception.description,
    }).encode()

app = falcon.App(error_serializer=error_serializer)
```

---

## Middleware

```python
# WSGI middleware
class AuthMiddleware:
    def process_request(self, req, resp):
        token = req.get_header("Authorization")
        if not token:
            raise falcon.HTTPUnauthorized()
        req.context.user = verify_token(token)

    def process_resource(self, req, resp, resource, params):
        # called after routing, before handler
        pass

    def process_response(self, req, resp, resource, req_succeeded):
        resp.set_header("X-Powered-By", "Falcon")

# ASGI middleware
class AuthMiddleware:
    async def process_request(self, req, resp):
        token = req.get_header("Authorization")
        if not token:
            raise falcon.HTTPUnauthorized()
        req.context.user = await verify_token(token)

    async def process_resource(self, req, resp, resource, params):
        pass

    async def process_response(self, req, resp, resource, req_succeeded):
        pass

# Startup / shutdown (ASGI only)
class DBMiddleware:
    async def process_startup(self, scope, event):
        self.pool = await create_db_pool()

    async def process_shutdown(self, scope, event):
        await self.pool.close()

app = falcon.asgi.App(middleware=[AuthMiddleware(), DBMiddleware()])
```

---

## Hooks

```python
from falcon import before, after

def require_auth(req, resp, resource, params):
    if not req.context.user:
        raise falcon.HTTPUnauthorized()

def add_timing(req, resp, resource, params):
    req.context.start = time.time()

def log_response(req, resp, resource, params):
    elapsed = time.time() - req.context.start
    logger.info(f"{req.method} {req.path} {resp.status} {elapsed:.3f}s")

# Class-level hook
@falcon.before(require_auth)
@falcon.after(log_response)
class ItemResource:
    def on_get(self, req, resp, id): ...

# Method-level hook
class ItemResource:
    @falcon.before(require_auth)
    @falcon.after(log_response)
    def on_get(self, req, resp, id): ...

# ASGI async hooks
async def async_require_auth(req, resp, resource, params):
    req.context.user = await get_user(req)

@falcon.before(async_require_auth)
class ItemResource:
    async def on_get(self, req, resp): ...
```

---

## Media Handlers

```python
import falcon.media

# JSON (default)
app.req_options.media_handlers.update({
    falcon.MEDIA_JSON: falcon.media.JSONHandler(
        dumps=ujson.dumps,
        loads=ujson.loads,
    ),
})

# MessagePack
app.req_options.media_handlers.update({
    falcon.MEDIA_MSGPACK: falcon.media.MessagePackHandler(),
})

# Custom media handler
class CSVHandler:
    def deserialize(self, stream, content_type, content_length):
        return list(csv.reader(io.StringIO(stream.read().decode())))

    def serialize(self, media, content_type):
        out = io.StringIO()
        csv.writer(out).writerows(media)
        return out.getvalue().encode()

app.req_options.media_handlers.update({"text/csv": CSVHandler()})
app.resp_options.media_handlers.update({"text/csv": CSVHandler()})
```

---

## WebSocket (ASGI)

```python
class ChatResource:
    async def on_websocket(self, req, ws):
        await ws.accept()

        # Send
        await ws.send_text("hello")
        await ws.send_data(b"binary")
        await ws.send_media({"event": "connected"})   # serialized via media handler

        # Receive
        text  = await ws.receive_text()               # str
        data  = await ws.receive_data(timeout=30.0)   # bytes
        media = await ws.receive_media()              # deserialized

        # Close
        await ws.close(code=1000)

        ws.closed              # bool
        ws.subprotocol         # negotiated subprotocol | None
        ws.unaccepted          # bool — before accept()

        # Headers / params available via req
        req.headers.get("Authorization")
        req.params

app.add_route("/ws", ChatResource())
```

---

## Server-Sent Events (ASGI)

```python
import falcon.asgi.sse as sse

class EventResource:
    async def on_get(self, req, resp):
        resp.sse = self.emit_events()

    async def emit_events(self):
        for i in range(10):
            yield sse.SSEvent(
                data=json.dumps({"n": i}),
                event="update",
                event_id=str(i),
                retry=5000,         # client reconnect interval (ms)
            )
            await asyncio.sleep(1)
        # StopIteration ends the stream
```

---

## Static Files

```python
app.add_static_route(
    "/static",
    "/path/to/static/files",
    downloadable=False,        # add Content-Disposition: attachment
    fallback_filename=None,    # e.g. "index.html" for SPA fallback
)
```

---

## Testing

```python
from falcon import testing

# WSGI
client = testing.TestClient(app)

result = client.simulate_get("/items")
result = client.simulate_get("/items/1", headers={"Authorization": "Bearer token"})
result = client.simulate_post("/items", json={"name": "foo"})
result = client.simulate_put("/items/1", json={...})
result = client.simulate_patch("/items/1", json={...})
result = client.simulate_delete("/items/1")
result = client.simulate_request("GET", "/items", query_string="q=foo")

result.status_code           # int
result.status                # "200 OK"
result.json                  # Any
result.text                  # str
result.content               # bytes
result.headers               # dict
result.cookies               # dict

# ASGI
class TestApp(testing.TestCase):
    def create_app(self):
        return falcon.asgi.App()

async def test_items():
    client = testing.TestClient(asgi_app)
    result = await client.simulate_get("/items")

# WebSocket testing (ASGI)
async def test_ws():
    async with testing.simulate_ws(app, "/ws") as ws:
        await ws.send_text("hello")
        msg = await ws.receive_text()
        await ws.close()
```

---

## Common Patterns

```python
# Collection + item resource pattern
class ItemCollection:
    def on_get(self, req, resp):          # GET /items
        resp.media = {"items": [...]}

    def on_post(self, req, resp):         # POST /items
        data = req.get_media()
        resp.status = falcon.HTTP_201
        resp.media = {"id": new_id}

class ItemResource:
    def on_get(self, req, resp, id):      # GET /items/{id}
        ...

    def on_put(self, req, resp, id):      # PUT /items/{id}
        ...

    def on_delete(self, req, resp, id):   # DELETE /items/{id}
        resp.status = falcon.HTTP_204

app.add_route("/items",      ItemCollection())
app.add_route("/items/{id}", ItemResource())

# Dependency injection via resource __init__
class ItemResource:
    def __init__(self, db, cache):
        self.db    = db
        self.cache = cache

    def on_get(self, req, resp, id):
        item = self.cache.get(id) or self.db.get(id)
        resp.media = item

db    = Database()
cache = Cache()
app.add_route("/items/{id}", ItemResource(db, cache))

# Context-based auth
class AuthMiddleware:
    async def process_request(self, req, resp):
        token = req.get_header("Authorization", "").removeprefix("Bearer ")
        req.context.user = await auth_service.get_user(token)
        if not req.context.user:
            raise falcon.HTTPUnauthorized()

# Pagination helper
def get_page_params(req):
    page  = req.get_param_as_int("page",  default=1,  min_value=1)
    limit = req.get_param_as_int("limit", default=20, max_value=100)
    return page, limit, (page - 1) * limit

# Streaming response (ASGI)
class ReportResource:
    async def on_get(self, req, resp):
        async def gen():
            async for row in db.fetch_large_result():
                yield (json.dumps(row) + "\n").encode()

        resp.content_type = "application/x-ndjson"
        resp.stream = gen()

# Health check resource
class HealthResource:
    def on_get(self, req, resp):
        resp.media = {"status": "ok"}

app.add_route("/healthz", HealthResource())

# CORS via middleware
class CORSMiddleware:
    def process_response(self, req, resp, resource, req_succeeded):
        resp.set_header("Access-Control-Allow-Origin", "*")
        resp.set_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        resp.set_header("Access-Control-Allow-Headers", "Authorization, Content-Type")

# or use built-in: falcon.App(cors_enable=True)
```
