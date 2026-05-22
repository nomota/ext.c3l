all:
	@echo "make build-all"
	@echo "make clean"
	@echo "make pull"
	@echo "make push"

build-win:
	make build-all TARGET=win

build-all:
	@cd ./examples/regex && make build TARGET=$(TARGET)
	@cd ./examples/net && make build TARGET=$(TARGET)
	@cd ./examples/hash && make build TARGET=$(TARGET)
	@cd ./examples/io && make build TARGET=$(TARGET)
	@cd ./examples/fiber && make build TARGET=$(TARGET)
	@cd ./examples/serializer && make build TARGET=$(TARGET)
	@cd ./examples/aio && make build TARGET=$(TARGET)

clean:
	@rm -rf ./build/*
	@rm -rf ./ext/*/obj
	@cd ./examples/regex && make clean
	@cd ./examples/net && make clean
	@cd ./examples/hash && make clean
	@cd ./examples/io && make clean
	@cd ./examples/fiber && make clean
	@cd ./examples/serializer && make clean
	@cd ./examples/aio && make clean

push:
	@make clean
	@make pull
	@git add .
	@git commit -m "update"
	@git push origin main

pull:
	@git pull origin main
