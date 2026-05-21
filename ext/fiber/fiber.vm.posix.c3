// fiber.vm.posix.c3

// Virtual-memory stack alloc/free
//
// Note: Each stack takes 2 vm map counts.
//   default vm.max_map_count == 65_536
//   This limits max 32_573 stacks.
//   Use following commands to increase:
//       sudo sysctl -w vm.max_map_count=262144
//   or
//       echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-fiber.conf && sudo sysctl --system
//
// Nomota <hiongun@gmail.com>; MIT License

module ext::fiber::vm @if(env::POSIX);

import c::unistd;
import c::sys::mman;

//
// Constants 
//

const usz MIN_STACK_SIZE @private = 65_536;

fn void init() @init 
{

}

fn void deinit()
{

}

//
// Low-level VM stack helpers
//

fn usz page_size() @private
{
    long p = unistd::sysconf(unistd::_SC_PAGESIZE);
    if (p <= 0) return 4096;
    return (usz)p;
}

fn usz align_up(usz n, usz a) @inline @private
{
    return (n + a - 1) & ~(a - 1);
}

faultdef MMAP_FAILED, MPROTECT_FAILED;
fn char*? stack_alloc(
    usz requested_stack_size,
    usz* out_block_size,
    char** out_stack_low,
    char** out_stack_high,
    usz* out_stack_size
)
{
    usz ps = page_size();

    if (requested_stack_size < MIN_STACK_SIZE)
    {
        requested_stack_size = MIN_STACK_SIZE;
    }

    usz usable_size = align_up(requested_stack_size, ps);
    usz total_size = usable_size + ps;

    void* p = mman::mmap(
        null,
        total_size,
        mman::PROT_NONE,
        mman::MAP_PRIVATE | mman::MAP_ANONYMOUS,
        -1,
        0
    );

    if ((iptr)p == mman::MAP_FAILED || p == null)
    {
        return MMAP_FAILED~;
    }

    char* block = (char*)p;
    char* stack_low = block + ps;
    char* stack_high = stack_low + usable_size;

    int rc = mman::mprotect(
        stack_low,
        usable_size,
        mman::PROT_READ | mman::PROT_WRITE
    );

    if (rc != 0)
    {
        mman::munmap(block, total_size);
        return MPROTECT_FAILED~;
    }

    *out_block_size = total_size;
    *out_stack_low = stack_low;
    *out_stack_high = stack_high;
    *out_stack_size = usable_size;

    return block;
}

fn void stack_free(char* block, usz block_size)
{
    if (block == null || block_size == 0) return;
    mman::munmap(block, block_size);
}

