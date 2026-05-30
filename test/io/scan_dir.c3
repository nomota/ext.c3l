// scan_dir.c3

module scan_dir;

import std::io;
import ext::io::dir;


fn void? list_dir(String path, int depth = 0) @maydiscard
{
    DirIterator? iter = dir::scan_dir(mem, path);
    if (catch err = iter) {
        io::printfn("%*s[error opening: %s] %s", depth * 2, "", path, err);
        return;
    }
    defer iter.close();

    while (true) {
        DirEntry? entry = iter.next();
        if (catch err = entry) break;
        defer entry.free();

        String name = entry.name;
        if (name == "." || name == "..") continue;
        
        if (entry.is_dir()) {
            io::printfn("%*s[DIR]  %s/", depth*2, "", name);

            @pool() {
                DString subpath;
                subpath.appendf("%s/%s", path, name);
                list_dir(subpath.str_view(), depth + 1);
            };

        } else if (entry.is_link()) {
            io::printfn("%*s[LNK]  %s", depth*2, "", name);

        } else if (entry.is_file()) {
            long mtime = entry.last_modified()!;
            io::printfn("%*s[FILE] %s  (mtime=%d)", depth*2, "", name, mtime);
        }
    }
}

fn void main()
{
  @assert_leak() {
    list_dir("..")!!;
  };
}
