# ext::io Extended I/O Operations

Cross-platform file/directory operations in C3, filling the gap of missing pieces in the standard library.

### Available modules

| Module | Description |
|--------|-------------|
| `ext::io::stat` | File stat operations: exists(), size(), is_(file/dir/link), is_(readable/writable/executable), read_link(), link(), symlink(), last_modified(), change_mode() |
| `ext::io::cfile` | File operations: open(), close(), read(), read_byte(), write(), write_byte(), printf(), seek(), tell(), eof(), load(), save(), copy(), rename(), remove(), exists(), size(), last_modified(), is_file(), is_dir(), change_mode() |
| `ext::io::dir` | Directory/folder operations: get_cur_dir(), change_dir(), make_dir(), remove_dir(), rename(), list_dir(), exists(), is_dir(), is_file(), change_mode(), scan_dir() |

This is a part of extended C3 library.
Back to [ext.c3l](../../README.md) library.

### File Status Operations

Three abstraction for status operations.
* [stat.posix.c3](stat.posix.c3) : functions for posix systems.
* [stat.win32.c3](stat.win32.c3) : functions for win32 systems.

Available functions are:

```c3
import ext::io::stat;

bool b = stat::exists(String path);
long? n = stat::size(String path);
long? mtime = stat::last_modified(String path); // missing in std lib
bool b = stat::is_dir(String path);
bool b = stat::is_file(String path);
bool b = stat::is_link(String path); // missing in std lib
bool b = stat::is_readable(String psth); // missing in std lib
bool b = stat::is_writeable(String path); // missing in std lib
bool b = stat::is_executable(String path); // missing in std lib
sz? n = stat::read_link(String path, char[] output); // missing in std lib
Mode_t prev = stat::umask(Mode_t mode); // missing in std lib
void? stat::change_mode(String path, Mode_t mode) @maydiscard; // missing in std lib
void? stat::link(String file, String link);
void? stat::symlink(String file, String link);
```

### File Operations

Abstraction for file operations.
* [cfile.posix.c3](cfile.posix.c3) : functions for posix systems.
* [cfile.win32.c3](cfile.win32.c3) : functions for win32 systems.

Available functions are:

```c3
import ext::io::cfile;

cfile::File? fp = cfile::open(String file, String mode);
sz? n = fp.read(char[] buf) @dynamic;
char? c = fp.read_byte() @dynamic;
sz? n = fp.write(char[] buf) @dynamic;
void? fp.write_byte(char c) @dynamic;
sz? n = fp.readline(char[] buf);
sz? n = fp.printf(String format, args...);
void fp.flush();
void fp.close();
sz? fp.seek(long pos, int whence) maydiscard;
long? pos = fp.tell();
bool b = fp.eof();

char[]? buf = cfile::load(Allocator allocx, String file); // read whole file at once, must free(buf) later
void? cfile::save(String filename, char[] buf);
void? cfile::remove(String file) @maydiscard;
void? cfile::rename(String file, String target) @maydiscard;
void? cfile::copy(String file, String target) @maydiscard;

bool b = cfile::exists(String file);
sz? n = cfile::size(String file);
long? mtime = cfile::last_modified(String file); // missing in std lib
bool b = cfile::is_dir(String file);
bool b = cfile::is_file(String file);
bool b = cfile::is_link(String file); // missing in std lib
bool b = cfile::is_readable(String file); // missing in std lib
bool b = cfile::is_writeable(String file); // missing in std lib
bool b = cfile::is_executable(String file); // missing in std lib
sz? n = cfile::read_link(String file, char[] output); // missing in std lib
void? cfile::change_mode(String file, Mode_t mode) @maydiscard; // missing in std lib
```

### Directory/folder Operations

Abstraction for dir operations.

* [dir.posix.c3](dir.posix.c3) : functions for posix systems.
* [dir.win32.c3](dir.win32.c3) : functions for win32 systems.

Available functions are:

```c3
import ext::io::dir;

String? cwd = dir::get_cur_dir(char[] buf); // returns String representation of buf
void? dir::change_dir(String path) @maydiscard;
void? dir::make_dir(String path, bool recursive = false, CUInt mode = 0o755) @maydiscard;
void? dir::remove_dir(String path) @maydiscard;
List{String}? dir::list_dir(Allocator allocx, String path); // returned List{String} must be free'd properly

bool b = dir::exists(String path);
long? mtime = dir::last_modified(String path); // missing in std lib
bool b = dir::is_dir(String path);
bool b = dir::is_file(String path);
bool b = dir::is_link(String path); // missing in std lib
bool b = dir::is_readable(String path); // missing in std lib
bool b = dir::is_writeable(String path); // missing in std lib
sz? n = dir::read_link(String path, char[] output); // missing in std lib
void? dir::change_mode(String path, Mode_t mode) @maydiscard; // missing in std lib

DirIterator? iter = dir::scan_dir(Allocator allocx, String path);
void? iter.close() @maydiscard;
DirEntry entry = iter.next();
void? entry.free() @maydiscard;
String name = entry.name; // filename
long? mtime = entry.last_modified();
sz? size = entry.size();
bool b = entry.is_file();
bool b = entry.is_dir();
bool b = entry.is_link();
```

Back to [ext.c3l](../../README.md) library.

### Example

Examples
* [../../test/io/cfile_example.c3](../../test/io/cfile_example.c3)
* [../../test/io/scan_dir.c3](../../test/io/scan_dir.c3)

```c3
import ext::io::stat;
import std::io;

fn void check_file(String path) 
{
    if (stat::exists(path)) {
        io::printfn("File exists: %s", path);
        
        if (stat::is_dir(path)) {
            io::printfn("  Type: Directory");
        } else if (stat::is_file(path)) {
            io::printfn("  Type: File");
            
            ulong? size = stat::size(path);
            if (catch size) {
                io::printn("  Cannot get file size");
            } else {
                io::printfn("  Size: %d bytes", size);
            }
        }
        
        io::printfn("  Readable: %s", stat::is_readable(path) ? "yes" : "no");
        io::printfn("  Writable: %s", stat::is_writeable(path) ? "yes" : "no");
        io::printfn("  Executable: %s", stat::is_executable(path) ? "yes" : "no");
    }
}
```

Back to [ext.c3l](../../README.md) library.

