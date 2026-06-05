# test/aiohttp/Makefile

C3C = c3c compile
EXT = ../../ext

LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
IO = $(EXT)/io/*.c3
FIBER = $(EXT)/fiber/*.c3
WEPOLL = $(EXT)/wepoll/*.c3
MIO = $(EXT)/mio/*.c3
AIO = $(EXT)/aio/*.c3
SERIALIZER = $(EXT)/serializer/*.c3
AIOHTTP = headers.c3 response.c3 request.c3 url.c3 params.c3 router.c3 context.c3 cookies.c3 form.c3 body.c3 middleware.c3 cors.c3 application.c3 server.c3 static.c3 chunked.c3

LIBS = $(AIO) $(MIO) $(WEPOLL) $(FIBER) $(IO) $(MEM) $(LIBC) $(SERIALIZER) $(AIOHTTP)

TESTS = \
	test_router \
	test_request \
	test_response \
	test_url \
	test_form_cookie \
	test_application \
	test_aiohttp \
	test_middleware \
	test_context \
	test_server \
	test_static \
	test_live_server \
	test_error_cases \
	test_cors \
	test_params \
	test_header \
	test_body \
	test_request_limits \
	test_memory \
	test_live_edge \
	test_middleware_edge \
	test_live_concurrent \
	test_http_extreme \
	test_keepalive \
	test_chunked

SAN =
# SAN = --sanitize=address

.PHONY: all build test clean

all:
	@echo make build
	@echo make clean
	@echo make test

build: $(TESTS)

test: build
	@for test in $(TESTS); do \
		echo "RUN  $$test"; \
		./$$test || exit 1; \
		echo "PASS $$test"; \
		echo; \
	done
	@echo "All tests passed."

clean:
	-@rm -f x y *.exe *.pdb $(TESTS)

%: %.c3
	$(C3C) $< $(LIBS) -o $@ $(SAN)
	
# eof