all:
	@echo make build
	@echo make clean

build:
	make tcpserver
	make tcpclient
	make udpserver
	make udpclient

clean:
	-@rm -f *.exe *.pdb
	-@rm -f tcpserver
	-@rm -f tcpclient
	-@rm -f udpserver
	-@rm -f udpclient

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
NET = $(EXT)/net/*.c3 
MEM = $(EXT)/mem/*.c3 $(EXT)/debug/*.c3
LIBS = $(LIBC) $(NET) $(MEM)

TARGET ?= linux
ifeq ($(TARGET),win)
	T = --target windows-x64
else
	T =
endif

tcpclient: tcpclient.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

udpclient: udpclient.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

tcpserver: tcpserver.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

udpserver: udpserver.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

