all:
	@echo make build
	@echo make clean

build:
	@make slre
	@make slre_test
	@make regex_test
	@make regex_example

clean:
	-@rm -f slre
	-@rm -f slre_test
	-@rm -f regex_test
	-@rm -f regex_example

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
REGEX = $(EXT)/regex/*.c3 
MEM = $(EXT)/mem/*.c3 $(EXT)/debug/*.c3
LIBS = $(MEM) $(REGEX) $(LIBC)

slre: slre.c slre_test.c
	cc $^ -o $@

slre_test: slre_test.c3
	$(C3C) $^ $(LIBS) -o $@

regex_test: regex_test.c3
	$(C3C) $^ $(LIBS) -o $@

regex_example: regex_example.c3
	$(C3C) $^ $(LIBS) -o $@


