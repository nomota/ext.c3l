import std::io;
fn void main()
{
    String s = "a";
    switch (s) {
      case "a": io::printfn("a");
    }
    
    char[] slice;
    io::printfn("%p, %d", slice.ptr, slice.len);
    mem::free(slice.ptr);
    mem::free(slice);
    mem::free(null);
    if ((void*)slice == null) {
        io::printfn("-");
        slice = mem::alloc_array(char, 10);
        mem::free(slice);
        io::printfn("%p, %d", slice.ptr, slice.len);
        // slice[0] = 'a'; // use after free
        //mem::free(slice); // double free
        slice = {};
        io::printfn("%p, %d", slice.ptr, slice.len);
    }
}