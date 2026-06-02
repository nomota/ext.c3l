all:
	@echo make build
	@echo make clean

build:
	@make test_basic
	@make test_multi_udp
	@make test_tcp
	@make test_oneshot_udp
	@make test_tcp_hup
	@make test_invalid_api
	@make test_timeout
	@make test_stress_udp
	@make test_batch_udp
	@make test_pending_del_udp
	
clean:
	-@rm -f x y *.exe *.pdb
	-@rm -f test_basic
	-@rm -f test_multi_udp
	-@rm -f test_tcp
	-@rm -f test_oneshot_udp
	-@rm -f test_tcp_hup
	-@rm -f test_invalid_api
	-@rm -f test_timeout
	-@rm -f test_stress_udp
	-@rm -f test_batch_udp
	-@rm -f test_pending_del_udp

C3C = c3c compile
EXT = ../../ext
LIBC = $(EXT)/c/*.c3
MEM = $(EXT)/debug/*.c3 $(EXT)/mem/*.c3
WEPOLL = $(EXT)/wepoll/*.c3

LIBS = $(WEPOLL) $(MEM) $(LIBC)

SAN = --sanitize=address
SAN = --target windows-x64
# SAN = 

test_basic: test_basic.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_multi_udp: test_multi_udp.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_tcp: test_tcp.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_oneshot_udp: test_oneshot_udp.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)

test_tcp_hup: test_tcp_hup.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_invalid_api: test_invalid_api.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_timeout: test_timeout.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_stress_udp: test_stress_udp.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_batch_udp: test_batch_udp.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
test_pending_del_udp: test_pending_del_udp.c3
	$(C3C) $^ $(LIBS) -o $@ $(SAN)
	
