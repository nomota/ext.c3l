all:
	@echo make build
	@echo make clean

build:
	make sample1
	make sample2
	make sample3
	make sample4
	make sample5
	make sample6
	make sample7
	make sample8
	make sample9
	make sample10
	make sample11
	make sample12

clean:
	-@rm -f *.exe *.pdb
	-@rm -f sample1
	-@rm -f sample2
	-@rm -f sample3
	-@rm -f sample4
	-@rm -f sample5
	-@rm -f sample6
	-@rm -f sample7
	-@rm -f sample8
	-@rm -f sample9
	-@rm -f sample10
	-@rm -f sample11
	-@rm -f sample12

C3C = c3c compile

EXT = ../../ext
LIBC = $(EXT)/c/*.c3
FIBER = $(EXT)/fiber/*.c3 
ASYNCIO = $(EXT)/asyncio/*.c3
MEM = $(EXT)/mem/*.c3 $(EXT)/debug/*.c3

TARGET ?= linux
ifeq ($(TARGET),win)
	T = --target windows-x64
else
	T =
endif

SAN = --sanitize=address
SAN = 
LIBS = $(LIBC) $(MEM) $(FIBER) $(ASYNCIO)

sample1: sample1.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample2: sample2.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample3: sample3.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample4: sample4.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample5: sample5.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample6: sample6.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample7: sample7.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample8: sample8.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

sample9: sample9.c3
	$(C3C) $^ $(LIBS) -o $@ $(T) $(SAN)

sample10: sample10.c3
	$(C3C) $^ $(LIBS) -o $@ $(T) $(SAN)

sample11: sample11.c3
	$(C3C) $^ $(LIBS) -o $@ $(T) $(SAN)

sample12: sample12.c3
	$(C3C) $^ $(LIBS) -o $@ $(T) $(SAN)
