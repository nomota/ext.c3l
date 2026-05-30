all:
	@echo make build
	@echo make clean

build:
	@make test_pipe
	@make test_echo
	@make test_echo_thread
	@make test_udp
	@make test_waker
	@make test_addr
	@make test_wepoll_basic
	
clean:
	-@rm -f x y *.exe *.pdb
	-@rm -f test_pipe
	-@rm -f test_echo
	-@rm -f test_echo_thread
	-@rm -f test_udp
	-@rm -f test_waker
	-@rm -f test_addr
	-@rm -f test_wepoll_basic

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
MIO = mio.c3 mio.epoll.c3 mio.posix.c3 mio.wsapoll.c3 mio.win32.c3

LIBS = $(MIO) $(MEM) $(LIBC)

SAN = --sanitize=address
SAN = --target windows-x64
# SAN = 

test_pipe: test_pipe.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_echo: test_echo.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_echo_thread: test_echo_thread.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_udp: test_udp.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_waker: test_waker.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_addr: test_addr.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_wepoll_basic: test_wepoll_basic.c3 wepoll.impl.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
