// fiber.vm.win32.c3

// Windows virtual-memory stack alloc/free.
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber::vm @if(env::WIN32);

import c::windows;
import c::memoryapi;
import c::winnt;

//
// Constants
//

const sz MIN_STACK_SIZE @private = 65_536;

//
// Init / deinit
//

fn void init() @init
{
}

fn void deinit()
{
}

//
// Low-level helpers
//

fn sz page_size() @private
{
    SystemInfo info = {};
    windows::getSystemInfo(&info);

    if (info.dwPageSize == 0) return 4096;

    return (sz)info.dwPageSize;
}

fn sz align_up(sz n, sz a) @inline @private
{
    return (n + a - 1) & ~(a - 1);
}

//
// Stack allocation
//

faultdef VIRTUALALLOC_FAILED;

fn char*? stack_alloc(
    sz requested_stack_size,
    sz* out_block_size,
    char** out_stack_low,
    char** out_stack_high,
    sz* out_stack_size
)
{
    sz ps = page_size();

    if (requested_stack_size < MIN_STACK_SIZE)
    {
        requested_stack_size = MIN_STACK_SIZE;
    }

    sz usable_size = align_up(requested_stack_size, ps);
    sz total_size = usable_size + ps;

    //
    // Reserve the whole region first.
    //
    // Layout:
    //
    //     [ reserved/no-access guard page ][ committed RW stack ]
    //
    void* p = memoryapi::virtualAlloc(
        null,
        total_size,
        winnt::MEM_RESERVE,
        winnt::PAGE_NOACCESS
    );

    if (p == null) return VIRTUALALLOC_FAILED~;;

    char* block = (char*)p;
    char* stack_low = block + ps;
    char* stack_high = stack_low + usable_size;

    void* committed = memoryapi::virtualAlloc(
        stack_low,
        usable_size,
        winnt::MEM_COMMIT,
        winnt::PAGE_READWRITE
    );

    if (committed == null)
    {
        memoryapi::virtualFree(block, 0, winnt::MEM_RELEASE);
        return VIRTUALALLOC_FAILED~;
    }

    *out_block_size = total_size;
    *out_stack_low = stack_low;
    *out_stack_high = stack_high;
    *out_stack_size = usable_size;

    return block;
}

fn void stack_free(char* block, sz block_size)
{
    if (block == null || block_size == 0) return;

    memoryapi::virtualFree(block, 0, winnt::MEM_RELEASE);
}