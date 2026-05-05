all:
	@echo make build
	@echo make clean

build:
	#@make client1
	@make server1
	@make server2
	@make test_router
	@make test_request
	@make test_response
	@make test_url
	@make test_form_cookie

clean:
	-@rm -f x y
	-@rm -f server1
	-@rm -f server2
	-@rm -f test_router
	-@rm -f test_request
	-@rm -f test_response
	-@rm -f tesy_url
	-@rm -f test_form_cookie
	# -@rm -f client1
	

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
IO = $(EXT)/io/*.c3
FIBER = $(EXT)/fiber/*.c3
ASYNCIO = $(EXT)/asyncio/*.c3
AIOFILES = $(EXT)/aiofiles/*.c3
SERIALIZER = $(EXT)/serializer/*.c3
HTTP = headers.c3 response.c3 request.c3 url.c3 params.c3 router.c3 context.c3 cookies.c3 form.c3 body.c3 middleware.c3 cors.c3 application.c3 server.c3 static.c3

LIBS = $(AIOFILES) $(ASYNCIO) $(FIBER) $(IO) $(MEM) $(LIBC) $(SERIALIZER) $(HTTP)

SAN = --sanitize=address
SAN =

#client1: client1.c3
#	$(C3C) $^ $(LIBS) -o $@ $(SAN)

server1: server1.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

server2: server2.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_router: test_router.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_request: test_request.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_response: test_response.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_url: test_url.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_form_cookie: test_form_cookie.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_application: test_application.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
