all:
	@echo make build
	@echo make clean

build:
	make murmurtest
	make cityexample

clean:
	-@rm -f murmurtest
	-@rm -f cityexample

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
HASH = $(EXT)/hash/*.c3 

murmurtest: murmurtest.c3
	$(C3C) $^ $(LIBC) $(HASH) -o $@

cityexample: cityexample.c3
	$(C3C) $^ $(LIBC) $(HASH) -o $@
