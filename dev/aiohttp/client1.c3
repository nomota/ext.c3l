// client1.c3

module example;

import std::io;
import ext::asyncio;
import ext::aiohttp;


// 
//  Simple HTTP GET client
// 

fn void client_main()
{
    ClientSession* session = aiohttp::session_new();

    ClientResponse*? resp = session.get("http://127.0.0.1:8080/");
    if (catch err = resp) {
        io::printfn("[client] request failed: %s", err);
        session.close();
        return;
    }

    io::printfn("[client] status: %d", resp.status);
    io::printfn("[client] reason: %s", resp.reason);

    String? server = resp.headers.get("Server");
    if (try server) {
        io::printfn("[client] server: %s", server);
    }

    String? text = resp.text();
    if (catch err = text) {
        io::printfn("[client] read body failed: %s", err);
        resp.release();
        session.close();
        return;
    }

    io::printfn("== body ==");
    io::printfn("%s", text);
    io::printfn("==");

    resp.release();
    session.close();
}


// 
//  Entry point
// 

fn void main()
{
    asyncio::run(&client_main);
}

/*
# Python code
# client1.py

import aiohttp
import asyncio

async def client_main():
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get("http://127.0.0.1:8080/") as resp:
                print(f"[client] status: {resp.status}")
                print(f"[client] reason: {resp.reason}")

                server = resp.headers.get("Server")
                if server is not None:
                    print(f"[client] server: {server}")

                try:
                    text = await resp.text()
                except Exception as e:
                    print(f"[client] read body failed: {e}")
                    return

                print("== body ==")
                print(text)
                print("==")

        except Exception as e:
            print(f"[client] request failed: {e}")


def main():
    asyncio.run(client_main())


if __name__ == "__main__":
    main()
*/