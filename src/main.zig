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
pub const Response = messages.Response;

pub const std_options = std.Options{
    .fmt_max_depth = 5,
};

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
    try writeT(writer, tSize(message));
    try writeT(writer, @TypeOf(message).code);
    try writeT(writer, message);
}

fn tSize(t: anytype) u32 {
    const info = @typeInfo(@TypeOf(t));
    switch (info) {
        .@"struct" => {
            var len: u32 = 0;
            inline for (info.@"struct".fields) |field| {
                len += tSize(@field(t, field.name));
            }

            return len;
        },
        .pointer, .array => {
            var len: u32 = @sizeOf(u32);
            for (t) |e| len += tSize(e);
            return len;
        },
        .@"union" => switch (t) {
            inline else => |payload, tag| return tSize(tag) + tSize(payload),
        },
        .optional => return if (t) tSize(t.?) else 0,
        else => return @sizeOf(@TypeOf(t)),
    }
}

fn writeT(writer: *Writer, t: anytype) !void {
    const T = @TypeOf(t);
    const info = @typeInfo(T);
    switch (info) {
        .@"union" => switch (t) {
            inline else => |payload, tag| {
                writeT(tag);
                writeT(writer, payload);
            },
        },
        .@"struct" => inline for (info.@"struct".fields) |field| {
            try writeT(writer, @field(t, field.name));
        },
        .pointer => try writeSlice(writer, t),
        .array => try writeSlice(writer, &t),
        .optional => if (t) writeT(t.?),
        .void => {},
        else => try writer.writeInt(T, t, .little),
    }
}

fn writeSlice(writer: *Writer, s: anytype) !void {
    try writeT(writer, @as(u32, @intCast(s.len)));
    for (s) |e| try writeT(writer, e);
}

const ReadProgress = struct { current: u32, end: u32 };

pub fn read(gpa: Allocator, reader: *Reader, ResponseT: type) !ResponseT {
    const len = try reader.takeInt(u32, .little);
    var progress = ReadProgress{ .current = 0, .end = len };

    const response = readT(gpa, reader, ResponseT, &progress);
    if (progress.current != progress.end) {
        freeResponse(gpa, response);
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
            switch (tag) {
                inline else => |code| {
                    const payload = try readT(gpa, reader, TagPayload(T, code), progress);
                    t = @unionInit(T, @tagName(code), payload);
                },
            }
        },
        .@"struct" => {
            inline for (@typeInfo(T).@"struct".fields) |field|
                @field(t, field.name) = try readT(gpa, reader, field.type, progress);
        },
        .array => {
            const size = try reader.takeInt(u32, .little);
            progress.current += @sizeOf(u32);
            if (size != t.len) return error.invalidField;

            for (0..t.len) |i| t[i] = try readT(gpa, reader, meta.Child(T), progress);
        },
        .pointer => {
            const size = try reader.takeInt(u32, .little);
            progress.current += @sizeOf(u32);

            const Child = meta.Child(T);
            const slice = try gpa.alloc(Child, size);
            errdefer gpa.free(slice);
            for (0..size) |i| slice[i] = try readT(gpa, reader, Child, progress);
            t = slice;
        },
        .@"enum" => {
            t = try reader.takeEnum(T, .little);
            progress.current += @sizeOf(T);
        },
        // Optionals can only ever be at the end of a message.
        .optional => {
            if (progress.current == progress.end) t = null else {
                t = try readT(gpa, reader, @TypeOf(t.?), progress);
            }
        },
        .void => {},
        else => {
            t = try reader.takeInt(T, .little);
            progress.current += @sizeOf(T);
        },
    }

    return t;
}

pub fn freeResponse(gpa: Allocator, response: anytype) void {
    const T = @TypeOf(response);
    switch (@typeInfo(T)) {
        .pointer => {
            for (response) |e| freeResponse(gpa, e); // The child could have heap allocated memory as well.
            gpa.free(response);
        },
        .optional => if (response) |v| freeResponse(gpa, v),
        .@"struct" => inline for (@typeInfo(T).@"struct".fields) |field|
            freeResponse(gpa, @field(response, field.name)),
        .@"union" => switch (response) {
            inline else => |payload| freeResponse(gpa, payload),
        },
        else => {},
    }
}

pub fn main(init: std.process.Init) !u8 {
    const hostname = try HostName.init("server.slsknet.org");
    const stream = try HostName.connect(hostname, init.io, 2242, .{ .mode = .stream, .protocol = .tcp }); // TODO: timeout
    var r_back = stream.reader(init.io, static(allocate([4096]u8)));
    var w_back = stream.writer(init.io, static(allocate([1024]u8)));
    const reader = &r_back.interface;
    const writer = &w_back.interface;

    try write(writer, try messages.client.Login.init(init.gpa, "username", "password"));
    try writer.flush();

    while (true) {
        const response = try read(init.gpa, reader, Response(messages.server));
        errdefer freeResponse(init.gpa, response);

        switch (response) {
            .login => |login| {
                switch (login) {
                    .true => {
                        print("Login sucessful!\n", .{});
                    },
                    .false => |r| {
                        print("Login rejected: '{s}'!\n", .{r.reason});
                    },
                }

                freeResponse(init.gpa, login);
            },
            .excludedSearchPhrases => |excluded| {
                for (excluded.phrases) |p| print("{s}\n", .{p});
                freeResponse(init.gpa, excluded);
                return 0;
            },
            else => |other, tag| {
                print("WARNING: No handler for response {}: '{s}'.\n{any}\n\n", .{
                    @intFromEnum(tag),
                    @tagName(tag),
                    other,
                });
                freeResponse(init.gpa, other);
            },
        }
    }

    return 0;
}
