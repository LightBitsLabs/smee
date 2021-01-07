# Only use the recipes defined in these makefiles
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:
# Delete target files if there's an error
# This avoids a failure to then skip building on next run if the output is created by shell redirection for example
# Not really necessary for now, but just good to have already if it becomes necessary later.
.DELETE_ON_ERROR:
# Treat the whole recipe as a one shell script/invocation instead of one-per-line 
.ONESHELL:
# Use bash instead of plain sh 
SHELL := bash
.SHELLFLAGS := -o pipefail -euc

binary := boots
.PHONY: all ${binary} crosscompile dc gen run test
all: ${binary}

crosscompile: $(shell git ls-files | grep -v -e vendor -e '_test.go' | grep '.go$$' )
	CGO_ENABLED=0 GOOS=linux GOARCH=386 go build -v -o ./boots-linux-x86_64 -ldflags="-X main.GitRev=$(shell git rev-parse --short HEAD)"
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -o ./boots-linux-amd64 -ldflags="-X main.GitRev=$(shell git rev-parse --short HEAD)"
	CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 go build -v -o ./boots-linux-aarch64 -ldflags="-X main.GitRev=$(shell git rev-parse --short HEAD)"
	CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -v -o ./boots-linux-armv7l -ldflags="-X main.GitRev=$(shell git rev-parse --short HEAD)"
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -v -o ./boots-linux-arm64 -ldflags="-X main.GitRev=$(shell git rev-parse --short HEAD)"

# this is quick and its really only for rebuilding when dev'ing, I wish go would
# output deps in make syntax like gcc does... oh well this is good enough
${binary}: $(shell git ls-files | grep -v -e vendor -e '_test.go' | grep '.go$$' )
	CGO_ENABLED=0 go build -v -ldflags="-X main.GitRev=$(shell git rev-parse --short HEAD)"

ifeq ($(origin GOBIN), undefined)
GOBIN := ${PWD}/bin
export GOBIN
endif

ipxe/bindata.go: ipxe/bin/ipxe.efi ipxe/bin/snp-hua.efi ipxe/bin/snp-nolacp.efi ipxe/bin/undionly.kpxe
	go-bindata -pkg ipxe -o $@ $^
	gofmt -w $@

ipxev := 18dc73d27edb55ebe9cb13c58d59af3da3bd374b
ipxeh := 17b6bbad8f0a94b15cdb5470bb60c8c7868759efd89f0ea8111c94eefaaa4c0c665a5b8d9547defeb8caf432a0d9d12e25aa81709b4e5a6055cb416c140b4de7
ipxeconfigs := $(wildcard ipxe/ipxe/*.h)

ipxe/bin/ipxe.efi: ipxe/ipxe/build/ipxe-x86_64-efi/ipxe.efi
ipxe/bin/snp-nolacp.efi: ipxe/ipxe/build/ipxe-arm64-efi/snp.efi
ipxe/bin/undionly.kpxe: ipxe/ipxe/build/ipxe-x86_64-kpxe/undionly.kpxe
ipxe/bin/ipxe.efi ipxe/bin/snp-nolacp.efi ipxe/bin/undionly.kpxe:
	cp $^ $@

ipxe/ipxe/build/${ipxev}.tar.gz: ipxev.mk
	mkdir -p $(@D)
	curl -fL https://github.com/ipxe/ipxe/archive/${ipxev}.tar.gz > $@
	echo "${ipxeh}  $@" | sha512sum -c

# given  t=$(patsubst ipxe/ipxe/build/%,%,$@)
# and   $@=ipxe/ipxe/build/*/*
# t       =                */*
ipxe/ipxe/build/ipxe-arm64-efi/snp.efi ipxe/ipxe/build/ipxe-x86_64-efi/ipxe.efi ipxe/ipxe/build/ipxe-x86_64-kpxe/undionly.kpxe: ipxe/ipxe/build/${ipxev}.tar.gz ipxe/ipxe/build.sh ${ipxeconfigs}
	+t=$(patsubst ipxe/ipxe/build/%,%,$@)
	rm -rf $(@D)
	mkdir -p $(@D)
	tar -xzf $< -C $(@D)
	cp ${ipxeconfigs} $(@D)
	cd $(@D) && ../../build.sh $$t ${ipxev}

ifeq ($(CI),drone)
run: ${binary}
	${binary}
test:
	go test -race -coverprofile=coverage.txt -covermode=atomic ${TEST_ARGS} ./...
else
run: ${binary}
	docker-compose up -d --build cacher
	docker-compose up --build boots
test:
	docker-compose up -d --build cacher
endif
