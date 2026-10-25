# syntax=docker/dockerfile:1-labs
# Use -labs for copy --exclude

### Build Vela
from docker.io/golang:1.27.3-bookworm as build
workdir /goatcounter
copy --exclude=goatcounter-data --exclude=Dockerfile . /goatcounter
env CGO_ENABLED=1
env GOTOOLCHAIN=auto
run apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*
run go build -trimpath -ldflags='-s -w -extldflags=-static' \
	-tags='osusergo,netgo,sqlite_omit_load_extension' \
	./cmd/goatcounter

### Build container
from docker.io/alpine:3.24.3
run apk add --no-cache ca-certificates
copy --from=build /goatcounter/goatcounter /bin/goatcounter
run addgroup goatcounter && adduser -D -G goatcounter goatcounter && mkdir -p /home/goatcounter/goatcounter-data && chown goatcounter:goatcounter /home/goatcounter/goatcounter-data

label org.opencontainers.image.title="Vela"
label org.opencontainers.image.description="Privacy-first web analytics, compatible with GoatCounter"

expose     80 443 8080
workdir    /home/goatcounter
user       goatcounter:goatcounter
volume     ["/home/goatcounter/goatcounter-data"]
entrypoint ["goatcounter"]
cmd        ["serve", "-automigrate"]
