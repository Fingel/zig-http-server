const std = @import("std");
const net = std.net;
const fs = std.fs;
const mem = std.mem;
const expect = std.testing.expect;

pub const ServeFileError = error{
    HeaderMalformed,
    MethodNotSupported,
    ProtoNotSupported,
    UnknownMimeType,
};

const mimeTypes = .{
    .{ ".html", "text/html" },
    .{ ".css", "text/css" },
    .{ ".png", "image/png" },
    .{ ".jpg", "image/jpeg" },
    .{ ".gif", "image/gif" },
};

pub fn main() !void {
    std.debug.print("Starting server\n", .{});
    const self_addr = try net.Address.resolveIp("0.0.0.0", 4206);
    var listener = try self_addr.listen(.{ .reuse_address = true });
    std.debug.print("Listening on {}\n", .{self_addr});

    while (listener.accept()) |conn| {
        std.debug.print("Accepted connection from: {}\n", .{conn.address});
        var recv_buf: [4096]u8 = undefined;
        var recv_total: usize = 0;
        while (conn.stream.read(recv_buf[recv_total..])) |recv_len| {
            if (recv_len == 0) break;
            recv_total += recv_len;
            if (mem.containsAtLeast(u8, recv_buf[0..recv_total], 1, "\r\n\r\n")) {
                break;
            }
        } else |read_err| {
            return read_err;
        }
        const recv_data = recv_buf[0..recv_total];
        const header = parseHeader(recv_data) catch |err| {
            if (err == ServeFileError.HeaderMalformed) {
                // Browsers (or firefox?) attempt to optimize for speed
                // by opening a connection to the server once a user highlights
                // a link, but doesn't start sending the request until it's
                // clicked. The request eventually times out so we just
                // go agane.
                std.debug.print("Got connection but no header!\n", .{});
                continue;
            } else {
                return err;
            }
        };
        const path = try parsePath(header.requestLine);
        const mime = mimeForPath(path);
        const buf = openLocalFile(path) catch |err| {
            if (err == error.FileNotFound) {
                _ = try conn.stream.writer().write(http404());
                continue;
            } else {
                return err;
            }
        };
        std.debug.print("SENDING----\n", .{});
        const httpHead =
            "HTTP/1.1 200 OK \r\n" ++
            "Connection: close\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {}\r\n" ++
            "\r\n";
        _ = try conn.stream.writer().print(httpHead, .{ mime, buf.len });
        _ = try conn.stream.writer().write(buf);
    } else |err| {
        std.debug.print("error in accept: {}\n", .{err});
    }
}

pub fn mimeForPath(path: []const u8) []const u8 {
    const extension = std.fs.path.extension(path);
    inline for (mimeTypes) |kv| {
        if (mem.eql(u8, extension, kv[0])) {
            return kv[1];
        }
    }
    return "application/octet-stream";
}

pub fn http404() []const u8 {
    return "HTTP/1.1 404 NOT FOUND \r\n" ++
        "Connection: close\r\n" ++
        "Content-Type: text/html; charset=utf8\r\n" ++
        "Content-Length: 9\r\n" ++
        "\r\n" ++
        "NOT FOUND";
}
pub fn openLocalFile(path: []const u8) ![]u8 {
    const localPath = path[1..];
    const file = fs.cwd().openFile(localPath, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("File not found: {s}\n", .{localPath});
            return error.FileNotFound;
        },
        else => return err,
    };
    defer file.close();
    std.debug.print("file: {}\n", .{file});
    const memory = std.heap.page_allocator;
    const maxSize = std.math.maxInt(usize);
    return try file.readToEndAlloc(memory, maxSize);
}

pub fn parsePath(requestLine: []const u8) ![]const u8 {
    var requestLineIter = mem.tokenizeScalar(u8, requestLine, ' ');
    const method = requestLineIter.next().?;
    if (!mem.eql(u8, method, "GET")) return ServeFileError.MethodNotSupported;
    const path = requestLineIter.next().?;
    if (path.len <= 0) return error.NoPath;
    const proto = requestLineIter.next().?;
    if (!mem.eql(u8, proto, "HTTP/1.1")) return ServeFileError.ProtoNotSupported;
    if (mem.eql(u8, path, "/")) {
        return "/index.html";
    }
    return path;
}

const HeaderNames = enum {
    Host,
    @"User-Agent",
};

const HTTPHeader = struct {
    requestLine: []const u8,
    host: []const u8,
    userAgent: []const u8,

    pub fn print(self: HTTPHeader) void {
        std.debug.print("{s} - {s}\n", .{
            self.requestLine,
            self.host,
        });
    }
};

pub fn parseHeader(header: []const u8) !HTTPHeader {
    var headerStruct = HTTPHeader{
        .requestLine = undefined,
        .host = undefined,
        .userAgent = undefined,
    };
    var headerIter = mem.tokenizeSequence(u8, header, "\r\n");
    headerStruct.requestLine = headerIter.next() orelse return ServeFileError.HeaderMalformed;
    while (headerIter.next()) |line| {
        const nameSlice = mem.sliceTo(line, ':');
        if (nameSlice.len == line.len) return ServeFileError.HeaderMalformed;
        const headerName = std.meta.stringToEnum(HeaderNames, nameSlice) orelse continue;
        const headerValue = mem.trimLeft(u8, line[nameSlice.len + 1 ..], " ");
        switch (headerName) {
            .Host => headerStruct.host = headerValue,
            .@"User-Agent" => headerStruct.userAgent = headerValue,
        }
    }
    return headerStruct;
}
