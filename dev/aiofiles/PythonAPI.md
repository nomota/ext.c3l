# aiofiles API Reference

## File I/O

### Open — `aiofiles.open()`

```python
async with aiofiles.open(
    file,                    # str | Path
    mode="r",                # 'r' | 'w' | 'a' | 'rb' | 'wb' | 'ab' | 'r+' | 'w+' | ...
    encoding=None,           # e.g. "utf-8"  (text mode only)
    errors=None,             # "strict" | "ignore" | "replace"
    newline=None,
    buffering=-1,
    loop=None,               # deprecated in 3.10+
    executor=None,           # custom ThreadPoolExecutor
) as f:
    ...
```

---

## Text Mode (`mode='r' | 'w' | 'a' | 'r+'`)

### `AsyncTextIOWrapper`

```python
# Read
content  = await f.read(size=-1)       # str — entire file, or up to size chars
line     = await f.readline()          # str — one line (including \n)
lines    = await f.readlines()         # list[str]

async for line in f:                   # async line-by-line iteration
    print(line, end="")

# Write
await f.write(s: str)                  # -> int (number of characters written)
await f.writelines(lines: list[str])   # write lines in order (no auto newline)

# Seek
pos      = await f.tell()             # -> int (current position in bytes)
await f.seek(offset, whence=0)        # whence: 0=start, 1=current, 2=end
await f.truncate(size=None)           # resize file

# Flush / Close
await f.flush()
await f.close()

# Attributes
f.closed     # bool
f.mode       # str
f.name       # str | int
f.encoding   # str
f.errors     # str
```

---

## Binary Mode (`mode='rb' | 'wb' | 'ab' | 'r+b'`)

### `AsyncBufferedIOBase` / `AsyncBufferedReader`

```python
# Read
data  = await f.read(size=-1)         # bytes — entire file, or up to size bytes
data  = await f.read1(size=-1)        # bytes — at most one underlying system call
data  = await f.readinto(b)           # int  — read into a pre-allocated buffer
line  = await f.readline()            # bytes — up to \n
lines = await f.readlines()           # list[bytes]

# Write
await f.write(b: bytes)               # -> int
await f.writelines(lines: list[bytes])

# Seek
pos   = await f.tell()
await f.seek(offset, whence=0)
await f.truncate(size=None)

# Flush / Close
await f.flush()
await f.close()

f.closed  # bool
f.name    # str | int
f.mode    # str
```

---

## Raw Binary Mode (`mode='rb'`, unbuffered)

### `AsyncFileIO`

```python
data = await f.read(size=-1)          # bytes
await f.write(b: bytes)               # -> int
await f.readinto(b)                   # -> int
pos  = await f.tell()
await f.seek(offset, whence=0)
await f.truncate(size=None)
await f.flush()
await f.close()

f.closed     # bool
f.mode       # str
f.name       # str | int
```

---

## Temporary Files — `aiofiles.tempfile`

```python
import aiofiles.tempfile as atf
```

### `NamedTemporaryFile`

```python
async with atf.NamedTemporaryFile(
    mode="w+b",
    suffix=None,
    prefix=None,
    dir=None,
    delete=True,          # auto-delete on context exit
    encoding=None,
    errors=None,
) as tmp:
    await tmp.write(b"data")
    await tmp.seek(0)
    data = await tmp.read()
    print(tmp.name)       # "/tmp/tmpXXXXXX"
```

### `TemporaryFile`

```python
async with atf.TemporaryFile(
    mode="w+b",
    suffix=None,
    prefix=None,
    dir=None,
) as tmp:
    await tmp.write(b"data")
    await tmp.seek(0)
    data = await tmp.read()
    # no tmp.name (anonymous file)
```

### `SpooledTemporaryFile`

```python
async with atf.SpooledTemporaryFile(
    max_size=0,           # held in memory up to this size, then spilled to disk
    mode="w+b",
    suffix=None,
    prefix=None,
    dir=None,
    encoding=None,
    errors=None,
) as tmp:
    await tmp.write(b"small data")
    await tmp.rollover()  # force spill to disk
    f.closed              # bool
```

### `TemporaryDirectory`

```python
async with atf.TemporaryDirectory(
    suffix=None,
    prefix=None,
    dir=None,
) as tmpdir:
    print(tmpdir)         # "/tmp/tmpXXXXXX" (directory path string)
    path = Path(tmpdir) / "file.txt"
    async with aiofiles.open(path, "w") as f:
        await f.write("hello")
# directory and all contents deleted on context exit
```

---

## OS-level Utilities — `aiofiles.os`

```python
import aiofiles.os as aos
```

### File System Operations

```python
await aos.rename(src, dst)
await aos.replace(src, dst)             # atomic rename
await aos.remove(path)                  # delete file
await aos.unlink(path)                  # alias for remove

await aos.mkdir(path, mode=0o777, exist_ok=False)
await aos.makedirs(path, mode=0o777, exist_ok=False)
await aos.rmdir(path)                   # empty directory only
await aos.removedirs(path)              # remove empty parent directories recursively

await aos.link(src, dst)               # hard link
await aos.symlink(src, dst)            # symbolic link
await aos.readlink(path)               # -> str
```

### File Info

```python
stat   = await aos.stat(path)          # os.stat_result
stat   = await aos.lstat(path)         # stat of the symlink itself (not target)
stat.st_size
stat.st_mtime
stat.st_mode

exists = await aos.path.exists(path)   # -> bool
isfile = await aos.path.isfile(path)   # -> bool
isdir  = await aos.path.isdir(path)    # -> bool
islink = await aos.path.islink(path)   # -> bool
size   = await aos.path.getsize(path)  # -> int (bytes)
```

### Directory Listing

```python
entries = await aos.listdir(path=".")  # -> list[str] (filenames only)

# scandir — iterate DirEntry objects (reuses stat, more efficient than listdir)
async with aos.scandir(path=".") as it:
    async for entry in it:
        entry.name           # str
        entry.path           # str (full path)
        entry.is_file()      # bool
        entry.is_dir()       # bool
        entry.is_symlink()   # bool
        entry.stat()         # os.stat_result (cached)
```

### Low-level File Descriptors

```python
fd  = await aos.open(path, flags, mode=0o777)   # -> int (fd)
await aos.close(fd)
n   = await aos.read(fd, n)                      # -> bytes
n   = await aos.write(fd, data)                  # -> int
await aos.fsync(fd)                              # flush to disk
await aos.fdatasync(fd)                          # flush data only (no metadata)
await aos.ftruncate(fd, length)
stat = await aos.fstat(fd)                       # -> os.stat_result
await aos.sendfile(out_fd, in_fd, offset, count) # zero-copy transfer
```

---

## Direct Executor Dispatch — `aiofiles.threadpool`

Run a synchronous function in a thread pool asynchronously.

```python
import aiofiles.threadpool as atp

result = await atp.run_in_executor(
    executor=None,         # None → default ThreadPoolExecutor
    func=my_sync_func,
    *args,
)

# Example: wrap a synchronous library call
data = await atp.run_in_executor(None, json.load, open("data.json"))
```

---

## Common Patterns

```python
# Read entire file as text
async with aiofiles.open("config.toml", encoding="utf-8") as f:
    content = await f.read()

# Process line by line
async with aiofiles.open("log.txt") as f:
    async for line in f:
        process(line.rstrip("\n"))

# Write text
async with aiofiles.open("output.txt", "w", encoding="utf-8") as f:
    await f.write("first line\n")
    await f.writelines(["second\n", "third\n"])

# Binary copy in chunks
async with aiofiles.open("src.bin", "rb") as src, \
           aiofiles.open("dst.bin", "wb") as dst:
    while chunk := await src.read(65536):
        await dst.write(chunk)

# Append to file
async with aiofiles.open("events.log", "a") as f:
    await f.write(f"{timestamp} {event}\n")

# Safe atomic write (write to temp, then rename)
async with aiofiles.open("data.json.tmp", "w") as f:
    await f.write(json.dumps(obj))
await aos.replace("data.json.tmp", "data.json")

# Check existence before reading
if await aos.path.exists("config.json"):
    async with aiofiles.open("config.json") as f:
        config = json.loads(await f.read())

# List files in a directory
names = await aos.listdir("./logs")
txt_files = [n for n in names if n.endswith(".txt")]

# Write to temp file, then move to final destination
async with atf.NamedTemporaryFile(mode="wb", delete=False, suffix=".bin") as tmp:
    await tmp.write(processed_data)
    tmp_path = tmp.name
await aos.replace(tmp_path, "result.bin")
```
