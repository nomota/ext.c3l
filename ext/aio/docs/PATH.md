// ext/aio/docs/PATH.md 

# ext::aio::path

Async path and filesystem operations on top of `ext::aio`.

This module wraps blocking path, directory, link, and file-status operations with `aio::run_in_executor()`, so they can be used from async code without blocking the event loop thread.

## Module

```c3
module ext::aio::path;
```


## File status

### `statinfo`

```c3
struct StatInfo
{
    sz size;
    long mtime;

    bool is_file;
    bool is_dir;
    bool is_link;
}

fn StatInfo? path::statinfo(String path)
```

Returns basic file status information.

```c3
import ext::io::stat;
import ext::aio::path;

StatInfo st = path::statinfo("data.txt")!;

long size = st.size;
long mtime = st.mtime;

```

If the path does not exist, `STAT_FILE_NOT_FOUND` is returned.

### `getsize`

```c3
fn sz? path::getsize(String path)
```

Returns the file size in bytes.

```c3
sz size = path::getsize("data.txt")!;
```

## Path checks

### `exists`

```c3
fn bool path::exists(String path)
```

Returns `true` if the path exists.

```c3
if (path::exists("data.txt"))
{
    // path exists
}
```

If the executor call fails, this function returns `false`.

### `isfile`

```c3
fn bool path::isfile(String path)
```

Returns `true` if the path is a regular file.

```c3
if (path::isfile("data.txt"))
{
    // regular file
}
```

If the executor call fails, this function returns `false`.

### `isdir`

```c3
fn bool path::isdir(String path)
```

Returns `true` if the path is a directory.

```c3
if (path::isdir("assets"))
{
    // directory
}
```

If the executor call fails, this function returns `false`.

### `islink`

```c3
fn bool path::islink(String path)
```

Returns `true` if the path is a symbolic link.

```c3
if (path::islink("current"))
{
    // symbolic link
}
```

If the executor call fails, this function returns `false`.

## Rename, replace, and remove

### `rename`

```c3
fn void? path::rename(String path, String path2) @maydiscard
```

Renames `path` to `path2`.

```c3
path::rename("old.txt", "new.txt")!;
```

### `replace`

```c3
fn void? path::replace(String path, String path2) @maydiscard
```

Replaces `path2` with `path`.

If `path2` already exists, it is removed first. Then `path` is renamed to `path2`.

```c3
path::replace("new.tmp", "data.txt")!;
```

### `remove`

```c3
fn void? path::remove(String path) @maydiscard
```

Removes a file.

```c3
path::remove("data.txt")!;
```

## Directories

### `mkdir`

```c3
fn void? path::mkdir(String path, int mode = 0o777) @maydiscard
```

Creates a single directory.

```c3
path::mkdir("cache")!;
```

With an explicit mode:

```c3
path::mkdir("private", 0o700)!;
```

### `makedirs`

```c3
fn void? path::makedirs(String path, int mode = 0o777, bool exist_ok = true) @maydiscard
```

Creates a directory and missing parent directories.

```c3
path::makedirs("build/output/tmp")!;
```

If `exist_ok` is `false` and the directory already exists, `MKDIR_FILE_EXIST` is returned.

```c3
path::makedirs("build", 0o777, false)!;
```

### `removedirs`

```c3
fn void? path::removedirs(String path, int mode = 0o777) @maydiscard
```

Removes an empty directory and then tries to remove empty parent directories.

```c3
path::removedirs("build/output/tmp")!;
```

If the target directory does not exist, `RMDIR_FILE_NOT_FOUND` is returned.

The `mode` argument is currently not used by the implementation.

## Directory listing

### `listdir`

```c3
fn List{String}? path::listdir(Allocator allocx, String path)
```

Returns a list of file names in a directory. Returned list must be properly free'd.

```c3
List{String} files = path::listdir(mem, "assets")!;

foreach (name: files)
{
    io::printfn("%s", name);
    name.free(mem);
}
files.free();
```

The returned `List{String}` must be freed properly. This includes the list itself and any string memory allocated for the entries according to the allocator/list implementation.

### `scandir`

```c3
alias DirIterator = dir::DirIterator;
alias DirEntry = dir::DirEntry;

fn DirIterator? path::scandir(Allocator allocx, String path)
```

Returns a directory iterator.

```c3
path::DirIterator it = path::scandir(mem, "assets")!;
defer it.close();

while (true)
{
    path::DirEntry? entry = it.next();
    if (catch err = entry) break;

    defer entry.free();

    if (entry.is_file())
    {
        io::printfn("file: %s", entry.name);
    }
}
```

`DirIterator` and `DirEntry` are aliases to the underlying directory types.

## Links

### `link`

```c3
fn void? path::link(String path, String path2) @maydiscard
```

Creates a hard link from `path` to `path2`.

```c3
path::link("data.txt", "data.link")!;
```

### `symlink`

```c3
fn void? path::symlink(String path, String path2) @maydiscard
```

Creates a symbolic link from `path` to `path2`.

```c3
path::symlink("releases/v1", "current")!;
```

### `readlink`

```c3
fn sz? path::readlink(String path, char[] buf) @maydiscard
```

Reads the target of a symbolic link into `buf`.

Returns the number of bytes written to `buf`.

```c3
char[1024] buf;

sz n = path::readlink("current", buf[..])!;
String target = (String)buf[0:n];
```

## Send file

### `sendfile`

```c3
fn sz? path::sendfile(Fd to_sock, Fd from_fd, long offset, long count)
```

Sends `count` bytes from file descriptor `from_fd` to socket descriptor `to_sock`, starting at `offset`.

```c3
sz sent = path::sendfile(sock_fd, file_fd, 0, file_size)!;
```

The implementation seeks the source file to `offset`, reads chunks, and writes them to the socket asynchronously.

## Example: create, write, stat, and remove

```c3
import ext::aio;
import ext::aio::path;
import ext::debug;

fn void? main_task(void* arg)
{
    path::makedirs("tmp/example")!;

    File* f = aio::file_open("tmp/example/data.txt", "w")!;
    defer f.free();

    f.write_all("hello path\n")!;
    f.flush()!;

    path::Stat st = path::stat("tmp/example/data.txt")!;
    warn("size: %d", st.st_size);

    path::remove("tmp/example/data.txt")!;
    path::removedirs("tmp/example")!;
}
```

## Example: list directory

```c3
import std::collections::list;
import std::io;
import ext::aio::path;
import ext::mem;

fn void? main_task(void* arg)
{
    List{String} files = path::listdir(mem, ".")!;

    foreach (name: files)
    {
        io::printfn("%s", name);
        name.free(mem);
    }
    files.free();
}
```

## Example: replace a file atomically

```c3
import ext::aio;
import ext::aio::path;

fn void? main_task(void* arg)
{
    File* f = aio::file_open("config.tmp", "w")!;
    defer f.free();

    f.write_all("new config\n")!;
    f.flush()!;

    path::replace("config.tmp", "config.txt")!;
}
```

## Example: symbolic link

```c3
import ext::aio::path;
import ext::debug;

fn void? main_task(void* arg)
{
    path::symlink("releases/v1", "current")!;

    char[1024] buf;
    sz n = path::readlink("current", buf[..])!;

    String target = (String)buf[0:n];
    warn("current -> %s", target);
}
```

## Error handling

```c3
if (catch err = path::stat("missing.txt"))
{
    if (err == path::STAT_FILE_NOT_FOUND)
    {
        // file does not exist
    }

    return err~;
}
```

```c3
if (catch err = path::makedirs("cache", 0o777, false))
{
    if (err == path::MKDIR_FILE_EXIST)
    {
        // directory already exists
    }

    return err~;
}
```

## Notes

- Most operations are executed through `aio::run_in_executor()`.
- `exists()`, `isfile()`, `isdir()`, and `islink()` return `false` if their executor call fails.
- `listdir()` returns allocated strings and the returned list must be freed correctly.
- `scandir()` returns the underlying directory iterator type through aliases.
- `replace()` removes the destination first if it already exists.
- `removedirs()` stops when it reaches a non-empty parent directory.
- `sendfile()` is implemented as a read/write loop, not as a platform-native zero-copy sendfile wrapper.

// eof