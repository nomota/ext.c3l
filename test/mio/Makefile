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
	@make test_error_paths
	@make test_multi_udp_batch
	
clean:
	-@rm -f x y *.exe *.pdb
	-@rm -f test_pipe
	-@rm -f test_echo
	-@rm -f test_echo_thread
	-@rm -f test_udp
	-@rm -f test_waker
	-@rm -f test_addr
	-@rm -f test_error_paths
	-@rm -f test_multi_udp_batch

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
WEPOLL = $(EXT)/wepoll/*.c3
MIO = $(EXT)/mio/*.c3

LIBS = $(WEPOLL) $(MIO) $(MEM) $(LIBC)

SAN = --sanitize=address
SAN = --target windows-x64
SAN = 

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

test_error_paths: test_error_paths.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_multi_udp_batch: test_multi_udp_batch.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
