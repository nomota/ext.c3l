all:
	@echo make build
	@echo make clean

build:
	@make test1
	@make test_pipe
	@make test_pipe_stream
	@make test_echo_server
	@make test_tcp_echo
	@make test_shutdown
	@make test_read_timeout
	@make test_timeout_all
	@make test_server_closeall
	@make test_taskgroup
	@make test_buffered
	@make test_datagram_echo
	@make test_primitives
	@make test_file
	@make test_executor
	@make test_path
	@make test_handler
	
clean:
	-@rm -f x y *.exe *.pdb
	-@rm -f test1
	-@rm -f test_pipe
	-@rm -f test_pipe_stream
	-@rm -f test_echo_server
	-@rm -f test_tcp_echo
	-@rm -f test_shutdown
	-@rm -f test_read_timeout
	-@rm -f test_timeout_all
	-@rm -f test_server_closeall
	-@rm -f test_taskgroup
	-@rm -f test_buffered
	-@rm -f test_datagram_echo
	-@rm -f test_primitives
	-@rm -f test_file
	-@rm -f test_executor
	-@rm -f test_path
	-@rm -f test_handler

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
FIBER = $(EXT)/fiber/*.c3
IO = $(EXT)/io/*.c3
AIO = $(EXT)/aio/*.c3

LIBS = $(AIO) $(FIBER) $(MEM) $(LIBC) $(IO)

SAN = --sanitize=address
SAN = --target windows-x64
SAN = 

test1: test1.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_pipe: test_pipe.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_pipe_stream: test_pipe_stream.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_echo_server: test_echo_server.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_tcp_echo: test_tcp_echo.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_shutdown: test_shutdown.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_read_timeout: test_read_timeout.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_timeout_all: test_timeout_all.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_server_closeall: test_server_closeall.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_taskgroup: test_taskgroup.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_buffered: test_buffered.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_datagram_echo: test_datagram_echo.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_primitives: test_primitives.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_file: test_file.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_executor: test_executor.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_path: test_path.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_handler: test_handler.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	


