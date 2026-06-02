all:
	@echo "make build-all"
	@echo "make clean"
	@echo "make pull"
	@echo "make push"

build-win:
	make build-all TARGET=win

build-all:
	@cd ./test/regex && make build TARGET=$(TARGET)
	@cd ./test/net && make build TARGET=$(TARGET)
	@cd ./test/hash && make build TARGET=$(TARGET)
	@cd ./test/io && make build TARGET=$(TARGET)
	@cd ./test/fiber && make build TARGET=$(TARGET)
	@cd ./test/serializer && make build TARGET=$(TARGET)
	@cd ./test/aio && make build TARGET=$(TARGET)
	@cd ./test/wepoll && make build TARGET=$(TARGET)
	@cd ./test/mio && make build TARGET=$(TARGET)

clean:
	@rm -rf ./build/*
	@rm -rf ./ext/*/obj
	@cd ./test/regex && make clean
	@cd ./test/net && make clean
	@cd ./test/hash && make clean
	@cd ./test/io && make clean
	@cd ./test/fiber && make clean
	@cd ./test/serializer && make clean
	@cd ./test/aio && make clean
	@cd ./test/wepoll && make clean
	@cd ./test/mio && make clean

push:
	@make clean
	@make pull
	@git add .
	@git commit -m "update"
	@git push origin main

pull:
	@git pull origin main
