// udpclient.c3

import std::io;
import c::stdlib;
import c::stdio;
import ext::net::udp;

fn void main(String[] args)
{
    if (args.len <= 1) {
        io::printfn("Usage: %s 'msg'", args[0]);
        return;
    }
    
    UdpSocket? sock = udp::new();
    if (catch err = sock) {
        io::printfn("%s", err);
        stdlib::exit(1);
        return;
    }
    defer (void)sock.close();
    (void)sock.sendto(args[1], "127.0.0.1", 5757);
    io::printfn("udpclient: sent: %s to port 5757", args[1]);
    
    char[1024] buf;
    char[64] ipb;
    ushort port;
    (void)sock.recvfrom(&buf, &ipb, &port);
    stdio::printf("udpclient: recv from:%s:%d msg:%s\n", &ipb[0], port, &buf[0]);
}
