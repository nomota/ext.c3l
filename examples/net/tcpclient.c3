// tcpclient.c3

import std::io;
import c::stdlib;
import c::stdio;
import ext::net::tcp;

fn void main(String[] args)
{
    if (args.len <= 1) {
        io::printfn("Usage: %s run", args[0]);
        return;
    }
    
    TcpSocket? sock = tcp::new_connect("127.0.0.1", 5757);
    if (catch err = sock) {
        io::printfn("tcpclient: %s", err);
        stdlib::exit(1);
        return;
    }
    defer (void)sock.close();

    io::printfn("tcpclient: connected");
    io::printfn("tcpclient: cmds: QUIT session, HALT server");

    while (true) {
        io::printf("tcpclient: type anything\n>> ");
        String? line = io::readline(tmem);
        if (catch err = line) {
            io::printfn("tcpclient: %s", err);
            break;
        }
        if (catch err = sock.send(line)) {
            io::printfn("tcpclient: %s", err);
            break;
        }
        if (catch line.index_of_char('\n')) {
            (void)sock.send("\n");
        }
        
        char[1024] buf;
        if (catch err = sock.readline(&buf)) {
            io::printfn("tcpclient: %s", err);
            break;
        }

        stdio::printf("tcpclient: received: %s", &buf[0]);
        line.free(tmem);
    }
}
