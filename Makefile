all: build upload

clean:
	rm -rf _build

build:
	run-rstblog build

serve:
	run-rstblog serve

upload:
	csync -a _build/ sftp://vzdusne.cz:/g4
	@echo "Done..."
