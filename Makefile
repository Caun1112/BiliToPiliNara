.PHONY: all package test verify clean

all: package

package:
	./scripts/build.sh package

test:
	./scripts/build.sh test

verify:
	./scripts/build.sh verify

clean:
	./scripts/build.sh clean
