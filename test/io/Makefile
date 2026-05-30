all:
	@echo make build
	@echo make clean

build:
	@make cfile_example
	@make scan_dir

clean:
	-@rm -f *.exe *.pdb
	-@rm -f cfile_example
	-@rm -f x 
	-@rm -f scan_dir

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
IO = $(EXT)/io/*.c3 
MEM = $(EXT)/mem/*.c3 $(EXT)/debug/*.c3
LIBS = $(LIBC) $(IO) $(MEM)

TARGET ?= linux
ifeq ($(TARGET),win)
	T = --target windows-x64
else
	T =
endif

cfile_example: cfile_example.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)

scan_dir: scan_dir.c3
	$(C3C) $^ $(LIBS) -o $@ $(T)



