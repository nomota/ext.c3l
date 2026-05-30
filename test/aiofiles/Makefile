all:
	@echo make build
	@echo make clean

build:
	@make aio_sample
	@make aio_tempfile

clean:
	-@rm -f x y *.pdb *.exe
	-@rm -f aio_sample
	-@rm -f aio_tempfile

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
IO = $(EXT)/io/*.c3
FIBER = $(EXT)/fiber/*.c3
ASYNCIO = $(EXT)/asyncio/*.c3
AIOFILES = $(EXT)/aiofiles/*.c3

LIBS = $(AIOFILES) $(ASYNCIO) $(FIBER) $(IO) $(MEM) $(LIBC)
SAN = --sanitize=address
SAN =

aio_sample: aio_sample.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

aio_tempfile: aio_tempfile.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

