
//  file.win32.c3

module ext::io::cfile @if(env::WIN32);

import c::windows;
import c::winbase;
import c::errno;
import c::stdio;
import ext::io::stat;
import c::sys::stat;
import ext::mem;
import ext::debug;

tlocal LocalAllocator localmem = {};

struct File
{
    windows::Handle fp;
}

fn Char16*? utf8to16(String path, Char16[] wpath) @private
{
    if (path.len == 0) return errno::F_INVAL~;
    Char16[] p2 = path.to_utf16(tmem)!;
    // defer free(p2);
    
    if (p2.len >= wpath.len-1) return errno::F_BAD_LENGTH~;
    
    wpath[0:p2.len] = p2[0:p2.len];
    wpath[p2.len] = 0;
    for (usz i = 0; i < p2.len; i++) {
        if (p2[i] == (Char16)'/') {
            wpath[i] = (Char16)'\\';
        }
    }
    
    return wpath.ptr;
}

fn File? open(String fname, String mode) 
{
    Char16[512] namebuf;
    Char16* name = utf8to16(fname, &namebuf)!;

    winbase::DWord access = 0;
    winbase::DWord disposition = 0;
    winbase::DWord attributes = winbase::FILE_ATTRIBUTE_NORMAL;

    if (mode == "r" || mode == "rb") {
        access = winbase::GENERIC_READ;
        disposition = winbase::OPEN_EXISTING;
    } else if (mode == "r+") {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::OPEN_EXISTING;
    } else if (mode == "w" || mode == "wb") {
        access = winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    } else if (mode == "w+") {
        access = winbase::GENERIC_READ | winbase::GENERIC_WRITE;
        disposition = winbase::CREATE_ALWAYS;
    } else if (mode == "a" || mode == "ab") {
        access = winbase::FILE_APPEND_DATA; // or GENERIC_WRITE
        disposition = winbase::OPEN_ALWAYS;
    } else if (mode == "a+") {
        access = winbase::GENERIC_READ | winbase::FILE_APPEND_DATA;
        disposition = winbase::OPEN_ALWAYS;
    } else {
        return errno::E_INVALID_ARG~;
    }
    
    winbase::DWord share = winbase::FILE_SHARE_READ;
   
    File f;
    f.fp = windows::createFileW(name, access, share, null, disposition, 0, null);
    if (f.fp == windows::INVALID_HANDLE_VALUE) return errno::get_fault()~;
    
    // For append mode, seek to end
    if (mode[0] == 'a') {
        windows::setFilePointerEx(f.fp, 0, null, windows::FILE_END);
    }
    
    return f;
}

fn usz? File.read(&self, char[] buf) @dynamic
{
    uint bytes_read;
    windows::Bool success = windows::readFile(self.fp, buf.ptr, (uint)buf.len, &bytes_read, null);
    if (!success) return errno::get_fault()~;
    if (bytes_read == 0) return errno::EOF~;
    return (usz)bytes_read;
}

fn char? File.read_byte(&self) @dynamic
{
    char c;
    uint read;
    if (!windows::readFile(self.fp, &c, 1, &read, null) || read == 0) return errno::EOF~;
    return c;
}

fn usz? File.readline(&self, char[] buf)
{
    usz idx = 0;
    while (idx < buf.len - 1) {
        char c;
        uint bytes_read;
        windows::Bool success = windows::readFile(self.fp, &c, 1, &bytes_read, null);
        if (!success) return errno::get_fault()~;
        if (bytes_read == 0) {
            if (idx == 0) return errno::EOF~;
            break;
        }
        buf[idx++] = c;
        if (c == '\n') break;
    }
    buf[idx] = 0;
    return idx;
}

fn usz? File.write(&self, char[] buf) @dynamic
{
    uint bytes_written;
    windows::Bool success = windows::writeFile(self.fp, buf.ptr, (uint)buf.len, &bytes_written, null);
    if (!success) return errno::get_fault()~;
    return (usz)bytes_written;
}

fn void? File.write_byte(&self, char c) @dynamic
{
    uint written;
    if (!windows::writeFile(self.fp, &c, 1, &written, null) || written == 0)
    {
        return errno::get_fault()~;
    }
}

fn void? File.close(&self) @dynamic @maydiscard
{
    windows::closeHandle(self.fp);
}

fn void File.flush(&self)
{
    windows::flushFileBuffers(self.fp);
}

fn usz? File.printf(&self, String fmt, args...)
{
    // Format to temporary buffer
    DString str; // str.init(mem);
    // defer str.free();
    str.appendf(fmt, ...args);
    
    // Write formatted string
    uint bytes_written;
    windows::Bool success = windows::writeFile(self.fp, str.str_view().ptr, (uint)str.len(), &bytes_written, null);
    if (!success) return errno::get_fault()~;
    return (usz)bytes_written;
}

fn usz? File.seek(&self, long pos, int whence) @dynamic @maydiscard
{
    uint move_method;
    switch (whence) {
        case 0: move_method = windows::FILE_BEGIN;
        case 1: move_method = windows::FILE_CURRENT;
        case 2: move_method = windows::FILE_END;
        default: return errno::F_INVAL~;
    }
    
    windows::Bool ok = windows::setFilePointerEx(self.fp, pos, null, move_method);
    if (! ok) return errno::get_fault()~;
    return self.tell();
}

fn long? File.tell(&self) @dynamic
{
    long pos;
    windows::Bool success = windows::setFilePointerEx(self.fp, 0, &pos, windows::FILE_CURRENT);
    if (!success) return errno::get_fault()~;
    return pos;
}

fn bool File.eof(&self) 
{
    long pos = windows::setFilePointer(self.fp, 0, null, windows::FILE_CURRENT);
    long size = windows::getFileSize(self.fp, null);
    return pos >= size;
}

fn char[]? load(Allocator allocx, String file)
{
    localmem = allocx;
    
    long n = size(file)!;
    
    char[] buf = localmem.alloc_array(char, n)!;
    defer (catch err) { free(buf); }
    
    File fp = open(file, "r")!;
    defer fp.close();
    long i = 0;
    while (i < n) {
        usz? r = fp.read(buf[i..n-1]);
        if (catch err = r) {
            if (err == errno::EOF) break;
            return err~;
        }
        i += r;
    }
    assert(i == n);
    return buf;
}

fn void? save(String filename, char[] data)
{
	File file = open(filename, "w")!;
	defer (void)file.close();
	while (data.len)
	{
		usz written = file.write(data)!;
		data = data[written..];
	}
}

fn void? remove(String fname) @maydiscard
{
    Char16[512] namebuf;
    Char16* name = utf8to16(fname, &namebuf)!;

    windows::Bool success = windows::deleteFileW(name);
    if (!success) return errno::get_fault()~;
}

fn void? rename(String fname, String fname2) @maydiscard
{
    Char16[512] namebuf;
    Char16* name = utf8to16(fname, &namebuf)!;

    Char16[512] namebuf2;
    Char16* name2 = utf8to16(fname2, &namebuf2)!;

    windows::Bool success = windows::moveFileW(name, name2);
    if (!success) return errno::get_fault()~;
}

fn void? copy(String fname, String fname2) @maydiscard
{
    char[] buf = load(tmem, fname)!;
    // defer free(buf);
    
    File fp = open(fname2, "w")!;
    defer fp.close();
    
    long i = 0;
    while (i < buf.len) {
        usz r = fp.write(buf[i..buf.len-1])!;
        i += r;
    }
}

fn usz? size(String file) => stat::size(file);

fn bool exists(String file) => stat::exists(file);

fn long? last_modified(String file) => stat::last_modified(file);

fn bool is_dir(String file) => stat::is_dir(file);
fn bool is_file(String file) => stat::is_file(file);
fn bool is_link(String file) => stat::is_link(file);

fn bool is_readable(String file) => stat::is_readable(file);
fn bool is_writeable(String file) => stat::is_writeable(file);
fn bool is_executable(String file) => stat::is_executable(file);

fn usz? read_link(String link, char[] output) => stat::read_link(link, output);
fn void? change_mode(String file, Mode_t mode) @maydiscard => stat::change_mode(file, mode);
