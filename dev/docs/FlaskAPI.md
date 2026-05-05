# Flask API Reference

## Application

### `Flask`

```python
from flask import Flask

app = Flask(
    import_name,                  # typically __name__
    static_url_path=None,         # URL prefix for static files (default: /static)
    static_folder="static",       # filesystem path to static files
    static_host=None,
    host_matching=False,          # enable host-based routing
    subdomain_matching=False,
    template_folder="templates",
    instance_path=None,           # override instance folder path
    instance_relative_config=False,
    root_path=None,
)
```

### Configuration

```python
# Direct assignment
app.config["DEBUG"]              = True
app.config["SECRET_KEY"]         = "changeme"
app.config["TESTING"]            = False

# Bulk update
app.config.from_object("myapp.config.ProductionConfig")
app.config.from_pyfile("config.py", silent=False)
app.config.from_envvar("APP_CONFIG_FILE")
app.config.from_mapping({"KEY": "value"})
app.config.from_prefixed_env(prefix="FLASK")   # reads FLASK_* env vars

# Common built-in keys
app.config["DEBUG"]                      # bool
app.config["TESTING"]                    # bool
app.config["SECRET_KEY"]                 # str — required for sessions/signing
app.config["SESSION_COOKIE_NAME"]        # str
app.config["SESSION_COOKIE_SECURE"]      # bool
app.config["SESSION_COOKIE_HTTPONLY"]    # bool
app.config["SESSION_COOKIE_SAMESITE"]    # "Lax" | "Strict" | "None"
app.config["PERMANENT_SESSION_LIFETIME"] # timedelta
app.config["MAX_CONTENT_LENGTH"]         # int (bytes) — max request body
app.config["SEND_FILE_MAX_AGE_DEFAULT"]  # timedelta
app.config["JSON_SORT_KEYS"]             # bool
app.config["JSONIFY_PRETTYPRINT_REGULAR"] # bool
app.config["TEMPLATES_AUTO_RELOAD"]      # bool
app.config["SERVER_NAME"]                # "host:port" — for url_for with _external
app.config["APPLICATION_ROOT"]           # str — URL prefix
app.config["PREFERRED_URL_SCHEME"]       # "http" | "https"
```

### Application Context & State

```python
from flask import g, current_app

# g — per-request global storage (reset each request)
g.user    = user
g.db      = db_conn

# current_app — proxy to the active Flask app
current_app.config["SECRET_KEY"]
current_app.logger.info("message")
current_app.extensions        # dict of registered extensions

# App context (outside request context)
with app.app_context():
    db.create_all()
    current_app.config["DEBUG"]
```

---

## Running

```python
# Development
app.run(
    host="0.0.0.0",
    port=5000,
    debug=True,
    use_reloader=True,
    use_debugger=True,
    threaded=True,
    processes=1,
    ssl_context=None,          # "adhoc" | (cert, key) | ssl.SSLContext
    extra_files=None,          # additional files to watch for reloader
)

# CLI (preferred)
# flask --app myapp run --host 0.0.0.0 --port 5000 --debug
# flask --app myapp:create_app() run

# Production — use a WSGI server
# gunicorn "myapp:create_app()" -w 4 -b 0.0.0.0:8000
# uwsgi --http 0.0.0.0:8000 --module myapp:app
```

### Application Factory

```python
def create_app(config=None):
    app = Flask(__name__)
    app.config.from_object("config.DefaultConfig")
    if config:
        app.config.from_mapping(config)

    from .models import db
    db.init_app(app)

    from .routes import bp
    app.register_blueprint(bp)

    return app
```

---

## Routing

### Decorators

```python
@app.route("/items", methods=["GET"])
@app.route("/items", methods=["POST"])
@app.route("/items/<int:id>", methods=["GET", "PUT", "DELETE"])

# Shorthand (Flask 2.0+)
@app.get("/items")
@app.post("/items")
@app.put("/items/<int:id>")
@app.patch("/items/<int:id>")
@app.delete("/items/<int:id>")
```

### Route Parameters

```python
@app.route(
    "/items/<int:id>",
    endpoint="item_detail",         # name for url_for (default: function name)
    strict_slashes=True,            # False allows trailing slash mismatch
    redirect_to=None,               # redirect old URL to new
    host=None,                      # host-based routing (requires host_matching=True)
    subdomain=None,
    provide_automatic_options=True,
)
def get_item(id): ...
```

### Path Converters

```python
<name>           # str (default) — any text without /
<name:string>    # str
<name:int>       # int
<name:float>     # float
<name:path>      # str, including /
<name:uuid>      # uuid.UUID

# Custom converter
from werkzeug.routing import BaseConverter

class SlugConverter(BaseConverter):
    regex = r"[a-z0-9\-]+"

app.url_map.converters["slug"] = SlugConverter
# usage: /posts/<slug:slug>
```

### URL Building

```python
from flask import url_for

url_for("item_detail", id=1)               # "/items/1"
url_for("item_detail", id=1, _external=True)  # "http://host/items/1"
url_for("item_detail", id=1, q="foo")      # "/items/1?q=foo"
url_for("static", filename="style.css")    # "/static/style.css"
url_for("bp_name.view_name", id=1)         # blueprint-prefixed
```

### `Blueprint`

```python
from flask import Blueprint

bp = Blueprint(
    "items",                    # name
    __name__,
    url_prefix="/items",
    template_folder="templates",
    static_folder="static",
    static_url_path="/items/static",
    subdomain=None,
)

@bp.get("/<int:id>")
def get_item(id): ...

@bp.before_request
def before(): ...

@bp.after_request
def after(response): ...

@bp.errorhandler(404)
def not_found(e): ...

app.register_blueprint(bp)
app.register_blueprint(bp, url_prefix="/api/v1/items")  # override prefix

# Nested blueprints (Flask 2.0+)
parent = Blueprint("parent", __name__, url_prefix="/parent")
child  = Blueprint("child",  __name__, url_prefix="/child")
parent.register_blueprint(child)
app.register_blueprint(parent)
```

---

## Request Object — `flask.request`

```python
from flask import request

request.method           # "GET" | "POST" | ...
request.path             # "/items/1"
request.full_path        # "/items/1?q=foo"
request.url              # full URL string
request.base_url         # URL without query string
request.host             # "example.com"
request.host_url         # "http://example.com/"
request.scheme           # "http" | "https"
request.is_secure        # bool
request.is_json          # bool — Content-Type is application/json

# Query parameters
request.args             # ImmutableMultiDict
request.args.get("q")
request.args.get("page", 1, type=int)
request.args.getlist("tags")   # list[str]

# Form data (application/x-www-form-urlencoded, multipart/form-data)
request.form             # ImmutableMultiDict
request.form.get("username")
request.form.getlist("roles")

# JSON body
request.json             # Any | None (requires Content-Type: application/json)
request.get_json(
    force=False,           # parse even if Content-Type is not JSON
    silent=False,          # return None instead of raising on parse error
    cache=True,
)

# Raw body
request.data             # bytes — raw body (only if not form/file consumed)
request.get_data(cache=True, as_text=False, parse_form_data=False)

# File uploads
request.files            # ImmutableMultiDict[str, FileStorage]
f = request.files["upload"]
f.filename               # original filename
f.content_type           # MIME type
f.content_length         # int | None
f.read()                 # bytes
f.save("path/to/dest")
f.stream                 # BytesIO

# Headers
request.headers          # EnvironHeaders (case-insensitive)
request.headers.get("Authorization")
request.content_type     # str
request.content_length   # int | None
request.accept           # Accept
request.accept_mimetypes.best_match(["application/json", "text/html"])

# Cookies
request.cookies          # ImmutableMultiDict
request.cookies.get("session_id")

# Auth
request.authorization    # Authorization object | None
request.authorization.username
request.authorization.password

# Client info
request.remote_addr      # str — client IP
request.environ          # raw WSGI environ dict
request.endpoint         # str — matched endpoint name
request.view_args        # dict — matched path parameters
request.url_rule         # Rule object
request.blueprints       # list[str] — active blueprint chain
```

---

## Response

### Response Helpers

```python
from flask import (
    make_response, jsonify,
    redirect, abort, send_file,
    send_from_directory, stream_with_context,
)

# Return value shortcuts (auto-wrapped by Flask)
return "text string"                          # 200 text/html
return "text", 201
return "text", 201, {"X-Custom": "value"}
return {"key": "value"}                       # 200 application/json (dict auto-jsonified)
return response_object

# jsonify
return jsonify({"key": "value"})
return jsonify(items=[1, 2, 3], total=3)

# make_response (full control)
resp = make_response("body", 200)
resp = make_response(jsonify({...}), 201)
resp.headers["X-Custom"] = "value"
resp.set_cookie("session", "abc", ...)
return resp

# Redirect
return redirect(url_for("index"))
return redirect("https://example.com", code=301)

# Abort (raises HTTPException)
abort(404)
abort(403, description="Access denied")

# File responses
return send_file(
    "path/to/file.pdf",
    mimetype="application/pdf",
    as_attachment=True,
    download_name="report.pdf",
    conditional=True,              # support If-Modified-Since / Range
    etag=True,
    max_age=None,                  # cache max-age seconds
)

return send_from_directory(
    "uploads",
    "file.png",
    as_attachment=False,
)

# Streaming response
def generate():
    for chunk in large_data:
        yield chunk

return app.response_class(
    stream_with_context(generate()),
    content_type="text/plain",
)
```

### `Response` Object

```python
resp = make_response()

resp.status_code         # int
resp.status              # "200 OK"
resp.data                # bytes
resp.text                # str
resp.json                # Any (if JSON)
resp.headers             # Headers
resp.headers["X-Custom"] = "value"
resp.content_type        # str
resp.mimetype            # str (without params)
resp.charset             # str

resp.set_cookie(
    key,
    value="",
    max_age=None,          # int seconds | timedelta
    expires=None,          # datetime | timestamp
    path="/",
    domain=None,
    secure=False,
    httponly=False,
    samesite=None,         # "Strict" | "Lax" | "None"
)
resp.delete_cookie(key, path="/", domain=None, secure=False, samesite=None)
resp.get_etag()
resp.set_etag("abc123", weak=False)
resp.cache_control.max_age = 3600
resp.cache_control.no_cache = True
resp.cache_control.public  = True
resp.last_modified = datetime.utcnow()
resp.expires = datetime(...)
resp.vary.add("Accept-Encoding")

resp.autocorrect_location_header = True
resp.implicit_sequence_conversion = True
resp.direct_passthrough = False
```

---

## Sessions

```python
from flask import session

session["user_id"] = 42
session.get("user_id")
session.pop("user_id", None)
del session["user_id"]
session.clear()
session.modified = True       # force save even if only mutated (e.g. list append)
session.permanent = True      # use PERMANENT_SESSION_LIFETIME instead of browser session

"user_id" in session          # bool
```

---

## Error Handling

```python
@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "not found"}), 404

@app.errorhandler(500)
def server_error(e):
    return jsonify({"error": "internal error"}), 500

@app.errorhandler(Exception)
def handle_all(e):
    return jsonify({"error": str(e)}), 500

# HTTPException attributes
from werkzeug.exceptions import HTTPException

@app.errorhandler(HTTPException)
def handle_http(e):
    return jsonify({
        "code":        e.code,
        "name":        e.name,
        "description": e.description,
    }), e.code

# Register on Blueprint
@bp.errorhandler(404)
def bp_not_found(e): ...

# Common werkzeug exceptions
from werkzeug.exceptions import (
    BadRequest,           # 400
    Unauthorized,         # 401
    Forbidden,            # 403
    NotFound,             # 404
    MethodNotAllowed,     # 405
    Conflict,             # 409
    Gone,                 # 410
    UnsupportedMediaType, # 415
    UnprocessableEntity,  # 422
    TooManyRequests,      # 429
    InternalServerError,  # 500
    ServiceUnavailable,   # 503
)
```

---

## Request Lifecycle Hooks

```python
@app.before_request
def before():
    g.user = get_user_from_token(request.headers.get("Authorization"))

@app.after_request
def after(response):
    response.headers["X-Request-Id"] = str(uuid4())
    return response            # must return response

@app.teardown_request
def teardown(exc):             # called after response, even on error
    db = g.pop("db", None)
    if db is not None:
        db.close()

@app.teardown_appcontext
def teardown_ctx(exc):         # called when app context is popped
    db = g.pop("db", None)
    if db:
        db.close()

# Startup / shutdown (Flask 2.3+ with Werkzeug 3.0)
@app.before_serving
async def startup():           # ASGI / async only
    app.db = await connect()

@app.after_serving
async def shutdown():
    await app.db.close()

# Blueprint-scoped hooks
@bp.before_request
def bp_before(): ...

@bp.after_request
def bp_after(response): ...

@bp.before_app_request
def before_all(): ...           # runs for all app requests
```

---

## Class-Based Views

```python
from flask.views import View, MethodView

# MethodView — one method per HTTP verb
class ItemAPI(MethodView):
    init_every_request = False     # True = new instance per request

    def get(self, id=None):
        if id is None:
            return jsonify({"items": [...]})
        return jsonify({"id": id})

    def post(self):
        data = request.get_json()
        return jsonify({"created": True}), 201

    def put(self, id):
        ...

    def delete(self, id):
        return "", 204

# Register
view = ItemAPI.as_view("item_api")
app.add_url_rule("/items",      view_func=view,   methods=["GET", "POST"])
app.add_url_rule("/items/<int:id>", view_func=view, methods=["GET", "PUT", "DELETE"])

# Decorators on class
class ItemAPI(MethodView):
    decorators = [login_required, rate_limit]
```

---

## Templating (Jinja2)

```python
from flask import render_template, render_template_string

return render_template(
    "item.html",
    item=item,
    title="Detail",
)

return render_template_string("<h1>{{ title }}</h1>", title="Hello")

# Template globals / filters
app.jinja_env.globals["now"] = datetime.utcnow
app.jinja_env.filters["currency"] = lambda v: f"${v:.2f}"

@app.template_filter("reverse")
def reverse_filter(s):
    return s[::-1]

@app.template_global("current_user")
def current_user():
    return g.user
```

---

## Signals (blinker)

```python
from flask import signals_available
from flask.signals import (
    request_started,
    request_finished,
    request_tearing_down,
    got_request_exception,
    appcontext_pushed,
    appcontext_tearing_down,
    message_flashed,
)

# Connect
def on_request_started(sender, **extra):
    logger.debug(f"Request started: {request.path}")

request_started.connect(on_request_started, app)

# Custom signal
from blinker import Namespace
_signals = Namespace()
user_created = _signals.signal("user-created")

user_created.send(app, user=new_user)
user_created.connect(lambda sender, user: send_welcome_email(user))
```

---

## Extensions (Common)

```python
# Flask-SQLAlchemy
from flask_sqlalchemy import SQLAlchemy
app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///db.sqlite3"
db = SQLAlchemy(app)
# or with factory: db.init_app(app)

class User(db.Model):
    id    = db.Column(db.Integer, primary_key=True)
    name  = db.Column(db.String(80), nullable=False)
    email = db.Column(db.String(120), unique=True)

db.create_all()
db.session.add(user)
db.session.commit()
db.session.rollback()
db.session.delete(user)
User.query.get(1)
User.query.filter_by(name="Alice").first()
User.query.filter(User.id > 10).all()

# Flask-Migrate
from flask_migrate import Migrate
migrate = Migrate(app, db)
# flask db init / migrate / upgrade / downgrade

# Flask-Login
from flask_login import LoginManager, login_user, logout_user, current_user, login_required
login_manager = LoginManager(app)
login_manager.login_view = "auth.login"

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

login_user(user, remember=True)
logout_user()
current_user.is_authenticated
current_user.is_anonymous

@app.get("/profile")
@login_required
def profile(): ...

# Flask-JWT-Extended
from flask_jwt_extended import (
    JWTManager, create_access_token, create_refresh_token,
    jwt_required, get_jwt_identity, get_jwt,
    set_access_cookies, unset_jwt_cookies,
)
jwt = JWTManager(app)
app.config["JWT_SECRET_KEY"] = "secret"

token = create_access_token(identity=user.id, expires_delta=timedelta(hours=1))
refresh = create_refresh_token(identity=user.id)

@app.get("/me")
@jwt_required()
def me():
    return jsonify(identity=get_jwt_identity())

# Flask-Caching
from flask_caching import Cache
cache = Cache(app, config={"CACHE_TYPE": "SimpleCache", "CACHE_DEFAULT_TIMEOUT": 300})

@cache.cached(timeout=60)
def get_items(): ...

@cache.memoize(timeout=60)
def get_item(id): ...

cache.delete("view:/items")
cache.clear()

# Flask-Limiter
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
limiter = Limiter(get_remote_address, app=app, default_limits=["200/day", "50/hour"])

@app.get("/items")
@limiter.limit("10/minute")
def list_items(): ...
```

---

## Testing

```python
import pytest
from flask import Flask

@pytest.fixture
def client(app):
    return app.test_client()

@pytest.fixture
def app():
    app = create_app({"TESTING": True, "DATABASE": ":memory:"})
    yield app

# Test client methods
client.get("/items")
client.get("/items", query_string={"q": "foo", "page": 1})
client.post("/items", json={"name": "foo", "price": 9.99})
client.post("/login", data={"username": "u", "password": "p"})
client.put("/items/1", json={...})
client.patch("/items/1", json={...})
client.delete("/items/1")
client.open("/items", method="GET", headers={"Authorization": "Bearer token"})

response.status_code        # int
response.status             # "200 OK"
response.data               # bytes
response.text               # str (Flask 2.2+)
response.json               # Any
response.headers            # Headers
response.get_json()         # Any
response.get_data(as_text=True)

# Session manipulation in tests
with client.session_transaction() as sess:
    sess["user_id"] = 1

# Request context in tests
with app.test_request_context("/items?q=foo"):
    assert request.args.get("q") == "foo"

# Application context in tests
with app.app_context():
    assert current_app.config["TESTING"] is True

# pytest-flask
def test_get_item(client):
    rv = client.get("/items/1")
    assert rv.status_code == 200
    assert rv.json["id"] == 1

def test_create_item(client):
    rv = client.post("/items", json={"name": "foo", "price": 1.0})
    assert rv.status_code == 201
```

---

## Common Patterns

```python
# JSON API error response
def api_error(message, status=400, **kwargs):
    return jsonify({"error": message, **kwargs}), status

@app.errorhandler(422)
def validation_error(e):
    return api_error("Validation failed", 422, details=str(e))

# Pagination
def paginate(query, page, per_page=20):
    p = query.paginate(page=page, per_page=per_page, error_out=False)
    return {
        "items":   [i.to_dict() for i in p.items],
        "total":   p.total,
        "pages":   p.pages,
        "page":    p.page,
        "has_next": p.has_next,
        "has_prev": p.has_prev,
    }

# Token auth decorator
from functools import wraps

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get("Authorization", "").removeprefix("Bearer ")
        user = User.query.filter_by(token=token).first()
        if not user:
            abort(401)
        g.user = user
        return f(*args, **kwargs)
    return decorated

@app.get("/profile")
@token_required
def profile():
    return jsonify(g.user.to_dict())

# Per-request DB connection
@app.before_request
def open_db():
    g.db = get_db_connection()

@app.teardown_request
def close_db(exc):
    db = g.pop("db", None)
    if db:
        db.close()

# Streaming CSV download
import csv, io

@app.get("/export")
def export_csv():
    def generate():
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["id", "name"])
        yield buf.getvalue()
        buf.seek(0); buf.truncate()
        for row in db.fetch_all():
            w.writerow([row.id, row.name])
            yield buf.getvalue()
            buf.seek(0); buf.truncate()

    headers = {"Content-Disposition": "attachment; filename=export.csv"}
    return app.response_class(
        stream_with_context(generate()),
        mimetype="text/csv",
        headers=headers,
    )

# Versioned blueprints
v1 = Blueprint("v1", __name__, url_prefix="/api/v1")
v2 = Blueprint("v2", __name__, url_prefix="/api/v2")

# CORS (manual)
@app.after_request
def add_cors(response):
    response.headers["Access-Control-Allow-Origin"]  = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    return response
```
