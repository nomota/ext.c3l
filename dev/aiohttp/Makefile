all:
	@echo make build
	@echo make clean

build:
	@make client1
	@make server1

clean:
	-@rm -f server1
	-@rm -f client1

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
IO = $(EXT)/io/*.c3
FIBER = $(EXT)/fiber/*.c3
ASYNCIO = $(EXT)/asyncio/*.c3
AIOFILES = $(EXT)/aiofiles/*.c3
SERIALIZER = $(EXT)/serializer/*.c3
AIOHTTP = util.url.c3 util.chunk.c3 util.ws.c3 client.dns.c3 client.pool.c3 client.req.c3 web.router.c3 web.middleware.c3 web.static.c3 aiohttp.types.c3 aiohttp.client.c3 aiohttp.web.c3

LIBS = $(AIOFILES) $(ASYNCIO) $(FIBER) $(IO) $(MEM) $(LIBC) $(SERIALIZER) $(AIOHTTP)

SAN = --sanitize=address
SAN =

client1: client1.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

server1: server1.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

