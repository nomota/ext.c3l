# Fiber API Reference (Go)

## Application

### `fiber.New`

```go
import "github.com/gofiber/fiber/v2"

app := fiber.New(fiber.Config{
    Prefork:                 false,          // spawn multiple processes (SO_REUSEPORT)
    ServerHeader:            "",             // Server header value
    StrictRouting:           false,          // /foo != /foo/
    CaseSensitive:           false,          // /Foo == /foo
    Immutable:               false,          // make ctx values immutable
    UnescapePath:            false,          // unescape path before matching
    ETag:                    false,          // auto ETag generation
    BodyLimit:               4 * 1024 * 1024, // max request body (bytes)
    Concurrency:             256 * 1024,     // max concurrent connections
    ReadTimeout:             0,              // time.Duration; 0 = no timeout
    WriteTimeout:            0,
    IdleTimeout:             0,
    ReadBufferSize:          4096,
    WriteBufferSize:         4096,
    CompressedFileSuffix:    ".fiber.gz",
    ProxyHeader:             "",             // e.g. "X-Forwarded-For"
    GETOnly:                 false,
    ErrorHandler:            DefaultErrorHandler,
    DisableKeepalive:        false,
    DisableDefaultDate:      false,
    DisableDefaultContentType: false,
    DisableHeaderNormalizing: false,
    DisableStartupMessage:   false,
    AppName:                 "MyApp v1.0.0",
    StreamRequestBody:       false,
    EnableTrustedProxyCheck: false,
    TrustedProxies:          []string{"127.0.0.1", "10.0.0.0/8"},
    EnableIPValidation:      false,
    EnablePrintRoutes:       false,
    ColorScheme:             fiber.DefaultColors,
    RequestMethods:          []string{"GET","POST","PUT","DELETE","PATCH","HEAD","OPTIONS"},
    JSONEncoder:             json.Marshal,   // custom JSON encoder
    JSONDecoder:             json.Unmarshal, // custom JSON decoder
    XMLEncoder:              xml.Marshal,
    Network:                 fiber.NetworkTCP4,  // | NetworkTCP | NetworkTCP6
})
```

### Running

```go
// Plain HTTP
app.Listen(":8080")
app.Listen("0.0.0.0:8080")

// TLS
app.ListenTLS(":443", "cert.pem", "key.pem")

// Mutual TLS
app.ListenMutualTLS(":443", "cert.pem", "key.pem", "ca.pem")

// Custom listener
ln, _ := net.Listen("tcp", ":8080")
app.Listener(ln)

// Graceful shutdown
go func() {
    if err := app.Listen(":8080"); err != nil {
        log.Fatal(err)
    }
}()

quit := make(chan os.Signal, 1)
signal.Notify(quit, os.Interrupt)
<-quit
app.Shutdown()               // wait for in-flight requests
app.ShutdownWithTimeout(5 * time.Second)
app.ShutdownWithContext(ctx)
```

---

## Routing

### HTTP Methods

```go
app.Get("/items",          handler)
app.Post("/items",         handler)
app.Put("/items/:id",      handler)
app.Patch("/items/:id",    handler)
app.Delete("/items/:id",   handler)
app.Head("/items",         handler)
app.Options("/items",      handler)
app.Connect("/items",      handler)
app.Trace("/items",        handler)

app.All("/items", handler)              // all HTTP methods
app.Add("GET", "/items", handler)       // explicit method string

// Named route (chainable)
app.Get("/items", handler).Name("item_list")
app.GetRoute("item_list")               // *Route
```

### Route Parameters

```go
// Named parameter
app.Get("/items/:id", func(c *fiber.Ctx) error {
    id := c.Params("id")              // string
    return c.JSON(fiber.Map{"id": id})
})

// Optional parameter
app.Get("/items/:id?", handler)

// Wildcard / greedy
app.Get("/files/*",  handler)         // c.Params("*")  — everything after /files/
app.Get("/files/*1", handler)         // named wildcard

// Regex constraint
app.Get(`/items/:id<\d+>`, handler)   // digits only

// Multiple params
app.Get("/users/:uid/posts/:pid", func(c *fiber.Ctx) error {
    uid := c.Params("uid")
    pid := c.Params("pid")
    ...
})
```

### Grouping

```go
v1 := app.Group("/api/v1")
v1.Get("/items", handler)
v1.Post("/items", handler)

auth := app.Group("/admin", authMiddleware)
auth.Get("/users", listUsers)

// Group with middleware
api := app.Group("/api", cors(), logger())
api.Get("/items", handler)
```

### Static Files

```go
app.Static("/static", "./public")
app.Static("/", "./public/index.html")
app.Static(
    "/static",
    "./public",
    fiber.Static{
        Compress:      true,
        ByteRange:     true,            // Range header support
        Browse:        false,           // directory listing
        Index:         "index.html",
        CacheDuration: 10 * time.Second,
        MaxAge:        3600,            // Cache-Control max-age
    },
)
```

### URL Building

```go
url, err := app.GetRoute("item_detail").URL("id", "1")  // "/items/1"

// c.GetRouteURL inside handler
url, err := c.GetRouteURL("item_detail", fiber.Map{"id": 1})
```

---

## Handler & Middleware

### Handler Signature

```go
type Handler func(*fiber.Ctx) error

// Multiple handlers per route (middleware chain)
app.Get("/items", authMiddleware, cacheMiddleware, getItems)
```

### Middleware Registration

```go
// Global
app.Use(logger.New())
app.Use(recover.New())
app.Use(cors.New())

// Path-prefixed
app.Use("/api", authMiddleware)

// Multiple middlewares
app.Use(middlewareA, middlewareB)
```

---

## `fiber.Ctx`

### Request

```go
// Method & URL
c.Method()              // "GET"
c.Path()                // "/items/1"
c.OriginalURL()         // "/items/1?q=foo"
c.BaseURL()             // "http://example.com"
c.Hostname()            // "example.com"
c.Port()                // "8080"
c.Protocol()            // "http" | "https"
c.Secure()              // bool
c.IsFromLocal()         // bool

// Client IP
c.IP()                  // string — respects ProxyHeader if set
c.IPs()                 // []string — all IPs in X-Forwarded-For

// Path params
c.Params("id")                       // string
c.ParamsInt("id")                    // (int, error)
c.ParamsParser(&struct)              // bind all path params to struct

// Query params
c.Query("q")                         // string
c.Query("page", "1")                 // with default
c.QueryInt("page", 1)                // (int, error) with default
c.QueryBool("active")                // (bool, error)
c.QueryFloat("score")                // (float64, error)
c.QueryParser(&struct)               // bind all query params to struct

// Headers
c.Get("Content-Type")               // string — header value
c.Get("X-Token", "default")
c.GetReqHeaders()                    // map[string][]string

// Cookies
c.Cookies("session")                 // string
c.Cookies("session", "default")

// Body
c.Body()                             // []byte — raw body
c.BodyRaw()                          // []byte (alias)
c.BodyParser(&v)                     // decode body by Content-Type into struct
c.JSONParser(&v)                     // force JSON decode
c.XMLParser(&v)                      // force XML decode

// Multipart / Form
c.FormValue("field")                 // string
c.FormFile("upload")                 // (*multipart.FileHeader, error)
c.MultipartForm()                    // (*multipart.Form, error)
f, _ := c.FormFile("file")
c.SaveFile(f, "./uploads/"+f.Filename)

// Request metadata
c.Is("json")                         // bool — Content-Type check
c.Accepts("application/json")        // string — best match | ""
c.AcceptsCharsets("utf-8")
c.AcceptsEncodings("gzip")
c.AcceptsLanguages("en")
c.Protocol()                         // "http" | "https"
c.XHR()                             // bool — X-Requested-With: XMLHttpRequest

// Locals (per-request key-value store)
c.Locals("user", userObj)            // set
c.Locals("user").(User)             // get (type assert)
```

### Response

```go
// Status
c.Status(fiber.StatusOK)             // *Ctx — chainable
c.Status(200).JSON(data)

// Body
c.Send([]byte("hello"))              // []byte
c.SendString("hello")                // string
c.SendStream(reader)                 // io.Reader
c.SendStream(reader, size)           // with Content-Length
c.WriteString("partial")             // write without ending
c.Write([]byte("partial"))

// JSON / XML
c.JSON(fiber.Map{"key": "value"})
c.JSON(struct)
c.JSONP(data)                        // JSONP with callback
c.JSONP(data, "cb")                  // custom callback name
c.XML(struct)

// Template
c.Render("index", fiber.Map{"Title": "Hello"})
c.Render("index", data, "layouts/main")  // with layout

// File
c.SendFile("./static/file.pdf")
c.SendFile("./file.pdf", true)       // true = use FS cache
c.Download("./file.pdf")             // as attachment (Content-Disposition)
c.Download("./file.pdf", "report.pdf")

// Redirect
c.Redirect("/new-path")              // 302
c.Redirect("/new-path", 301)
c.RedirectBack("/fallback")          // redirect to Referer

// Headers
c.Set("X-Custom", "value")
c.Append("Vary", "Accept-Encoding")
c.Set(fiber.HeaderContentType, fiber.MIMEApplicationJSON)
c.Type("pdf")                        // sets Content-Type from extension
c.Type("json", "utf-8")
c.Vary("Accept", "Accept-Encoding")

// Cookies
c.Cookie(&fiber.Cookie{
    Name:     "session",
    Value:    "abc123",
    Path:     "/",
    Domain:   "example.com",
    MaxAge:   3600,
    Expires:  time.Now().Add(24 * time.Hour),
    Secure:   true,
    HTTPOnly: true,
    SameSite: "Lax",                 // "Strict" | "Lax" | "None"
})
c.ClearCookie("session")
c.ClearCookie()                      // clear all cookies

// Format (content negotiation)
c.Format(fiber.Map{
    "text/plain":       func() error { return c.SendString("hello") },
    "application/json": func() error { return c.JSON(data) },
    "text/html":        func() error { return c.SendString("<h1>hello</h1>") },
})
```

### Context Utilities

```go
c.Next()                             // error — call next handler in chain
c.RestartRouting()                   // re-run routing from the start

c.App()                              // *fiber.App
c.Route()                            // *fiber.Route — matched route
c.Fresh()                            // bool — 304 Not Modified check
c.Stale()                            // bool — opposite of Fresh

// Request context (for DB calls, etc.)
c.Context()                          // *fasthttp.RequestCtx
c.UserContext()                      // context.Context
c.SetUserContext(ctx)                // set context.Context

c.GetRespHeader("Content-Type")
c.GetRespHeaders()                   // map[string][]string

// Attachment
c.Attachment()                       // Content-Disposition: attachment
c.Attachment("report.pdf")           // with filename

// Links header
c.Links("http://example.com/page/2", "next",
        "http://example.com/page/5", "last")
```

---

## Error Handling

```go
// Return error from handler
app.Get("/items/:id", func(c *fiber.Ctx) error {
    id, err := c.ParamsInt("id")
    if err != nil {
        return fiber.NewError(fiber.StatusBadRequest, "invalid id")
    }
    item, err := db.GetItem(id)
    if err != nil {
        return fiber.NewError(fiber.StatusNotFound, "item not found")
    }
    return c.JSON(item)
})

// fiber.Error
type fiber.Error struct {
    Code    int
    Message string
}

err := fiber.NewError(404, "not found")
err.Error()   // "not found"

// Global error handler
app := fiber.New(fiber.Config{
    ErrorHandler: func(c *fiber.Ctx, err error) error {
        code := fiber.StatusInternalServerError
        var e *fiber.Error
        if errors.As(err, &e) {
            code = e.Code
        }
        return c.Status(code).JSON(fiber.Map{
            "error": err.Error(),
        })
    },
})

// Common fiber status errors
fiber.ErrBadRequest                  // 400
fiber.ErrUnauthorized                // 401
fiber.ErrPaymentRequired             // 402
fiber.ErrForbidden                   // 403
fiber.ErrNotFound                    // 404
fiber.ErrMethodNotAllowed            // 405
fiber.ErrRequestTimeout              // 408
fiber.ErrConflict                    // 409
fiber.ErrGone                        // 410
fiber.ErrUnprocessableEntity         // 422
fiber.ErrTooManyRequests             // 429
fiber.ErrInternalServerError         // 500
fiber.ErrNotImplemented              // 501
fiber.ErrBadGateway                  // 502
fiber.ErrServiceUnavailable          // 503
```

---

## Middleware (Built-in)

```go
import (
    "github.com/gofiber/fiber/v2/middleware/basicauth"
    "github.com/gofiber/fiber/v2/middleware/cache"
    "github.com/gofiber/fiber/v2/middleware/compress"
    "github.com/gofiber/fiber/v2/middleware/cors"
    "github.com/gofiber/fiber/v2/middleware/csrf"
    "github.com/gofiber/fiber/v2/middleware/encryptcookie"
    "github.com/gofiber/fiber/v2/middleware/etag"
    "github.com/gofiber/fiber/v2/middleware/favicon"
    "github.com/gofiber/fiber/v2/middleware/idempotency"
    "github.com/gofiber/fiber/v2/middleware/keyauth"
    "github.com/gofiber/fiber/v2/middleware/limiter"
    "github.com/gofiber/fiber/v2/middleware/logger"
    "github.com/gofiber/fiber/v2/middleware/monitor"
    "github.com/gofiber/fiber/v2/middleware/proxy"
    "github.com/gofiber/fiber/v2/middleware/recover"
    "github.com/gofiber/fiber/v2/middleware/requestid"
    "github.com/gofiber/fiber/v2/middleware/session"
    "github.com/gofiber/fiber/v2/middleware/skip"
    "github.com/gofiber/fiber/v2/middleware/timeout"
)

// Logger
app.Use(logger.New(logger.Config{
    Format:     "${time} ${method} ${path} ${status} ${latency}\n",
    TimeFormat: "2006-01-02 15:04:05",
    TimeZone:   "UTC",
    Output:     os.Stdout,
}))

// Recover (panic recovery)
app.Use(recover.New(recover.Config{
    EnableStackTrace: true,
}))

// CORS
app.Use(cors.New(cors.Config{
    AllowOrigins:     "https://example.com, https://app.example.com",
    AllowMethods:     "GET,POST,PUT,DELETE,OPTIONS",
    AllowHeaders:     "Authorization, Content-Type",
    AllowCredentials: true,
    ExposeHeaders:    "X-Custom",
    MaxAge:           86400,
}))

// Rate Limiter
app.Use(limiter.New(limiter.Config{
    Max:        100,
    Expiration: 1 * time.Minute,
    KeyGenerator: func(c *fiber.Ctx) string {
        return c.IP()
    },
    LimitReached: func(c *fiber.Ctx) error {
        return c.Status(429).JSON(fiber.Map{"error": "rate limit exceeded"})
    },
    Storage: redisStorage,           // optional persistent storage
}))

// Cache
app.Use(cache.New(cache.Config{
    Next:         func(c *fiber.Ctx) bool { return c.Query("refresh") == "true" },
    Expiration:   30 * time.Minute,
    CacheControl: true,
    KeyGenerator: func(c *fiber.Ctx) string { return c.Path() },
    Storage:      redisStorage,
}))

// Compress
app.Use(compress.New(compress.Config{
    Level: compress.LevelBestSpeed,  // | LevelBestCompression | LevelDefault
}))

// Session
store := session.New(session.Config{
    Expiration:     24 * time.Hour,
    KeyLookup:      "cookie:session_id",
    CookieSameSite: "Lax",
    CookieSecure:   true,
    CookieHTTPOnly: true,
    Storage:        redisStorage,
})

app.Get("/set", func(c *fiber.Ctx) error {
    sess, _ := store.Get(c)
    sess.Set("user_id", 42)
    sess.Save()
    return c.SendString("ok")
})

app.Get("/get", func(c *fiber.Ctx) error {
    sess, _ := store.Get(c)
    userID := sess.Get("user_id")
    sess.Delete("user_id")
    sess.Destroy()               // invalidate session
    return c.JSON(fiber.Map{"user_id": userID})
})

// JWT (via gofiber/contrib)
// import "github.com/gofiber/contrib/jwt"
app.Use(jwtware.New(jwtware.Config{
    SigningKey:     jwtware.SigningKey{Key: []byte("secret")},
    TokenLookup:   "header:Authorization",
    AuthScheme:    "Bearer",
    ErrorHandler:  func(c *fiber.Ctx, err error) error {
        return c.Status(401).JSON(fiber.Map{"error": "unauthorized"})
    },
}))

// Request ID
app.Use(requestid.New(requestid.Config{
    Header:     "X-Request-ID",
    Generator:  func() string { return uuid.New().String() },
}))

// Timeout
app.Use(timeout.NewWithContext(func(c *fiber.Ctx) error {
    return someSlowHandler(c)
}, 5*time.Second))

// Basic Auth
app.Use(basicauth.New(basicauth.Config{
    Users: map[string]string{
        "admin": "password",
    },
    Realm: "Restricted",
    Authorizer: func(user, pass string) bool {
        return user == "admin" && subtle.ConstantTimeCompare([]byte(pass), []byte("secret")) == 1
    },
}))

// Proxy
app.Use("/api", proxy.Balancer(proxy.Config{
    Servers: []string{
        "http://backend1:8080",
        "http://backend2:8080",
    },
    ModifyRequest: func(c *fiber.Ctx) error {
        c.Request().Header.Add("X-Real-IP", c.IP())
        return nil
    },
}))

// ETag
app.Use(etag.New())

// Favicon
app.Use(favicon.New(favicon.Config{
    File: "./public/favicon.ico",
}))

// Monitor (metrics dashboard at /metrics)
app.Get("/metrics", monitor.New())

// Skip middleware conditionally
app.Use(skip.New(authMiddleware, func(c *fiber.Ctx) bool {
    return c.Path() == "/healthz"
}))

// Encrypt cookie
app.Use(encryptcookie.New(encryptcookie.Config{
    Key: "32-byte-long-secret-key-here!!",
}))
```

---

## `fiber.Map` & Helpers

```go
fiber.Map{"key": "value"}            // alias for map[string]interface{}

// Status code constants
fiber.StatusOK                       // 200
fiber.StatusCreated                  // 201
fiber.StatusNoContent                // 204
fiber.StatusBadRequest               // 400
fiber.StatusUnauthorized             // 401
fiber.StatusForbidden                // 403
fiber.StatusNotFound                 // 404
fiber.StatusUnprocessableEntity      // 422
fiber.StatusTooManyRequests          // 429
fiber.StatusInternalServerError      // 500

// MIME type constants
fiber.MIMEApplicationJSON            // "application/json"
fiber.MIMEApplicationXML             // "application/xml"
fiber.MIMETextPlain                  // "text/plain"
fiber.MIMETextHTML                   // "text/html"
fiber.MIMEOctetStream                // "application/octet-stream"
fiber.MIMEMultipartForm              // "multipart/form-data"
fiber.MIMEApplicationForm            // "application/x-www-form-urlencoded"

// Header constants
fiber.HeaderAuthorization
fiber.HeaderContentType
fiber.HeaderContentLength
fiber.HeaderAccept
fiber.HeaderCacheControl
fiber.HeaderXRequestID
```

---

## Binding / Validation

```go
// BodyParser binds by Content-Type
type CreateItem struct {
    Name  string  `json:"name"  xml:"name"  form:"name"`
    Price float64 `json:"price" xml:"price" form:"price"`
}

app.Post("/items", func(c *fiber.Ctx) error {
    var body CreateItem
    if err := c.BodyParser(&body); err != nil {
        return fiber.NewError(fiber.StatusBadRequest, err.Error())
    }
    // validate with go-playground/validator
    if err := validate.Struct(body); err != nil {
        return fiber.NewError(fiber.StatusUnprocessableEntity, err.Error())
    }
    return c.Status(201).JSON(body)
})

// QueryParser
type ListParams struct {
    Page  int    `query:"page"`
    Limit int    `query:"limit"`
    Q     string `query:"q"`
}

app.Get("/items", func(c *fiber.Ctx) error {
    var p ListParams
    if err := c.QueryParser(&p); err != nil {
        return err
    }
    return c.JSON(p)
})

// ParamsParser
type PathParams struct {
    ID int `params:"id"`
}

app.Get("/items/:id", func(c *fiber.Ctx) error {
    var p PathParams
    c.ParamsParser(&p)
    return c.JSON(p)
})

// ReqHeaderParser
type HeaderParams struct {
    Token string `reqHeader:"Authorization"`
}

c.ReqHeaderParser(&headerParams)
```

---

## WebSocket

```go
import "github.com/gofiber/contrib/websocket"

app.Get("/ws", websocket.New(func(c *websocket.Conn) {
    // Send
    c.WriteMessage(websocket.TextMessage, []byte("hello"))
    c.WriteMessage(websocket.BinaryMessage, []byte{0x00})
    c.WriteJSON(fiber.Map{"event": "connected"})

    // Receive loop
    for {
        mt, msg, err := c.ReadMessage()
        if err != nil {
            break                            // client disconnected
        }
        switch mt {
        case websocket.TextMessage:
            c.WriteMessage(websocket.TextMessage, msg)
        case websocket.BinaryMessage:
            c.WriteMessage(websocket.BinaryMessage, msg)
        }
    }

    // Close
    c.WriteMessage(websocket.CloseMessage,
        websocket.FormatCloseMessage(websocket.CloseNormalClosure, "bye"))

    c.Conn                                   // *gorilla/websocket.Conn
    c.Locals("user")                         // access Locals set before upgrade
    c.Params("id")                           // path params
    c.Query("token")                         // query params
    c.Headers("Authorization")              // request headers

}, websocket.Config{
    HandshakeTimeout: 10 * time.Second,
    ReadBufferSize:   1024,
    WriteBufferSize:  1024,
    Origins:          []string{"https://example.com"},
}))

// Middleware before upgrade
app.Use("/ws", func(c *fiber.Ctx) error {
    if c.Get("Authorization") == "" {
        return fiber.ErrUnauthorized
    }
    c.Locals("user", getUser(c))
    return c.Next()
})
```

---

## Server-Sent Events

```go
app.Get("/sse", func(c *fiber.Ctx) error {
    c.Set("Content-Type", "text/event-stream")
    c.Set("Cache-Control", "no-cache")
    c.Set("Connection", "keep-alive")
    c.Set("Transfer-Encoding", "chunked")

    c.Context().SetBodyStreamWriter(fasthttp.StreamWriter(func(w *bufio.Writer) {
        for i := 0; i < 10; i++ {
            fmt.Fprintf(w, "id: %d\n", i)
            fmt.Fprintf(w, "event: update\n")
            fmt.Fprintf(w, "data: %s\n\n", payload)
            w.Flush()
            time.Sleep(time.Second)
        }
    }))
    return nil
})
```

---

## Testing

```go
import (
    "testing"
    "net/http/httptest"
    "github.com/gofiber/fiber/v2"
)

func TestGetItem(t *testing.T) {
    app := fiber.New()
    app.Get("/items/:id", getItemHandler)

    // Create test request
    req := httptest.NewRequest("GET", "/items/1", nil)
    req.Header.Set("Authorization", "Bearer token")

    // Execute
    resp, err := app.Test(req)                    // default timeout: 1s
    resp, err  = app.Test(req, 5000)              // custom timeout (ms); -1 = no timeout

    // Assertions
    if resp.StatusCode != 200 {
        t.Errorf("expected 200 got %d", resp.StatusCode)
    }

    body, _ := io.ReadAll(resp.Body)
    resp.Body.Close()

    var result map[string]any
    json.Unmarshal(body, &result)
}

// POST with body
body := strings.NewReader(`{"name":"foo","price":9.99}`)
req  := httptest.NewRequest("POST", "/items", body)
req.Header.Set("Content-Type", "application/json")
resp, _ := app.Test(req)

// POST multipart form
var buf bytes.Buffer
w := multipart.NewWriter(&buf)
w.WriteField("name", "foo")
fw, _ := w.CreateFormFile("file", "test.txt")
fw.Write([]byte("content"))
w.Close()
req = httptest.NewRequest("POST", "/upload", &buf)
req.Header.Set("Content-Type", w.FormDataContentType())
resp, _ = app.Test(req)

// Using testify
import "github.com/stretchr/testify/assert"

assert.Equal(t, 200, resp.StatusCode)
assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))
```

---

## Common Patterns

```go
// Dependency injection via Locals in middleware
func AuthMiddleware(db *DB) fiber.Handler {
    return func(c *fiber.Ctx) error {
        token := c.Get("Authorization")
        user, err := db.GetUserByToken(token)
        if err != nil {
            return fiber.ErrUnauthorized
        }
        c.Locals("user", user)
        return c.Next()
    }
}

app.Use(AuthMiddleware(db))

app.Get("/me", func(c *fiber.Ctx) error {
    user := c.Locals("user").(*User)
    return c.JSON(user)
})

// Pagination helper
type PageParams struct {
    Page  int `query:"page"`
    Limit int `query:"limit"`
}

func (p *PageParams) Offset() int {
    if p.Page < 1 { p.Page = 1 }
    if p.Limit < 1 { p.Limit = 20 }
    return (p.Page - 1) * p.Limit
}

// Struct-based route handler (controller pattern)
type ItemController struct {
    db    *DB
    cache *Cache
}

func (h *ItemController) Register(app *fiber.App) {
    g := app.Group("/items")
    g.Get("/",    h.List)
    g.Post("/",   h.Create)
    g.Get("/:id", h.Get)
    g.Put("/:id", h.Update)
    g.Delete("/:id", h.Delete)
}

func (h *ItemController) List(c *fiber.Ctx) error {
    var p PageParams
    c.QueryParser(&p)
    items, err := h.db.ListItems(p.Offset(), p.Limit)
    if err != nil {
        return err
    }
    return c.JSON(items)
}

// Generic JSON error response
func JSONError(c *fiber.Ctx, status int, msg string) error {
    return c.Status(status).JSON(fiber.Map{"error": msg})
}

// Recover with custom logging
app.Use(recover.New(recover.Config{
    EnableStackTrace: true,
    StackTraceHandler: func(c *fiber.Ctx, e interface{}) {
        log.Printf("panic: %v\n%s", e, debug.Stack())
    },
}))

// Health check
app.Get("/healthz", func(c *fiber.Ctx) error {
    return c.JSON(fiber.Map{"status": "ok"})
})

// Streaming response
app.Get("/stream", func(c *fiber.Ctx) error {
    c.Set(fiber.HeaderContentType, "text/plain")
    c.Context().SetBodyStreamWriter(fasthttp.StreamWriter(func(w *bufio.Writer) {
        for i := 0; i < 100; i++ {
            fmt.Fprintf(w, "line %d\n", i)
            w.Flush()
        }
    }))
    return nil
})

// Versioned router
func SetupRoutes(app *fiber.App) {
    api := app.Group("/api")

    v1 := api.Group("/v1")
    v1.Get("/items", v1ListItems)

    v2 := api.Group("/v2")
    v2.Get("/items", v2ListItems)
}
```
