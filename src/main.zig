const std = @import("std");
const meta = std.meta;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;
const Md5 = std.crypto.hash.Md5;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const Type = std.builtin.Type;
const HostName = std.Io.net.HostName;

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

// I really wish zig had a @ReturnType builtin.
fn SelectT(values: anytype, comptime field: []const u8) type {
    return [values.len]@FieldType(meta.Child(@TypeOf(values)), field);
}

fn select(values: anytype, comptime field: []const u8) SelectT(values, field) {
    var fields: SelectT(values, field) = undefined;
    for (values, &fields) |v, *f| {
        f.* = @field(v, field);
    }

    return fields;
}

const Header = extern struct {
    length: u32,
    code: u32,
};

const Bool = enum(u8) {
    false = 0,
    true = 1
};

const messages = struct {
    pub const Login = struct {
        pub const code = 1;

        username: []const u8,
        password: []const u8,
        major: u32 = 177,
        hash: [Md5.digest_length * 2]u8,
        minor: u32 = 1,

        const Response = union(Bool) {
            false: struct {
                reason: []u8,
                details: ?[]u8
            },
            true: struct {
                greet: []u8,
                ip: u32,
                // If we can rely on pointers to the read buffer, a slice here
                // would give total control of memory allocations to the
                // caller. It could also be an array, but I haven't implemented
                // a way to read them.
                hash: []u8,
                supporter: Bool
            }
        };

        pub fn init(gpa: Allocator, username: []const u8, password: []const u8) !Login {
            const concat = try std.mem.concat(gpa, u8, &.{ username, password });
            defer gpa.free(concat);
            var login: Login = .{
                .username = concat[0..username.len],
                .password = concat[username.len..],
                .hash = undefined
            };

            const hash = login.hash[0..16];
            Md5.hash(concat, hash, .{});
            @memmove(&login.hash, &std.fmt.bytesToHex(hash, .lower));

            return login;
        }
    };
};

/// A tagged union for every implemented soulseek protocol response.
const Response = blk: {
    const decls = @typeInfo(messages).@"struct".decls;

    const attrs: [decls.len]Type.UnionField.Attributes = @splat(.{ .@"align" = null });
    var types: [decls.len]type = undefined;
    var values: [decls.len]u32 = undefined;
    var names: [decls.len][]const u8 = undefined;

    for (decls, &names, &types, &values) |decl, *name, *T, *value| {
        const Request = @field(messages, decl.name);
        T.* = Request.Response;
        value.* = Request.code;
        name.* = .{ ascii.toLower(decl.name[0]) } ++ decl.name[1..];
    }

    const Tag = @Enum(u32, .exhaustive, &names, &values);
    break :blk @Union(.@"auto", Tag, &names, &types, &attrs);
};

const Code = meta.Tag(Response);

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

    try writer.writeStruct(Header{ .length = len, .code = T.code}, .little);
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
fn read(gpa: Allocator, reader: *Reader) !Response {
    const header = try reader.takeStruct(Header, .little);
    const tag = std.enums.fromInt(Code, header.code) orelse return invalidHeader;
    return readUnion(Response, gpa, reader, tag);
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
            // This leaks memory. I unfortunately don't think I can remove this
            // allocation since some responses could be larger than the read
            // buffer. Regardless, I'm putting off writing a Response
            // deallocator for now.
            const slice = try gpa.alloc(u8, size);
            @memcpy(slice, try reader.take(size));
            break :sw slice;
        },
        .@"enum" => try reader.takeEnum(T, .little),
        // TODO: This requires passing around the header and either summing
        // read bytes or finding out where the zig io interface guarantees
        // pointer validity.
        .optional => null,
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

    try write(&writer.interface, try messages.Login.init(init.gpa, "username", "pass"));
    try writer.interface.flush();

    const response = try read(init.gpa, &reader.interface);
    std.debug.print("{s}\n", .{ response.login.false.reason });
}
