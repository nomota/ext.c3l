// util.chunk.c3

module ext::aiohttp;

// HTTP/1.1 Transfer-Encoding: chunked codec.
//
// Encoding (sender side):
//   chunk_encode()       : wrap a single data buffer as one chunk frame
//   chunk_encode_final() : emit the terminal zero-length chunk + trailing CRLF
//
// Decoding (receiver side):
//   ChunkDecoder         : streaming state machine — feed raw bytes, pull decoded frames
//   ChunkDecoder.feed()  : push received bytes into the decoder
//   ChunkDecoder.next()  : pull next decoded payload slice (zero-copy into feed buffer)
//   ChunkDecoder.done()  : true after the terminal chunk has been consumed
//
// Wire format (RFC 9112 §7.1):
//   chunked-body  = *chunk last-chunk trailer-section CRLF
//   chunk         = chunk-size [ chunk-ext ] CRLF chunk-data CRLF
//   chunk-size    = 1*HEXDIG
//   last-chunk    = 1*("0") CRLF CRLF
//
// Notes:
//   chunk-ext fields (";name=value") are accepted and silently discarded.
//   Trailer headers after the last chunk are accepted and silently discarded.
//   Maximum single chunk size: 0xFFFFFFFFFFFFFFFF (usz max).

//  faults 

faultdef
    INVALID_SIZE_LINE,   // chunk-size line is malformed
    CHUNK_TOO_LARGE,     // parsed size exceeds platform usz max
    INCOMPLETE,          // need more data (not an error — caller should feed more)
    OVERFLOW;            // internal ring buffer is full


//  private helpers 

const char[16] CHUNK_HEX @private = "0123456789abcdef";

// Format usz n as lowercase hex into buf[]. Returns number of chars written.
fn usz fmt_hex(char* buf, usz n) @private
{
    if (n == 0) { buf[0] = '0'; return 1; }
    char[16] tmp;
    usz len = 0;
    usz v = n;
    while (v > 0) { tmp[len++] = CHUNK_HEX[v & 0xF]; v >>= 4; }
    // reverse
    for (usz i = 0; i < len; i++) buf[i] = tmp[len - 1 - i];
    return len;
}

// Parse a hex digit. Returns 0xFF on invalid input.
fn char hex_val(char c) @private @inline
{
    if (c >= '0' && c <= '9') return (char)(c - '0');
    if (c >= 'a' && c <= 'f') return (char)(c - 'a' + 10);
    if (c >= 'A' && c <= 'F') return (char)(c - 'A' + 10);
    return 0xFF;
}

//  encoding 

// Return the number of bytes chunk_encode() will write for a payload of data_len.
fn usz chunk_encoded_size(usz data_len)
{
    // hex digits for size + CRLF + data + CRLF
    usz hex_digits = 1;
    usz v = data_len;
    while (v >= 16) { hex_digits++; v >>= 4; }
    return hex_digits + 2 + data_len + 2;
}

// Write one chunk frame into out[].
// out must be at least chunk_encoded_size(data_len) bytes.
// Returns number of bytes written.
// Passing data_len == 0 writes the terminal chunk (same as chunk_encode_final).
fn usz chunk_encode(char* out, char* data, usz data_len)
{
    usz j = 0;

    // chunk-size in hex
    char[16] hex;
    usz hex_len = fmt_hex(&hex[0], data_len);
    for (usz i = 0; i < hex_len; i++) out[j++] = hex[i];

    // CRLF after size line
    out[j++] = '\r'; out[j++] = '\n';

    // payload
    for (usz i = 0; i < data_len; i++) out[j++] = data[i];

    // CRLF after data
    out[j++] = '\r'; out[j++] = '\n';

    return j;
}

// Write only the terminal chunk ("0\r\n\r\n") into out[].
// out must be at least 5 bytes.
// Returns 5.
fn usz chunk_encode_final(char* out)
{
    out[0] = '0';
    out[1] = '\r'; out[2] = '\n';
    out[3] = '\r'; out[4] = '\n';
    return 5;
}

// Allocator-based convenience wrappers.

// Encode one data buffer as a chunk. Returns the allocated frame. Caller must free.
fn String chunk_encode_alloc(Allocator alloc, char* data, usz data_len)
{
    localmem = alloc;
    
    usz out_size = chunk_encoded_size(data_len);
    char* buf = localmem.malloc(out_size);
    usz written = chunk_encode(buf, data, data_len);
    return (String) buf[0:written];
}

//  decoding state machine 
//
// The decoder is a push/pull state machine:
//
//   while (stream has bytes) {
//       decoder.feed(buf, n);                  // push raw bytes
//       ChunkFrame frame;
//       while (decoder.next(&frame)) {         // pull decoded slices
//           if (frame.is_final) break;
//           process(frame.data, frame.data_len);
//       }
//   }
//
// ChunkFrame.data is a pointer into the internal ring buffer — copy it before
// the next feed() call if you need to keep it alive longer.

const usz CHUNK_RING_SIZE @private = 32_000; // must be power of two
const usz CHUNK_RING_MASK @private = CHUNK_RING_SIZE - 1;

enum ChunkState : char @private {
    SIZE_LINE,   // reading "hex-size [ext] CRLF"
    DATA,        // reading payload bytes
    DATA_CRLF,   // consuming the CRLF after payload
    TRAILER,     // consuming trailer lines after last-chunk
    DONE,        // terminal chunk fully consumed
}

struct ChunkFrame {
    char* data;      // pointer into decoder's internal buffer (not owned)
    usz   data_len;
    bool  is_final;  // true for the terminal zero-length chunk
}

struct ChunkDecoder {
    // ring buffer holding raw fed bytes
    char[CHUNK_RING_SIZE] ring;
    usz r_head;   // read position
    usz r_tail;   // write position (r_tail - r_head = bytes available)

    // parser state
    ChunkState state;
    usz chunk_remaining;  // bytes left in current DATA phase
}

fn void ChunkDecoder.init(&self)
{
    self.r_head = 0;
    self.r_tail = 0;
    self.state  = ChunkState.SIZE_LINE;
    self.chunk_remaining = 0;
}

// Number of bytes currently buffered.
fn usz ChunkDecoder.buffered(&self) @inline
{
    return self.r_tail - self.r_head;
}

// Read one byte from the ring without advancing. Returns false if empty.
fn bool ChunkDecoder.peek(&self, usz offset, char* out) @inline
{
    if (offset >= self.buffered()) return false;
    *out = self.ring[(self.r_head + offset) & CHUNK_RING_MASK];
    return true;
}

// Consume n bytes from the ring (advance read head).
fn void ChunkDecoder.consume(&self, usz n) @inline
{
    self.r_head += n;
}

// Push raw bytes into the decoder's ring buffer.
// Returns OVERFLOW if there is not enough space.
fn void? ChunkDecoder.feed(&self, char* data, usz len)
{
    usz avail = CHUNK_RING_SIZE - self.buffered();
    if (len > avail) return OVERFLOW~;
    for (usz i = 0; i < len; i++) {
        self.ring[self.r_tail & CHUNK_RING_MASK] = data[i];
        self.r_tail++;
    }
}

// Pull the next decoded chunk frame.
// Returns true and fills *out when a complete frame is available.
// Returns false when more data is needed (call feed() then next() again).
// Returns INVALID_SIZE_LINE on a malformed size line.
fn bool ChunkDecoder.next(&self, ChunkFrame* out)
{
    while (true) {
        switch (self.state) {

        //  SIZE_LINE: scan for CRLF, parse hex size 
        case ChunkState.SIZE_LINE:
            usz avail = self.buffered();

            // find "\r\n" in buffered bytes
            usz line_len = 0;
            bool found_crlf = false;
            for (usz i = 0; i + 1 < avail; i++) {
                char a; char b;
                self.peek(i,     &a);
                self.peek(i + 1, &b);
                if (a == '\r' && b == '\n') { line_len = i; found_crlf = true; break; }
            }
            if (!found_crlf) return false; // need more data

            // parse hex digits up to ';' (chunk-ext) or '\r'
            usz size = 0;
            bool got_digit = false;
            for (usz i = 0; i < line_len; i++) {
                char c; self.peek(i, &c);
                if (c == ';') break; // start of chunk-ext — stop here
                char v = hex_val(c);
                if (v == 0xFF) {
                    // invalid hex char
                    self.consume(line_len + 2);
                    return false; // caller checks ChunkError via feed path
                }
                // overflow guard (usz is 64-bit on modern targets)
                if (size > ((usz)0xFFFFFFFFFFFFFFFF >> 4)) {
                    self.consume(line_len + 2);
                    return false;
                }
                size = (size << 4) | (usz)v;
                got_digit = true;
            }

            self.consume(line_len + 2); // consume size line + CRLF

            if (!got_digit) return false; // malformed

            if (size == 0) {
                // terminal chunk — enter trailer scanning
                self.state = ChunkState.TRAILER;
                out.data      = null;
                out.data_len  = 0;
                out.is_final  = true;
                // fall through to TRAILER in next iteration
                continue;
            }

            self.chunk_remaining = size;
            self.state = ChunkState.DATA;
            continue;

        //  DATA: expose contiguous slice from the ring 
        case ChunkState.DATA:
            usz avail = self.buffered();
            if (avail == 0) return false;

            usz take = self.chunk_remaining < avail ? self.chunk_remaining : avail;

            // expose a contiguous slice — ring may wrap, so we can only
            // safely expose up to the end of the backing array.
            usz ring_pos  = self.r_head & CHUNK_RING_MASK;
            usz contig    = CHUNK_RING_SIZE - ring_pos; // bytes before wrap
            if (take > contig) take = contig;

            out.data      = &self.ring[ring_pos];
            out.data_len  = take;
            out.is_final  = false;

            self.consume(take);
            self.chunk_remaining -= take;

            if (self.chunk_remaining == 0) self.state = ChunkState.DATA_CRLF;
            return true;

        //  DATA_CRLF: consume the CRLF that follows chunk payload 
        case ChunkState.DATA_CRLF:
            if (self.buffered() < 2) return false;
            self.consume(2); // skip "\r\n"
            self.state = ChunkState.SIZE_LINE;
            continue;

        //  TRAILER: scan and discard trailer lines until blank line 
        case ChunkState.TRAILER:
            // trailer ends with a blank line: "\r\n" on its own
            usz avail = self.buffered();
            usz i = 0;
            while (i + 1 < avail) {
                char a; char b;
                self.peek(i,     &a);
                self.peek(i + 1, &b);
                if (a == '\r' && b == '\n') {
                    self.consume(i + 2);
                    if (i == 0) {
                        // blank line — end of trailers
                        self.state = ChunkState.DONE;
                        out.data     = null;
                        out.data_len = 0;
                        out.is_final = true;
                        return true;
                    }
                    // non-blank trailer line — keep scanning
                    avail -= (i + 2);
                    i = 0;
                    continue;
                }
                i++;
            }
            return false; // need more data

        //  DONE 
        case ChunkState.DONE:
            return false;
        }
    }
}

// True after the terminal chunk has been fully consumed.
fn bool ChunkDecoder.done(&self) @inline
{
    return self.state == ChunkState.DONE;
}
