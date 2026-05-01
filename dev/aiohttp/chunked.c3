// chunked.c3

module example;

import std::io;
import ext::asyncio;
import ext::aiohttp;


//
//  Chunked request body writer
//

fn void? write_chunks(ChunkWriter* writer)
{
    String[] chunks = {
        "Hello, ",
        "this is ",
        "chunked ",
        "request body!",
    };

    foreach (chunk : chunks) {
        writer.write(chunk)!;
        io::printfn("[client] sent chunk (%d bytes): %s", chunk.len, chunk);
    }

    writer.finish()!;
}


//
//  Chunked POST client
//

fn void client_main()
{
    ClientSession* session = aiohttp::session_new();

    String chunked = aiohttp::chunk_encode_alloc(mem, data, len);
    
    // Build a chunked POST request via a ChunkWriter callback
    ClientResponse*? resp = session.post(
        "http://127.0.0.1:8080/upload",
        chunked
    );
    
    if (catch err = resp) {
        io::printfn("[client] request failed: %s", err);
        session.close();
        return;
    }

    io::printfn("[client] status: %d", resp.status);
    io::printfn("[client] reason: %s", resp.reason);

    String? te = resp.headers.get("Transfer-Encoding");
    if (try te) {
        io::printfn("[client] Transfer-Encoding: %s", te);
    }

    String? ctype = resp.headers.get("Content-Type");
    if (try ctype) {
        io::printfn("[client] Content-Type: %s", ctype);
    }


    io::printfn("== body ==");

    String body = resp.text();
    

    io::printfn("==");

    resp.release();
    session.close();
}


//
//  Entry point
//

fn void main()
{
    @assert_leak() {
        asyncio::run(&client_main);
    };
}


/*
# Python code
# client2.py

import aiohttp
import asyncio


async def write_chunks():
    chunks = [
        b"Hello, ",
        b"this is ",
        b"chunked ",
        b"request body!",
    ]
    for chunk in chunks:
        print(f"[client] sent chunk ({len(chunk)} bytes): {chunk.decode()}")
        yield chunk


async def client_main():
    async with aiohttp.ClientSession() as session:
        try:
            async with session.post(
                "http://127.0.0.1:8080/upload",
                data=write_chunks(),
                chunked=True,
            ) as resp:
                print(f"[client] status: {resp.status}")
                print(f"[client] reason: {resp.reason}")

                te = resp.headers.get("Transfer-Encoding")
                if te is not None:
                    print(f"[client] Transfer-Encoding: {te}")

                ctype = resp.headers.get("Content-Type")
                if ctype is not None:
                    print(f"[client] Content-Type: {ctype}")

                print("== chunked body ==")

                async for chunk in resp.content.iter_chunked(1024):
                    print(f"[client] recv chunk ({len(chunk)} bytes): {chunk.decode()}")

                print("==")

        except Exception as e:
            print(f"[client] request failed: {e}")


def main():
    asyncio.run(client_main())


if __name__ == "__main__":
    main()
*/
```

---

**구조 설명:**

**송신 (chunked request)**
- `aiohttp::chunked(&write_chunks)` — 콜백을 받아 `Transfer-Encoding: chunked` POST body로 전송
- `ChunkWriter.write(chunk)` — 청크 하나 전송
- `ChunkWriter.finish()` — 종료 청크(`0\r\n\r\n`) 전송

**수신 (chunked response)**
- `resp.chunks()` — `ChunkReader` 핸들 획득 (기존 `resp.text()`는 전체 버퍼링)
- `reader.read_chunk()` — 청크 하나씩 읽기, 스트림 끝이면 `aiohttp::EOF` 반환
- `reader.release_chunk(chunk)` — 청크 메모리 해제

Python의 `async for chunk in resp.content.iter_chunked(1024)` 패턴에 대응하는 구조입니다.