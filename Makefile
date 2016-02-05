all: build upload

clean:
	rm -rf _build

build: clean
	run-blogdown build

serve: build
	run-blogdown serve

upload:
	@echo "upload not working yet :-("
