const std = @import("std");
const Allocator = std.mem.Allocator;
const HostName = std.Io.net.HostName;
const meta = std.meta;
const mem = std.mem;
const Reader = std.Io.Reader;
const Type = std.builtin.Type;
const Writer = std.Io.Writer;
pub const messages = @import("messages.zig");
const Header = messages.Header;
const Response = messages.Response;

fn allocate(T: type) T {
    return undefined;
}

fn static(comptime v: anytype) *@TypeOf(v) {
    const Static = struct { var mem = v; };
    return &Static.mem;
}

fn TagPayload(U: type, tag: meta.Tag(U)) type {
    return @FieldType(U, @tagName(tag));
}

fn write(writer: *Writer, message: anytype) !void {
    const T = @TypeOf(message);
    const fields = @typeInfo(T).@"struct".fields;

    var len: u32 = @sizeOf(u32);
    inline for (fields) |field| {
        len += switch(@typeInfo(field.type)) {
            .pointer,
            .array => @intCast(@sizeOf(u32) + @field(message, field.name).len),
            else => @sizeOf(field.type)
        };
    }

    try writer.writeStruct(Header(T){ .length = len, .code = T.code}, .little);
    inline for (fields) |field| {
        const value = @field(message, field.name);
        switch (@typeInfo(field.type)) {
            .pointer => try writeString(writer, value),
            .array => try writeString(writer, &value),
            else => try writer.writeInt(field.type, value, .little)
        }
    }
}

fn writeString(writer: *Writer, s: []const u8) !void {
    try writer.writeInt(u32, @intCast(s.len), .little);
    try writer.writeAll(s);
}

const invalidHeader = error.InvalidHeader;
fn read(gpa: Allocator, reader: *Reader, comptime U: type) !U {
    const header = try reader.takeStruct(Header(U), .little);
    const tag = std.enums.fromInt(meta.Tag(U), header.code) orelse return invalidHeader;
    return readUnion(U, gpa, reader, tag);
}

fn readT(T: type, gpa: Allocator, reader: *Reader) !T {
    return sw: switch (@typeInfo(T)) {
        .@"union" => {
            const tag = try reader.takeEnum(meta.Tag(T), .little);
            break :sw try readUnion(T, gpa, reader, tag);
        },
        .@"struct" => {
            var t: T = undefined;
            inline for (@typeInfo(T).@"struct".fields) |field| {
                @field(t, field.name) = try readT(field.type, gpa, reader);
            }

            break :sw t;
        },
        .@"pointer" => {
            const size = try reader.takeInt(u32, .little);
            // TODO: This leaks memory. I unfortunately don't think I can
            // remove this allocation since some responses could be larger than
            // the read buffer. Regardless, I'm putting off writing a Response
            // deallocator for now.
            const slice = try gpa.alloc(u8, size);
            @memcpy(slice, try reader.take(size));
            break :sw slice;
        },
        .@"enum" => try reader.takeEnum(T, .little),
        // TODO: This requires passing around the header and either summing
        // read bytes or finding out where the zig io interface guarantees
        // pointer validity. I should be checking message lenghts anyways.
        .optional => null,
        .void => {},
        else => try reader.takeInt(T, .little),
    };
}

fn readUnion(U: type, gpa: Allocator, reader: *Reader, tag: meta.Tag(U)) !U {
    switch (tag) {
        inline else => |code| {
            return @unionInit(U, @tagName(code), try readT(TagPayload(U, code), gpa, reader));
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const hostname = try HostName.init("server.slsknet.org");
    const stream = try HostName.connect(hostname, init.io, 2242, .{ .mode = .stream, .protocol = .tcp }); // TODO: timeout
    var reader = stream.reader(init.io, static(allocate([4096]u8)));
    var writer = stream.writer(init.io, static(allocate([1024]u8)));

    try write(&writer.interface, try messages.client.Login.init(init.gpa, "username", "pass"));
    try writer.interface.flush();

    const response = try read(init.gpa, &reader.interface, Response(messages.server));
    std.debug.print("{s}\n", .{ response.login.false.reason });
}
