// aiofiles.tempfile.c3

// asyncio-friendly
// temporaryFile(), temporaryDirectory()
// cleans up on close()

// Nomota <hiongun@gmail.com>; MIT License

module ext::aiofiles::tempfile; // @link("glibc");

import c::stdlib;
import c::stdio;
import c::string;
import c::unistd;
import c::processthreadapi;
import c::pthread;
import std::time;
import std::collections::list;
import ext::debug;
import ext::mem;
import ext::io::dir;
import ext::io::cfile;
import ext::asyncio;
import ext::aiofiles;
import ext::aiofiles::os::path;

// no boundary check, buf must be enough
fn String bcat(char[] buf, String... args)
{
    usz n = 0;
    foreach (arg: args) {
        buf[n:arg.len] = arg[0:arg.len];
        n += arg.len;
    }
    buf[n] = 0;
    return (String) buf[0:n];
}

struct AioTempFile {
    inline AioFile file;
    String name; // owened, must free
    String fullpath; // owened, must free
    bool closed;
}

fn String sys_temp_dir() @private
{
    $if env::WIN32:
        char* tmp = stdlib::getenv("TMPDIR");
        if (tmp == null) tmp = stdlib::getenv("TEMP");
        usz n = (usz)string::strlen(tmp);
        
        char[512] buf;
        String path = bcat(&buf, (String)tmp[0:n], "\\_aio_");

        dir::make_dir(path, true);
        return (String)tmp[0:n];
    $else
        dir::make_dir("/tmp/_aio_");
        return "/tmp";
    $endif
}

fn String get_temp_name() @private
{
    static int count = 0;
    ulong now = (ulong)time::now();

  $if env::WIN32:
    uint pid = (uint)processthreadapi::getCurrentProcessId();
    uint tid = (uint)processthreadapi::getCurrentThreadId();
  $else
    uint pid = (uint)unistd::getpid();
    uint tid = (uint)unistd::gettid();
  $endif
 
    return string::tformat("%x.%x.%x.%x", now, pid, tid, count++);
}

fn AioTempFile? temporaryFile()
{
    String fname = get_temp_name();
    String tdir = sys_temp_dir();
    
    char[1024] pbuf;
    String fullpath = bcat(&pbuf, tdir, "/_aio_/", fname);
    
    AioFile file = aiofiles::open(fullpath, "w+")!;

    return { .file = file, .name = mem_copy_str(fname), .fullpath = mem_copy_str(fullpath), .closed = false };
}

fn void AioTempFile.close_handle(&self)
{
    if (self.closed) return;
    self.file.close();
    self.closed = true;
}

fn void AioTempFile.close(&self)
{
    self.close_handle();

    mem_free(self.name);

    if (path::exists(self.fullpath)) {
        os::remove(self.fullpath);
    }

    mem_free(self.fullpath);
}

struct AioTempDir {
    String fullpath; // owened, must free
}

fn AioTempDir temporaryDirectory()
{
    String fname = get_temp_name();
    String tdir = sys_temp_dir();
    
    char[1024] pbuf;
    String fullpath = bcat(&pbuf, tdir, "/_aio_/", fname);

    os::makedirs(fullpath);
    
    return { .fullpath = mem_copy_str(fullpath) };
}

faultdef NONE;

struct Arg {
    String path;
    fault error;
}

/*
fn fault _clean_dir_in(String path)
=> @pool()
{
    List{String}? files = dir::list_dir(tmem, path);
    if (catch err = files) {
        return err;
    }
/*
    defer {
        foreach (file: files) {
            file.free(mem);
        }
        files.free();
    };
*/
    foreach (file: files) {
        //char[1024] pbuf;
        //String fullpath = bcat(&pbuf, path, "/", file);
        String fullpath = string::tformat("%s/%s", path, file);
        if (dir::is_file(fullpath)) {
            cfile::remove(fullpath);
        } else if (dir::is_link(fullpath)) {
            cfile::remove(fullpath);
        } else if (dir::is_dir(fullpath)) {
stdio::printf("==> fullpath: %.*s\n", fullpath.len, fullpath.ptr);
            fault error = NONE;
            error = _clean_dir_in(fullpath);
            
            if (error != NONE) {
                return error;
            }
        }
    }

    if (catch err = dir::remove_dir(path)) {
        return err;
    }

    return NONE;
}
*/

struct CleanNode {
    String path;        // owned
    bool expanded;
    CleanNode* next;
}

fn String _path_join_owned(String a, String b) @private
{
    usz n = a.len + 1 + b.len;
    char* p = mem_malloc(n + 1);

    string::memcpy(p, a.ptr, a.len);
    p[a.len] = '/';
    string::memcpy(p + a.len + 1, b.ptr, b.len);
    p[n] = 0;

    return (String)p[0:n];
}

fn void _clean_stack_push(CleanNode** head, String path, bool expanded) @private
{
    CleanNode* node = mem_alloc(CleanNode);
    node.path = mem_copy_str(path);
    node.expanded = expanded;
    node.next = *head;
    *head = node;
}

fn bool _clean_stack_pop(CleanNode** head, String* path, bool* expanded) @private
{
    if (*head == null) return false;

    CleanNode* node = *head;
    *head = node.next;

    *path = node.path;
    *expanded = node.expanded;
    mem_free(node);

    return true;
}

// non recursive
fn fault _clean_dir_in(String root)
{
    CleanNode* stack = null;

    _clean_stack_push(&stack, root, false);

    while (stack != null) {
        String path;
        bool expanded;
        _clean_stack_pop(&stack, &path, &expanded);

        if (expanded) {
            if (catch err = dir::remove_dir(path)) {
                path.free(mem);
                while (stack != null) {
                    String p;
                    bool e;
                    _clean_stack_pop(&stack, &p, &e);
                    p.free(mem);
                }
                return err;
            }

            path.free(mem);
            continue;
        }

        List{String}? files = dir::list_dir(mem, path);
        if (catch err = files) {
            path.free(mem);
            while (stack != null) {
                String p;
                bool e;
                _clean_stack_pop(&stack, &p, &e);
                p.free(mem);
            }
            return err;
        }

        // 자식들 처리 후 자기 자신을 지워야 하므로 다시 push
        _clean_stack_push(&stack, path, true);

        foreach (file: files) {
            String fullpath = _path_join_owned(path, file);

            if (!dir::is_link(fullpath) && dir::is_dir(fullpath)) {
                _clean_stack_push(&stack, fullpath, false);
                fullpath.free(mem);
            } else {
                if (catch err = cfile::remove(fullpath)) {
                    fullpath.free(mem);

                    foreach (f: files) {
                        f.free(mem);
                    }
                    files.free();

                    while (stack != null) {
                        String p;
                        bool e;
                        _clean_stack_pop(&stack, &p, &e);
                        p.free(mem);
                    }
                    return err;
                }
                fullpath.free(mem);
            } 
        }

        foreach (file: files) {
            file.free(mem);
        }
        files.free();

        path.free(mem);
    }

    return NONE;
}

fn void* _clean_dir(void* arg)
{
    Arg* a = (Arg*) arg;

    a.error = _clean_dir_in(a.path);

    return (void*) a;
}

fn void? clean_dir(String path) @maydiscard @private
{
    Arg *arg = mem_alloc(Arg); defer mem_free(arg);
    *arg = { .path = path, .error = NONE };
    
    Arg*? a = asyncio::run_in_executor(&_clean_dir, arg);

    if (catch err = a) {
        return err~;
    }

    if (a.error != NONE) {
        return a.error~;
    }
}

fn void? AioTempDir.close(&self) @maydiscard
{
    clean_dir(self.fullpath)!;
    mem_free(self.fullpath);
}
