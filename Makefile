PKG_PREFIX := github.com/VictoriaMetrics/VictoriaMetrics

BUILDINFO_TAG ?= $(shell echo $$(git describe --long --all | tr '/' '-')$$( \
	      git diff-index --quiet HEAD -- || echo '-dirty-'$$(git diff-index -u HEAD | openssl sha1 | cut -c 10-17)))

PKG_TAG ?= $(shell git tag -l --points-at HEAD)
ifeq ($(PKG_TAG),)
PKG_TAG := $(BUILDINFO_TAG)
endif

GO_BUILDINFO = -X '$(PKG_PREFIX)/lib/buildinfo.Version=$(APP_NAME)-$(shell date -u +'%Y%m%d-%H%M%S')-$(BUILDINFO_TAG)'

.PHONY: $(MAKECMDGOALS)

all: \
	vminsert \
	vmselect \
	vmstorage

all-pure: \
	vminsert-pure \
	vmselect-pure \
	vmstorage-pure

include app/*/Makefile
include deployment/*/Makefile

clean:
	rm -rf bin/*

publish: \
	publish-vminsert \
	publish-vmselect \
	publish-vmstorage

package: \
	package-vminsert \
	package-vmselect \
	package-vmstorage

release: \
	release-vmcluster

release-vmcluster: \
	release-vmcluster-amd64 \
	release-vmcluster-arm64

release-vmcluster-amd64:
	GOARCH=amd64 $(MAKE) release-vmcluster-generic

release-vmcluster-arm64:
	GOARCH=arm64 $(MAKE) release-vmcluster-generic

release-vmcluster-generic: \
	vminsert-$(GOARCH)-prod \
	vmselect-$(GOARCH)-prod \
	vmstorage-$(GOARCH)-prod
	cd bin && \
		tar --transform="flags=r;s|-$(GOARCH)||" -czf victoria-metrics-$(GOARCH)-$(PKG_TAG).tar.gz \
			vminsert-$(GOARCH)-prod \
			vmselect-$(GOARCH)-prod \
			vmstorage-$(GOARCH)-prod \
		&& sha256sum victoria-metrics-$(GOARCH)-$(PKG_TAG).tar.gz \
			vminsert-$(GOARCH)-prod \
			vmselect-$(GOARCH)-prod \
			vmstorage-$(GOARCH)-prod \
			| sed s/-$(GOARCH)-prod/-prod/ > victoria-metrics-$(GOARCH)-$(PKG_TAG)_checksums.txt

pprof-cpu:
	go tool pprof -trim_path=github.com/VictoriaMetrics/VictoriaMetrics@ $(PPROF_FILE)

fmt:
	GO111MODULE=on gofmt -l -w -s ./lib
	GO111MODULE=on gofmt -l -w -s ./app

vet:
	GO111MODULE=on go vet -mod=vendor ./lib/...
	GO111MODULE=on go vet -mod=vendor ./app/...

lint: install-golint
	golint lib/...
	golint app/...

install-golint:
	which golint || go install golang.org/x/lint/golint

errcheck: install-errcheck
	errcheck -exclude=errcheck_excludes.txt ./lib/...
	errcheck -exclude=errcheck_excludes.txt ./app/vminsert/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmselect/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmstorage/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmagent/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmalert/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmauth/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmbackup/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmrestore/...
	errcheck -exclude=errcheck_excludes.txt ./app/vmctl/...

install-errcheck:
	which errcheck || go install github.com/kisielk/errcheck

check-all: fmt vet lint errcheck golangci-lint

test:
	GO111MODULE=on go test -mod=vendor ./lib/... ./app/...

test-race:
	GO111MODULE=on go test -mod=vendor -race ./lib/... ./app/...

test-pure:
	GO111MODULE=on CGO_ENABLED=0 go test -mod=vendor ./lib/... ./app/...

test-full:
	GO111MODULE=on go test -mod=vendor -coverprofile=coverage.txt -covermode=atomic ./lib/... ./app/...

test-full-386:
	GO111MODULE=on GOARCH=386 go test -mod=vendor -coverprofile=coverage.txt -covermode=atomic ./lib/... ./app/...

benchmark:
	GO111MODULE=on go test -mod=vendor -bench=. ./lib/...
	GO111MODULE=on go test -mod=vendor -bench=. ./app/...

benchmark-pure:
	GO111MODULE=on CGO_ENABLED=0 go test -mod=vendor -bench=. ./lib/...
	GO111MODULE=on CGO_ENABLED=0 go test -mod=vendor -bench=. ./app/...

vendor-update:
	GO111MODULE=on go get -u -d ./lib/...
	GO111MODULE=on go get -u -d ./app/...
	GO111MODULE=on go mod tidy
	GO111MODULE=on go mod vendor

app-local:
	CGO_ENABLED=1 GO111MODULE=on go build $(RACE) -mod=vendor -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)$(RACE) $(PKG_PREFIX)/app/$(APP_NAME)

app-local-pure:
	CGO_ENABLED=0 GO111MODULE=on go build $(RACE) -mod=vendor -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)-pure$(RACE) $(PKG_PREFIX)/app/$(APP_NAME)

app-local-with-goarch:
	GO111MODULE=on go build $(RACE) -mod=vendor -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)-$(GOARCH)$(RACE) $(PKG_PREFIX)/app/$(APP_NAME)

app-local-windows-with-goarch:
	CGO_ENABLED=0 GO111MODULE=on go build $(RACE) -mod=vendor -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)-windows-$(GOARCH)$(RACE).exe $(PKG_PREFIX)/app/$(APP_NAME)

quicktemplate-gen: install-qtc
	qtc

install-qtc:
	which qtc || go install github.com/valyala/quicktemplate/qtc


golangci-lint: install-golangci-lint
	golangci-lint run --exclude '(SA4003|SA1019|SA5011):' -D errcheck -D structcheck --timeout 2m

install-golangci-lint:
	which golangci-lint || curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell go env GOPATH)/bin v1.29.0

docs-sync:
	cp app/vmagent/README.md docs/vmagent.md
	cp app/vmalert/README.md docs/vmalert.md
	cp app/vmauth/README.md docs/vmauth.md
	cp app/vmbackup/README.md docs/vmbackup.md
	cp app/vmrestore/README.md docs/vmrestore.md
	cp app/vmctl/README.md docs/vmctl.md
	cp app/vmgateway/README.md docs/vmgateway.md
	cp README.md docs/Cluster-VictoriaMetrics.md
