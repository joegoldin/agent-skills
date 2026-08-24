---
name: web-re
description: Use when reverse engineering a web or network protocol — protobuf or gRPC messages, a HAR capture, an undocumented HTTP or JSON API, a WebSocket stream, or a TLS-fingerprinted endpoint. Triggers on decoding protobuf wire format (protoscope, protoc --decode_raw), grpcurl or grpcui, curl-impersonate for bot-protected APIs, websocat, HTML scraping with pup or BeautifulSoup, or parsing HAR files. Builds on the reverse-engineering skill for the shared toolchain (mitmproxy, tshark, jq).
---

# Web Reverse Engineering

Web/protocol tools in the `re-shell` devShell. For the shared toolchain
(mitmproxy, tshark, nmap, avahi, jq, the output-directory conventions, and the
Python/Node environments), see the **reverse-engineering** skill.

## Protocol Buffers and gRPC

| Command | What it does |
|---------|--------------|
| `protoc --decode_raw < message.bin` | Decode a protobuf message with no `.proto` |
| `protoscope < message.bin` | Inspect raw protobuf wire format without definitions |
| `grpcurl -plaintext localhost:50051 list` | CLI gRPC client with reflection support |
| `grpcui -plaintext localhost:50051` | Web UI for a gRPC service |

## HTTP and TLS

| Command | What it does |
|---------|--------------|
| `curl_chrome142 https://example.com` | curl with a browser TLS fingerprint (bypasses bot detection) |
| `http GET https://api.example.com/endpoint` | HTTPie, a friendly HTTP client for API exploration |

## WebSocket

`websocat ws://localhost:8080/ws` is a CLI WebSocket client for bidirectional
communication; pipe stdin → WS and WS → stdout.

## HTML parsing

`cat page.html | pup 'div.content text{}'` is jq for HTML: CSS selectors on the
command line.

## Python libraries

| Import | Use |
|--------|-----|
| `google.protobuf` | Protobuf runtime for parsing and generating messages |
| `grpc` (grpcio) | gRPC Python client |
| `grpc_tools.protoc` | protoc plugin for Python gRPC codegen |
| `bs4` (beautifulsoup4) | HTML/XML parsing for scraping and response analysis |
| `haralyzer` | Parse and analyze HAR (HTTP Archive) files |

## Workflows

### Decode unknown protobuf messages

```sh
protoscope < message.bin        # raw wire format, no .proto
protoc --decode_raw < message.bin
```

### Decode protobuf with .proto definitions

```sh
protoc --python_out=tmp/ schema.proto
protoc --decode=MyMessage schema.proto < message.bin
```

### Explore gRPC services

```sh
grpcurl -plaintext localhost:50051 list
grpcurl -plaintext localhost:50051 describe my.Service
grpcurl -plaintext -d '{"field": "value"}' localhost:50051 my.Service/Method
grpcui -plaintext localhost:50051   # interactive web UI
```

### Analyze HAR files

```python
import json
from haralyzer import HarParser

with open("traffic.har") as f:
    har = HarParser(json.load(f))

for entry in har.pages[0].entries:
    print(f"{entry.request.method} {entry.request.url} -> {entry.response.status}")
```

### curl-impersonate for bot-protected APIs

```sh
curl_chrome142 -H "Accept: application/json" https://api.example.com/data
curl_firefox144 https://example.com
curl_chrome142 --proxy http://127.0.0.1:8080 https://api.example.com/data   # through mitmproxy
curl-impersonate https://example.com   # generic wrapper, auto-selects a profile
```

### WebSocket interception

```sh
websocat ws://localhost:8080/ws
echo '{"type":"subscribe","channel":"events"}' | websocat ws://localhost:8080/ws
# mitmproxy handles WebSocket natively; point the target at the proxy
```

### HTML scraping

```sh
curl -s https://example.com | pup 'a attr{href}'          # all links
curl -s https://example.com | pup 'div.main-content text{}'
```

## Notes

- mitmproxy exports HAR: `mitmdump --set hardump=tmp/traffic.har` or the mitmweb
  UI.
- curl-impersonate ships browser-versioned binaries (`curl_chrome142`,
  `curl_firefox144`, `curl_safari260`, ...); `ls $(dirname $(which curl-impersonate))`
  lists the profiles.
- `grpcui` opens a browser, so on headless hosts use `grpcurl` or forward the port.
- `blackboxprotobuf` is excluded from the environment: it hard-pins
  `protobuf==3.10.0`, incompatible with modern grpcio-tools. Use `protoscope`
  or `protoc --decode_raw` for schema-less decoding.
