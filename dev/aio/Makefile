all:
	@echo make build
	@echo make clean

build:
	@make test1
	@make test_pipe
	@make test_pipe_stream

clean:
	-@rm -f x y *.exe *.pdb
	-@rm -f test1
	-@rm -f test_pipe
	-@rm -f test_pipe_stream
	

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
FIBER = $(EXT)/fiber/*.c3
AIO = waiter.c3 task.c3 loop.c3 timer.c3 poller.c3 poller.epoll.c3 stream.c3 socket.posix.c3

LIBS = $(AIO) $(FIBER) $(MEM) $(LIBC)

SAN = --sanitize=address
SAN =

test1: test1.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_pipe: test_pipe.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_pipe_stream: test_pipe_stream.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

