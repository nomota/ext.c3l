// tcpserver.c3

import std::io;
import c::stdlib;
import ext::net::tcp;

fn void main(String[] args)
{
    if (args.len < 2) {
        io::printfn("Usage: %s run &", args[0]);
        io::printfn("       run in background (&)");
        stdlib::exit(0);
    }
    
    TcpSocket? sock = tcp::new_listen(5757);
    if (catch err = sock) {
        io::printfn("tcpserver: %s", err);
        return;
    }
    defer (void)sock.close();

    bool halt = false;
    while (!halt) {
        io::printfn("tcpserver: accepting port 5757...");
        char[64] ipbuf;
        ushort port;
        TcpSocket? s = sock.accept(&ipbuf, &port);
        if (catch err = s) {
            io::printfn("tcpserver: %s", err);
            break;
        }
    
        String ip = ((ZString)(&ipbuf[0])).str_view();
        io::printfn("tcpserver: connect from %s:%d (no new thread)", ip, port);
        io::printfn("tcpserver: cmds: QUIT session, HALT server");
        char[1024] buf;
        while (true) {
            io::printfn("tcpserver: readline ...");
            sz? n = s.readline(&buf);
            if (catch err = n) {
                io::printfn("tcpserver: %s", err);
                break;
            }
            buf[n] = '\0';
            String msg = ((ZString)(&buf[0])).str_view();

            io::printf("tcpserver: from:%s:%d msg:%s", ip, port, msg);
            msg.convert_to_upper();
        
            (void)s.send((char[])msg);
            if (catch msg.index_of_char('\n')) {
                (void)s.send("\n");
            }
            
            io::printf("tcpserver: sent:%s", msg);
            if (msg.starts_with("QUIT")) break;
            if (msg.starts_with("HALT")) {
                halt = true;
                break;
            }
        }
        io::printfn("tcpserver: close accepted connection");
        (void)s.close();
    }
    io::printfn("tcpserver: halt server");
}
