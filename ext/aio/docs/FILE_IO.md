// ext/aio/docs/FILE_IO.md 

# ext::aio File I/O

Asynchronous file I/O wrapper for `ext::aio`.

This module provides a `File` abstraction over an async file descriptor and exposes common file operations such as open, read, write, seek, flush, truncate, and size.


## Open files

### `file_open`

```c3
fn File*? aio::file_open(String path, String mode, int permission = 0o644)
```

Opens a file and returns a `File*`.

The `mode` string is passed to the underlying file-open implementation.

```c3
File* f = aio::file_open("hello.txt", "w+")!;
defer f.free();
```

The default permission is `0o644`.

```c3
File* f = aio::file_open("data.txt", "w", 0o600)!;
defer f.free();
```

## Standard streams

### `stdin`

```c3
fn File*? aio::stdin()
```

Returns a `File*` for standard input.

The returned object does not own the underlying file descriptor.

```c3
File* in = aio::stdin()!;
defer in.free();
```

### `stdout`

```c3
fn File*? aio::stdout()
```

Returns a `File*` for standard output.

The returned object does not own the underlying file descriptor.

```c3
File* out = aio::stdout()!;
defer out.free();

out.write_all("hello\n")!;
```

### `stderr`

```c3
fn File*? aio::stderr()
```

Returns a `File*` for standard error.

The returned object does not own the underlying file descriptor.

```c3
File* err = aio::stderr()!;
defer err.free();

err.write_all("error\n")!;
```

## State and lifetime

### `File.is_closed`

```c3
fn bool File.is_closed(&self) @inline
```

Returns `true` when the file is closed or its file descriptor is invalid.

```c3
if (f.is_closed()) return aio::FILE_CLOSED~;
```

### `File.close`

```c3
fn void File.close(&self)
```

Closes the file if it is still open.

Calling `close()` more than once is safe.

```c3
f.close();
```

For files created by `file_open()`, the underlying file descriptor is closed.

For `stdin()`, `stdout()`, and `stderr()`, the wrapper is closed but the underlying standard descriptor is not owned.

### `File.free`

```c3
fn void File.free(&self)
```

Closes the file if needed and releases the `File` object.

```c3
File* f = aio::file_open("data.txt", "r")!;
defer f.free();
```

## Reading

### `File.read`

```c3
fn sz? File.read(&self, char[] buf)
```

Reads up to `buf.len` bytes into `buf`.

Returns the number of bytes read.

```c3
char[4096] buf;

sz n = f.read(buf[..])!;
String data = (String)buf[0:n];
```

If `buf.len` is zero, it returns `0`.

If the file is closed, `FILE_CLOSED` is returned.

### `File.read_exact`

```c3
fn void? File.read_exact(&self, char[] buf)
```

Reads exactly `buf.len` bytes into `buf`.

If EOF is reached before the buffer is full, `FILE_EOF` is returned.

```c3
char[16] header;

f.read_exact(header[..])!;
```

Use this for fixed-size headers or binary records.

## Writing

### `File.write`

```c3
fn sz? File.write(&self, char[] data) @maydiscard
```

Writes up to `data.len` bytes.

Returns the number of bytes written.

```c3
sz n = f.write("hello")!;
```

If `data.len` is zero, it returns `0`.

If the file is closed, `FILE_CLOSED` is returned.

### `File.write_all`

```c3
fn void? File.write_all(&self, char[] data) @maydiscard
```

Writes the entire `data` slice.

This repeatedly calls `write()` until all bytes are written.

```c3
f.write_all("hello world\n")!;
```

If a write returns `0` before all bytes are written, `FILE_CLOSED` is returned.

## Position

### `File.seek`

```c3
fn long? File.seek(&self, long offset, int whence)
```

Moves the file position and returns the resulting position.

```c3
long pos = f.seek(0, 0)!;
```

The `whence` value is passed to the underlying seek operation.

Common values are usually equivalent to:

```c3
0 == SEEK_SET
1 == SEEK_CUR
2 == SEEK_END
```

### `File.tell`

```c3
fn long? File.tell(&self)
```

Returns the current file position.

```c3
long pos = f.tell()!;
```

## File operations

### `File.flush`

```c3
fn void? File.flush(&self) @maydiscard
```

Flushes pending file data.

```c3
f.flush()!;
```

### `File.truncate`

```c3
fn void? File.truncate(&self, long size) @maydiscard
```

Truncates or extends the file to `size` bytes.

```c3
f.truncate(0)!;
```

### `File.size`

```c3
fn long? File.size(&self)
```

Returns the file size in bytes.

```c3
long size = f.size()!;
```

## Example: write a file

```c3
import ext::aio;

fn void? main_task(void* arg)
{
    File* f = aio::file_open("hello.txt", "w")!;
    defer f.free();

    f.write_all("hello aio file\n")!;
    f.flush()!;
}
```

## Example: read a file

```c3
import ext::aio;
import ext::debug;

fn void? main_task(void* arg)
{
    File* f = aio::file_open("hello.txt", "r")!;
    defer f.free();

    char[4096] buf;

    sz n = f.read(buf[..])!;
    String text = (String)buf[0:n];

    warn("%s", text);
}
```

## Example: copy a file

```c3
import ext::aio;

fn void? main_task(void* arg)
{
    File* src = aio::file_open("input.bin", "r")!;
    defer src.free();

    File* dst = aio::file_open("output.bin", "w")!;
    defer dst.free();

    char[8192] buf;

    while (true)
    {
        sz n = src.read(buf[..])!;
        if (n == 0) break;

        dst.write_all(buf[0:n])!;
    }

    dst.flush()!;
}
```

## Example: read a fixed-size header

```c3
import ext::aio;

fn void? main_task(void* arg)
{
    File* f = aio::file_open("data.bin", "r")!;
    defer f.free();

    char[32] header;

    f.read_exact(header[..])!;
}
```

## Example: seek and overwrite

```c3
import ext::aio;
import c::errno;

fn void? main_task(void* arg)
{
    File* f = aio::file_open("data.txt", "r+")!;
    defer f.free();

    f.seek(0, 0 /*SEEK_SET*/)!;
    f.write_all("BEGIN")!;
    f.flush()!;
}
```

## Example: stdout and stderr

```c3
import ext::aio;

fn void? main_task(void* arg)
{
    File* out = aio::stdout()!;
    defer out.free();

    File* err = aio::stderr()!;
    defer err.free();

    out.write_all("normal output\n")!;
    err.write_all("error output\n")!;
}
```

## Error handling

```c3
if (catch err = f.read_exact(buf[..]))
{
    if (err == aio::FILE_EOF)
    {
        // The file ended before the buffer was filled.
    }

    return err~;
}
```

Closed files return `FILE_CLOSED`.

```c3
f.close();

if (catch err = f.write_all("data"))
{
    if (err == aio::FILE_CLOSED)
    {
        // The file is closed.
    }

    return err~;
}
```

## Notes

- `file_open()` returns a `File*` that owns its file descriptor.
- `stdin()`, `stdout()`, and `stderr()` return wrappers that do not own the underlying descriptor.
- `read()` may return fewer bytes than requested.
- `write()` may write fewer bytes than requested.
- Use `read_exact()` when an exact byte count is required.
- Use `write_all()` when the entire buffer must be written.
- Always call `free()` when the `File*` is no longer needed.

// eof