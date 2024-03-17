const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

const http = @import("http.zig");

test "test get mimetype for path" {
    const res = http.mimeForPath("foo/index.html");
    try expect(mem.eql(u8, res, "text/html"));
}

test "test unknown file type" {
    const res = http.mimeForPath("favicon.ico");
    try expect(mem.eql(u8, res, "application/octet-stream"));
}

test "test parsePath" {
    const requestLine = "GET /foo.html HTTP/1.1";
    const res = try http.parsePath(requestLine);
    try expect(mem.eql(u8, res, "/foo.html"));
}

test "test bad method" {
    const requestLine = "POST /foo.html HTTP/1.1";
    _ = http.parsePath(requestLine) catch |err| {
        try expect(err == http.ServeFileError.MethodNotSupported);
        return;
    };
}

test "test garbo string" {
    const requestLine = "Foobar";
    _ = http.parsePath(requestLine) catch |err| {
        try expect(err == http.ServeFileError.MethodNotSupported);
        return;
    };
}

test "test parseHeader" {
    const header =
        "GET / HTTP1.1\r\n" ++
        "Host: localhost:8000\r\n" ++
        "User-Agent: FooBrowser\r\n" ++
        "Accept-Lang: en\r\n";

    const res = try http.parseHeader(header);
    try expect(mem.eql(u8, res.host, "localhost:8000"));
    try expect(mem.eql(u8, res.userAgent, "FooBrowser"));
}
