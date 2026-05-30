// udpserver.c3

import std::io;
import c::stdlib;
import ext::net::udp;

fn void main(String[] args)
{
    if (args.len < 2) {
        io::printfn("Usage: %s run &", args[0]);
        io::printfn("       run in background (&)");
        stdlib::exit(0);
    }
    
    io::printfn("udpserver: binding to port 5757");
    UdpSocket? sock = udp::new_bind(5757);
    if (catch err = sock) {
        io::printfn("udpserver: %s", err);
        return;
    }
    defer (void)sock.close();

    io::printfn("udpserver: cmds: QUIT server");
    char[1024] buf;
    char[64] ipbuf;
    ushort port;
    while (true) {
        io::printfn("udpserver: recvfrom ...");
        sz? n = sock.recvfrom(&buf, &ipbuf, &port);
        if (catch err = n) {
            io::printfn("udpserver: %s", err);
            break;
        }
        String ip = ((ZString)(&ipbuf[0])).str_view();
        String msg = ((ZString)(&buf[0])).str_view();

        io::printfn("udpserver: recv from:%s:%d msg:%s", ip, port, msg);
        msg.convert_to_upper();
        
        (void)sock.sendto((char[])msg, ip, port);
        io::printfn("udpserver: sent: %s", msg);
        if (msg == "QUIT") break;
    }
    io::printfn("udpserver: quit server");
}
