# ext::aiofiles

This module is deprecated. Use [`ext::aio`](../aio/README.md) instead.

Asynchronous, non-blocking file I/O on top of [ext::asyncio](../asyncio/README.md) framework.
This module follows mostly the [Python's aiofiles API](PythonAPI.md).

### Available modules

| Module | Description |
|--------|-------------|
| `ext::aiofiles` | Asynchronous file operations: open(), file_size(), read(), write(), readline(), read_unbuffered(), at_eof(), read_until(), writef(), flush(), seek(), tell(), truncate(), stdin(), stdout(), stderr() |
| `ext::aiofiles::os` | Asynchronous os operations: stat(), rename(), replace(), remove(), mkdir(), makedirs(), rmdir(), removedirs(), listdir(), scandir(), link(), symlink(), readlink() |
| `ext::aiofiles::os::path` | Asynchronous Directory/folder operations: exists(), getsize(), isfile(), isdir(), islink() |
| ext::aiofiles::tempfile` | Asynchronous tempfile operations: temporaryFile(), temporaryDirectory() |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

### Files

* [aiofiles.c3](aiofiles.c3)
* [aiofiles.os.c3](aiofiles.os.c3)
* [aiofiles.tempfile.c3](aiofiles.tempfile.c3)

### API functions

Following functions follow Python like behavior, all of them are asynchronous/non-blocking under the framework of `asyncio`.

File I/O functions:

```c3
import ext::asyncio;
import ext::aiofiles;

usz? size = aiofiles::file_size(String path);
AioFile? afile = aiofiles::open(String path, String mode);
void? afile.close();

usz? n = afile.read_unbuffered(char[] buf); // .seek(), .tell() compatible
usz? n = afile.read(char[] buf); // buffered, not compatible with .seek() and .tell();
usz? n = afile.read_until(char delimiter, char[] buf);

bool b = afile.at_eof();

usz? n = afile.write(char[] buf);
usz? n = afile.writef(String format, ...args);
void afile.flush();

long afile.seek(long pos, int whence);
long afile.tell();

void? afile.truncate(long size);

AioFile in = aiofiles::stdin();
AioFile out = aiofiles::stdout();
AioFile err = aiofiles::stderr();
```

`os` functions like in Python:

```c3
import ext::asyncio;
import ext::aiofiles;
import ext::aiofiles::os;
import std::collections::list;

Stat? st = os::stat(String path);
long mtime = st.st_mtime;
long size = st.st_size;

void? os::rename(String name, String to_name) @maydiscard;
void? os::replace(String name, String to_name) @maydiscard; // overwrite if exists
void? os::remove(String name) @maydiscard;
usz? os::sendfile(int to_sock, int from_fd, long offset, long count);

void? os::mkdir(String name, int mode=0o777) @maydiscard;
void? os::makedirs(String name, int mode=0o777, bool exist_ok=true) @maydiscard;
void? os::removedirs(String path) @maydiscard; // remove recursively, if empty
List{String}? files = os::listdir(Allocator allocx, String path);

DirIterator? iter = os::scandir(Allocator allocx, String path);
void iter.close();

DirEntry? entry = iter.next();
void entry.free();
String name = entry.name;
usz? size = entry.size();
long? mtime = entry.last_modified();
bool b = entry.is_file();
bool b = entry.is_link();
bool b = entry.is_link();

void? os::link(String path, String newlink);
void? os::symlink(String path, String newlink);
usz? n = os::readlink(Stri g path, char[] buf);

```

`path` functions like in Python:

```c3
import ext::aiofiles::os::path;

usz? size = path::getsize(String path);
bool b = path::exists(String path);
bool b = path::isdir();
bool b = path::isfile();
bool b = path::islink();
```

`tempfile` functions like in Python:

```c3 
import ext::aiofiles::tempfile;

AioTempFile? tf = tempfile::temporaryFile();
String name = tf.name;
String fullpath = tf.fullpath;

void tf.close_handle(); // closes only handle, need to call .close() later

void tf.close(); // close file and remove it
// AioTempFile inherits all methods of AioFile above.

AioTempDir? td = tempfile::temporaryDirectory();
String fullpath = td.fullpath;
void td.close(); // removes everything in the directory
```

# Examples

* [../../examples/aiofiles/aio_sample.c3](../../examples/aiofiles/aio_sample.c3)
* [../../examples/aiofiles/aio_tempfile.c3](../../examples/aiofiles/aio_tempfile.c3)


This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.
