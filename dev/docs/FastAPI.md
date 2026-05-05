# FastAPI API Reference

## Application

### `FastAPI`

```python
from fastapi import FastAPI

app = FastAPI(
    title="My API",
    description="API description (supports Markdown)",
    version="0.1.0",
    openapi_url="/openapi.json",   # None to disable
    docs_url="/docs",              # Swagger UI; None to disable
    redoc_url="/redoc",            # ReDoc UI; None to disable
    root_path="",                  # ASGI root path (behind proxy)
    debug=False,
    lifespan=lifespan,             # async context manager for startup/shutdown
    dependencies=[Depends(verify_token)],  # global dependencies
    middleware=[...],
    exception_handlers={404: not_found_handler},
)
```

### Lifespan (startup / shutdown)

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    app.state.db = await connect_db()
    yield
    # shutdown
    await app.state.db.close()

app = FastAPI(lifespan=lifespan)
```

### Sub-applications & Mounting

```python
app.mount("/static", StaticFiles(directory="static"), name="static")
app.mount("/v1", other_app)                    # mount another ASGI app
```

---

## Routing

### Decorators

```python
@app.get("/items/{id}")
@app.post("/items")
@app.put("/items/{id}")
@app.patch("/items/{id}")
@app.delete("/items/{id}")
@app.head("/items")
@app.options("/items")
@app.trace("/items")

@app.api_route("/items", methods=["GET", "POST"])  # multiple methods
```

### Route Parameters

```python
@app.get(
    "/items/{id}",
    response_model=ItemOut,
    status_code=200,
    tags=["items"],
    summary="Get item",
    description="Long description (Markdown)",
    response_description="Returned item",
    deprecated=False,
    operation_id="get_item",
    include_in_schema=True,
    response_class=JSONResponse,
    name="item_detail",                  # named route
    dependencies=[Depends(rate_limit)],  # route-level dependencies
    responses={
        404: {"description": "Not found"},
        422: {"description": "Validation error"},
    },
)
async def get_item(id: int): ...
```

### `APIRouter`

```python
from fastapi import APIRouter

router = APIRouter(
    prefix="/users",
    tags=["users"],
    dependencies=[Depends(get_current_user)],
    responses={404: {"description": "Not found"}},
)

@router.get("/{id}")
async def get_user(id: int): ...

app.include_router(router)
app.include_router(router, prefix="/api/v1", tags=["v1"])
```

---

## Path, Query & Header Parameters

### Path Parameters

```python
from fastapi import Path

@app.get("/items/{id}")
async def get_item(
    id: int = Path(..., ge=1, le=1000, title="Item ID"),
):
    ...

# Path enum
class ModelName(str, Enum):
    alexnet = "alexnet"
    resnet  = "resnet"

@app.get("/models/{name}")
async def get_model(name: ModelName): ...
```

### Query Parameters

```python
from fastapi import Query

@app.get("/items")
async def list_items(
    q:      str | None = Query(None, min_length=3, max_length=50, pattern=r"^\w+$"),
    skip:   int        = Query(0, ge=0),
    limit:  int        = Query(10, le=100),
    tags:   list[str]  = Query([]),       # ?tags=a&tags=b
):
    ...
```

### Header Parameters

```python
from fastapi import Header

@app.get("/items")
async def get_items(
    user_agent: str | None = Header(None),   # auto-converts User-Agent → user_agent
    x_token:    list[str]  = Header([]),     # duplicate headers as list
):
    ...
```

### Cookie Parameters

```python
from fastapi import Cookie

@app.get("/items")
async def get_items(
    session_id: str | None = Cookie(None),
):
    ...
```

---

## Request Body

### Pydantic Models

```python
from pydantic import BaseModel, Field

class Item(BaseModel):
    name:        str
    price:       float     = Field(..., gt=0, description="Price in USD")
    description: str | None = Field(None, max_length=300)
    tags:        list[str] = []

@app.post("/items", status_code=201)
async def create_item(item: Item): ...

# Nested models
class Order(BaseModel):
    item:     Item
    quantity: int = Field(..., ge=1)
```

### Multiple Body Parameters

```python
from fastapi import Body

@app.put("/items/{id}")
async def update_item(
    id:   int,
    item: Item,
    user: User,                           # second body key
    note: str = Body(None, embed=True),   # embed=True wraps in {"note": ...}
):
    ...
# expects: {"item": {...}, "user": {...}, "note": "..."}
```

### `Body` Field Options

```python
Body(
    default,
    embed=False,      # wrap value under param name key
    media_type="application/json",
    title=None,
    description=None,
    examples={"example1": {"value": {"name": "Foo"}}},
)
```

---

## Form & File Upload

```python
from fastapi import Form, File, UploadFile

# Form fields (requires python-multipart)
@app.post("/login")
async def login(
    username: str = Form(...),
    password: str = Form(...),
):
    ...

# File upload
@app.post("/upload")
async def upload(
    file: UploadFile = File(...),
):
    content  = await file.read()          # bytes
    content  = await file.read(size)      # partial read
    await file.seek(0)
    await file.close()

    file.filename                         # original filename
    file.content_type                     # MIME type
    file.size                             # bytes (if known)
    file.headers                          # Headers

# Multiple files
@app.post("/uploads")
async def multi_upload(files: list[UploadFile] = File(...)): ...

# Mixed form + file
@app.post("/form-file")
async def form_file(
    name: str      = Form(...),
    file: UploadFile = File(...),
):
    ...
```

---

## Request Object

```python
from fastapi import Request

@app.get("/info")
async def info(request: Request):
    request.method           # "GET"
    request.url              # URL object
    request.url.path         # "/info"
    request.url.query        # "foo=bar"
    request.base_url         # base URL
    request.headers          # Headers (case-insensitive)
    request.query_params     # QueryParams
    request.path_params      # dict
    request.cookies          # dict
    request.client           # (host, port) | None
    request.state           # app state carried per-request

    body  = await request.body()          # bytes
    text  = await request.body()          # decode manually
    json  = await request.json()          # Any
    form  = await request.form()          # FormData
    async for chunk in request.stream(): ...
```

---

## Response

### Return Types

```python
# Return dict / Pydantic model directly
@app.get("/items/{id}", response_model=ItemOut)
async def get_item(id: int) -> ItemOut:
    return item                           # auto-serialized

# Explicit Response objects
from fastapi.responses import (
    JSONResponse,
    HTMLResponse,
    PlainTextResponse,
    RedirectResponse,
    StreamingResponse,
    FileResponse,
    Response,
)

return JSONResponse(content={"key": "value"}, status_code=200, headers={...})
return HTMLResponse(content="<h1>Hello</h1>")
return PlainTextResponse(content="hello")
return RedirectResponse(url="/new", status_code=307)
return Response(content=b"raw", media_type="application/octet-stream")

# Streaming
async def gen():
    for chunk in large_data:
        yield chunk

return StreamingResponse(gen(), media_type="text/plain")

# File download
return FileResponse(
    path="report.pdf",
    filename="report.pdf",                # Content-Disposition attachment name
    media_type="application/pdf",
    background=BackgroundTask(cleanup),
)
```

### `Response` Parameter

```python
# Inject Response to set headers/cookies without replacing body
@app.get("/items")
async def get_items(response: Response):
    response.headers["X-Custom"] = "value"
    response.set_cookie("session", "abc", httponly=True, samesite="lax")
    response.delete_cookie("old_cookie")
    response.status_code = 202
    return {"items": [...]}
```

### `response_model` Options

```python
@app.get(
    "/items/{id}",
    response_model=ItemOut,
    response_model_exclude_unset=True,    # omit fields not explicitly set
    response_model_exclude_none=True,     # omit None fields
    response_model_include={"id", "name"},
    response_model_exclude={"password"},
)
```

---

## Dependencies — `Depends`

```python
from fastapi import Depends

# Simple dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/items")
async def list_items(db: Session = Depends(get_db)): ...

# Async dependency
async def verify_token(x_token: str = Header(...)) -> User:
    user = await db.get_user_by_token(x_token)
    if not user:
        raise HTTPException(403)
    return user

# Dependency with dependency
def paginate(skip: int = 0, limit: int = 10):
    return {"skip": skip, "limit": limit}

@app.get("/items")
async def list_items(
    page: dict = Depends(paginate),
    user: User = Depends(verify_token),
): ...

# Class-based dependency
class CommonParams:
    def __init__(self, q: str | None = None, skip: int = 0, limit: int = 100):
        self.q     = q
        self.skip  = skip
        self.limit = limit

@app.get("/items")
async def list_items(params: CommonParams = Depends()): ...

# use_cache=False — call dependency once per request (default True)
Depends(get_db, use_cache=False)
```

---

## Exception Handling

### `HTTPException`

```python
from fastapi import HTTPException

raise HTTPException(
    status_code=404,
    detail="Item not found",
    headers={"X-Error": "true"},
)
```

### Custom Exception Handlers

```python
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

@app.exception_handler(404)
async def not_found(request: Request, exc: HTTPException):
    return JSONResponse({"error": exc.detail}, status_code=404)

@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    return JSONResponse({"detail": exc.errors()}, status_code=422)

@app.exception_handler(MyCustomError)
async def custom_error(request: Request, exc: MyCustomError):
    return JSONResponse({"msg": str(exc)}, status_code=400)
```

---

## Middleware

```python
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from starlette.middleware.sessions import SessionMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://example.com"],  # ["*"] for all
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["example.com", "*.example.com"])
app.add_middleware(HTTPSRedirectMiddleware)
app.add_middleware(SessionMiddleware, secret_key="secret")

# Custom middleware
from starlette.middleware.base import BaseHTTPMiddleware

class TimingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.time()
        response = await call_next(request)
        response.headers["X-Process-Time"] = str(time.time() - start)
        return response

app.add_middleware(TimingMiddleware)
```

---

## Background Tasks

```python
from fastapi import BackgroundTask, BackgroundTasks

# Via BackgroundTasks parameter
@app.post("/send")
async def send(bg: BackgroundTasks):
    bg.add_task(send_email, "user@example.com", subject="Hello")
    bg.add_task(log_event, "send", extra="data")
    return {"status": "queued"}

# Via Response
return FileResponse("file.zip", background=BackgroundTask(cleanup, path))
```

---

## Security

### OAuth2 / Bearer

```python
from fastapi.security import (
    OAuth2PasswordBearer,
    OAuth2PasswordRequestForm,
    HTTPBearer,
    HTTPBasic,
    HTTPBasicCredentials,
    APIKeyHeader,
    APIKeyQuery,
    APIKeyCookie,
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

@app.get("/me")
async def me(token: str = Depends(oauth2_scheme)): ...

@app.post("/token")
async def login(form: OAuth2PasswordRequestForm = Depends()):
    form.username
    form.password
    form.scopes    # list[str]
    return {"access_token": create_jwt(form.username), "token_type": "bearer"}
```

### HTTP Basic / Bearer / API Key

```python
security = HTTPBearer(auto_error=True)

@app.get("/secure")
async def secure(creds: HTTPAuthorizationCredentials = Depends(security)):
    creds.scheme       # "Bearer"
    creds.credentials  # token string

basic = HTTPBasic()

@app.get("/basic")
async def basic_auth(creds: HTTPBasicCredentials = Depends(basic)):
    creds.username
    creds.password

api_key = APIKeyHeader(name="X-API-Key", auto_error=True)

@app.get("/protected")
async def protected(key: str = Depends(api_key)): ...
```

---

## WebSocket

```python
from fastapi import WebSocket, WebSocketDisconnect

@app.websocket("/ws/{client_id}")
async def ws_endpoint(websocket: WebSocket, client_id: int):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()     # str
            data = await websocket.receive_bytes()    # bytes
            data = await websocket.receive_json()     # Any

            await websocket.send_text("reply")
            await websocket.send_bytes(b"data")
            await websocket.send_json({"msg": "ok"})
    except WebSocketDisconnect as e:
        e.code      # close code
        e.reason    # str

    await websocket.close(code=1000, reason="done")

    websocket.url
    websocket.headers
    websocket.query_params
    websocket.path_params
    websocket.cookies
    websocket.client       # (host, port)
    websocket.state
```

---

## Pydantic Integration

### Field Validation

```python
from pydantic import BaseModel, Field, field_validator, model_validator

class Item(BaseModel):
    id:    int    = Field(..., ge=1)
    name:  str    = Field(..., min_length=1, max_length=100)
    price: float  = Field(..., gt=0)
    tags:  list[str] = Field(default_factory=list)

    @field_validator("name")
    @classmethod
    def name_must_not_be_empty(cls, v):
        if not v.strip():
            raise ValueError("name must not be blank")
        return v.strip()

    @model_validator(mode="after")
    def check_consistency(self):
        if self.price > 1000 and not self.tags:
            raise ValueError("expensive items must have tags")
        return self

    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",           # reject unknown fields
        populate_by_name=True,
    )
```

### JSON Schema Customization

```python
class Item(BaseModel):
    name: str

    model_config = ConfigDict(
        json_schema_extra={"examples": [{"name": "Widget"}]},
    )
```

---

## Running & Deployment

```python
# Development
import uvicorn

uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True, workers=1)

# Production
uvicorn.run(
    "main:app",
    host="0.0.0.0",
    port=8000,
    workers=4,
    log_level="info",
    access_log=True,
    ssl_keyfile="key.pem",
    ssl_certfile="cert.pem",
    loop="uvloop",
    http="httptools",
)

# Gunicorn + Uvicorn workers
# gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

---

## Testing

```python
from fastapi.testclient import TestClient

client = TestClient(app, base_url="http://test", raise_server_exceptions=True)

response = client.get("/items/1")
response = client.post("/items", json={"name": "foo", "price": 1.5})
response = client.put("/items/1", json={...})
response = client.delete("/items/1")
response = client.get("/items", params={"q": "foo", "limit": 5})
response = client.get("/secure", headers={"Authorization": "Bearer token"})
response = client.post("/upload", files={"file": ("name.txt", b"content", "text/plain")})
response = client.post("/login", data={"username": "u", "password": "p"})

response.status_code       # int
response.json()            # Any
response.text              # str
response.headers           # dict

# WebSocket test
with client.websocket_connect("/ws/1") as ws:
    ws.send_text("hello")
    data = ws.receive_text()
    ws.send_json({"key": "val"})
    data = ws.receive_json()
    ws.close()

# Async test (pytest-asyncio + httpx)
from httpx import AsyncClient

async def test_items():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        resp = await ac.get("/items")
        assert resp.status_code == 200
```

---

## Common Patterns

```python
# Paginated list response
class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    skip:  int
    limit: int

@app.get("/items", response_model=Page[ItemOut])
async def list_items(skip: int = 0, limit: int = 10, db: Session = Depends(get_db)):
    items = db.query(Item).offset(skip).limit(limit).all()
    return Page(items=items, total=db.query(Item).count(), skip=skip, limit=limit)

# Global 404 / error response model
@app.exception_handler(404)
async def not_found(request, exc):
    return JSONResponse({"detail": "not found"}, status_code=404)

# Versioned router
v1 = APIRouter(prefix="/api/v1")
v2 = APIRouter(prefix="/api/v2")
app.include_router(v1)
app.include_router(v2)

# Dependency override in tests
app.dependency_overrides[get_db] = lambda: fake_db
app.dependency_overrides.clear()

# Access app state
@app.get("/health")
async def health(request: Request):
    return {"db": request.app.state.db is not None}

# Rate limiting via dependency
async def rate_limit(request: Request):
    key = request.client.host
    if await redis.incr(key) > 100:
        raise HTTPException(429, "rate limit exceeded")
    await redis.expire(key, 60)
```
