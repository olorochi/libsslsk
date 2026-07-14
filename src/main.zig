const std = @import("std");
const Allocator = std.mem.Allocator;
const HostName = std.Io.net.HostName;
const meta = std.meta;
const mem = std.mem;
const print = std.debug.print;
const Reader = std.Io.Reader;
const Type = std.builtin.Type;
const Writer = std.Io.Writer;

pub const messages = @import("messages.zig");
const Header = messages.Header;
pub const Response = messages.Response;
pub const client = messages.client;
pub const server = messages.server;

fn allocate(T: type) T {
    return undefined;
}

fn static(comptime v: anytype) *@TypeOf(v) {
    const Static = struct {
        var mem = v;
    };
    return &Static.mem;
}

fn TagPayload(U: type, tag: meta.Tag(U)) type {
    return @FieldType(U, @tagName(tag));
}

pub fn write(writer: *Writer, message: anytype) !void {
    const T = @TypeOf(message);
    const fields = @typeInfo(T).@"struct".fields;

    var len: u32 = @sizeOf(u32);
    inline for (fields) |field| {
        len += switch (@typeInfo(field.type)) {
            .pointer, .array => @intCast(@sizeOf(u32) + @field(message, field.name).len),
            else => @sizeOf(field.type),
        };
    }

    try writer.writeStruct(Header(T){ .len = len, .code = T.code }, .little);
    inline for (fields) |field| {
        const value = @field(message, field.name);
        switch (@typeInfo(field.type)) {
            .pointer => try writeString(writer, value),
            .array => try writeString(writer, &value),
            else => try writer.writeInt(field.type, value, .little),
        }
    }
}

fn writeString(writer: *Writer, s: []const u8) !void {
    try writer.writeInt(u32, @intCast(s.len), .little);
    try writer.writeAll(s);
}

const ReadProgress = struct { current: u32, end: u32 };

pub fn read(gpa: Allocator, reader: *Reader, ResponseT: type) !ResponseT {
    const header = try reader.takeStruct(Header(ResponseT), .little);
    const tag = std.enums.fromInt(meta.Tag(ResponseT), header.code) orelse return error.invalidCode;

    var progress = ReadProgress{ .current = @sizeOf(@TypeOf(header.len)), .end = header.len };
    const response = readUnion(ResponseT, gpa, reader, tag, &progress);
    if (progress.current != progress.end) {
        return error.invalidLength;
    }
    return response;
}

fn readT(gpa: Allocator, reader: *Reader, T: type, progress: *ReadProgress) !T {
    if (progress.current > progress.end) return error.invalidLength;

    var t: T = undefined;
    switch (@typeInfo(T)) {
        .@"union" => {
            const tag = try reader.takeEnum(meta.Tag(T), .little);
            progress.current += @sizeOf(meta.Tag(T));
            t = try readUnion(T, gpa, reader, tag, progress);
        },
        .@"struct" => {
            inline for (@typeInfo(T).@"struct".fields) |field|
                @field(t, field.name) = try readT(gpa, reader, field.type, progress);
        },
        .pointer => {
            const size = try reader.takeInt(u32, .little);
            progress.current += @sizeOf(u32);
            const Child = meta.Child(T);

            // TODO: Response deallocator.
            const slice = try gpa.alloc(Child, size);
            for (0..size) |i| slice[i] = try readT(gpa, reader, Child, progress);
            t = slice;
        },
        .@"enum" => {
            t = try reader.takeEnum(T, .little);
            progress.current += @sizeOf(T);
        },
        // Optionals can only ever be at the end of a message.
        .optional => t = if (progress.current == progress.end) null else try readT(gpa, reader, meta.Child(T), progress),
        .void => {},
        else => {
            t = try reader.takeInt(T, .little);
            progress.current += @sizeOf(T);
        },
    }

    return t;
}

fn readUnion(U: type, gpa: Allocator, reader: *Reader, tag: meta.Tag(U), progress: *ReadProgress) !U {
    switch (tag) {
        inline else => |code| {
            return @unionInit(U, @tagName(code), try readT(gpa, reader, TagPayload(U, code), progress));
        },
    }
}

pub fn main(init: std.process.Init) !void {
    const hostname = try HostName.init("server.slsknet.org");
    const stream = try HostName.connect(hostname, init.io, 2242, .{ .mode = .stream, .protocol = .tcp }); // TODO: timeout
    var r_back = stream.reader(init.io, static(allocate([4096]u8)));
    var w_back = stream.writer(init.io, static(allocate([1024]u8)));
    const reader = &r_back.interface;
    var writer = &w_back.interface;

    try write(writer, try client.Login.init(init.gpa, "username", "password"));
    try writer.flush();

    while (true) {
        const response = try read(init.gpa, reader, Response(server));
        switch (response) {
            .login => switch (response.login) {
                .true => print("Login sucessful!\n", .{}),
                .false => |r| {
                    print("Login rejected: '{s}'!\n", .{r.reason});
                    return;
                },
            },
            else => {
                const tag = meta.activeTag(response);
                print("WARNING: No handler for response {}: '{s}'.\n", .{ @intFromEnum(tag), @tagName(tag) });
            },
        }
    }
}
