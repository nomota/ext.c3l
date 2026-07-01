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
ENCODING = $(EXT)/encoding/*.c3
AIOHTTP = $(EXT)/aiohttp/*.c3

LIBS = $(AIO) $(MIO) $(WEPOLL) $(FIBER) $(IO) $(MEM) $(LIBC) $(ENCODING) $(AIOHTTP)

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
	test_chunked \
	test_multipart \
	test_live_multipart \
	test_shutdown \
	test_timeout \
	test_slow_client \
	test_methods \
	test_live_methods \
	test_protocol_edge \
	test_disconnect \
	test_no_body \
	test_router_priority \
	test_static_security \
	test_static_concurrent \
	test_static_prefix \
	test_executor_pressure \
	test_protocol_weird \
	test_memory_ownership \
	test_executor_cancel \
	test_error_recovery \
	test_static_large \
	test_response_edge \
	test_stream_file \
	test_stream_all \
	test_req_body \
	test_runtime_misc \
	test_advanced_all \
	test_keepalive_pipeline \
	test_chunked_all \
	test_static_all \
	test_form_all \
	test_cors_all \
	test_errhandler \
	test_timeout_m \
	test_compress \
	test_cache_range \
	test_request_json \
	test_websocket \
	test_ws_server \
	test_ws_protocol \
	test_client \
	a

LIVE_TESTS = \
	test_keepalive \
	test_live_server \
	test_live_edge \
	test_live_multipart \
	test_live_concurrent \
	test_timeout \
	test_slow_client \
	test_live_methods \
	test_disconnect \
	test_no_body \
	test_static_security \
	test_static_concurrent \
	test_executor_pressure \
	test_executor_cancel \
	test_error_recovery \
	test_static_large \
	test_stream_all \
	test_req_body \
	test_runtime_misc \
	test_advanced_all \
	test_keepalive_pipeline \
	test_chunked_all \
	test_static_all \
	test_form_all \
	test_cors_all \
	test_errhandler \
	test_timeout_m \
	test_compress \
	test_cache_range \
	test_ws_server \
	test_ws_protocol \
	test_client
	

SAN =
# SAN = --sanitize=address

.PHONY: all build test clean

all:
	@echo make build
	@echo make clean
	@echo make clean-live
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

clean-live:
	-@rm -f x y *.exe *.pdb $(LIVE_TESTS)

%: %.c3
	$(C3C) $< $(LIBS) -o $@ $(SAN)
	
# eof