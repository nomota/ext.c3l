all:
	@echo make build
	@echo make clean

build:
	@make test_basic
	
clean:
	-@rm -f x y *.exe *.pdb
	-@rm -f test_basic

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
WEPOLL = wepoll.c3

LIBS = $(WEPOLL) $(MEM) $(LIBC)

SAN = --sanitize=address
SAN = --target windows-x64
# SAN = 

test_basic: test_basic.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

