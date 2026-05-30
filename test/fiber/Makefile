all:
	@echo make build
	@echo make clean

build:
	@make fiber_test
	@make fiber_mem_test
	@make thread_mem_test

clean:
	-@rm -f x y *.exe *.pdb
	-@rm -f fiber_test
	-@rm -f fiber_mem_test
	-@rm -f thread_mem_test

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
FIBER = $(EXT)/fiber/*.c3 
MEM = $(EXT)/mem/*.c3 $(EXT)/debug/*.c3
LIBS = $(FIBER) $(MEM) $(LIBC)

TARGET ?= linux
ifeq ($(TARGET),win)
	T = --target windows-x64
else
	T =
endif

fiber_test: fiber_test.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

fiber_mem_test: fiber_mem_test.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

thread_mem_test: thread_mem_test.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)
