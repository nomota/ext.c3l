all:
	@echo make build
	@echo make clean

build:
	@make http_sample
	@make json_sample
	@make simdjson_sample

clean:
	-@rm -f http_sample
	-@rm -f json_sample
	-@rm -f simdjson_sample

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
SERIALIZER = $(EXT)/serializer/*.c3

LIBS = $(SERIALIZER) $(MEM) $(LIBC)
SAN = --sanitize=address
#SAN =

http_sample: http_sample.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

json_sample: json_sample.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

simdjson_sample: simdjson_sample.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

