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

// Maybe this is a bad name? Static memory is more of a mechanism here. The
// best use of this function is to transform a temporary (const in zig) to a
// mutable type, at the cost of a dereference in static memory.
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

const FatBool = enum(u8) {
    false = 0,
    true = 1
};

const Bool = enum(u8) {
    false = 0,
    true = 1
};

const Obfuscation = enum(u32) {
    none = 0,
    rotated = 1
};

const Status = enum(u8) {
    offline = 0,
    away = 1,
    online = 2
};

const UserStats = struct {
    username: []u8,
    avgspeed: u32,
    uploadnum: u32,
    unknown: u32,
    files: u32,
    dirs: u32,
};

pub const messages = struct {
    pub const Login = struct {
        pub const code = 1;

        username: []const u8,
        password: []const u8,
        major: u32 = 177,
        hash: [Md5.digest_length * 2]u8,
        minor: u32 = 1,

        pub const Response = union(Bool) {
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

    /// Tell the server what port the client is listening on.
    pub const SetWaitPort = struct {
        pub const code = 2;

        port: u32,
        /// This is rarely used. Nicotine+ does not even support it.
        obfuscation: ?struct {
            type: Obfuscation,
            port: u32
        } = null,

        // TODO: obfuscated init
    };

    /// Ask for ip and port information about a peer.
    pub const GetPeerAddress = struct {
        pub const code = 3;

        username: []const u8,

        pub const Response = struct {
            username: []u8,
            ip: u32,
            port: u32,
            obfuscation: struct {
                type: Obfuscation,
                port: u16 // wtf? u16 ok but why be inconsistent?
            }
        };
    };

    /// Request stats about a user. The soulseek server does not actually send
    /// notifications for this anymore, but only an initial response. Consider
    /// GetUserStatus and GetUserStats.
    pub const WatchUser = struct {
        pub const code = 5;

        username: []const u8,

        pub const Response = struct {
            username: []u8,
            stats: ?struct {
                status: Status,
                stats: UserStats,
                countrycode: ?[]u8
            }
        };
    };

    /// Stop watching user. Deprecated?
    pub const UnwatchUser = struct {
        pub const code = 6;

        username: []const u8,

        pub const Response = struct {
            username: []u8,
            stats: UserStats,
        };
    };

    pub const GetUserStatus = struct {
        pub const code = 7;

        username: []const u8,

        pub const Response = struct {
            username: []u8,
            status: Status,
            privileged: Bool,
        };
    };

    pub const SayChatroom = struct {
        pub const code = 13;

        room: []const u8,
        message: []const u8,

        pub const Response = struct {
            room: []u8,
            username: []u8,
            message: []u8,
        };
    };

    // TODO:
    // pub const JoinRoom = struct {
    //     pub const code = 14;

    //     room: []const u8,
    //     private: u32,

    //     pub const Response = struct {
    //         room: []u8,
    //         users: [][]u8,
    //         statuses: []Status,
    //         stats: []UserStats,
    //         slotsful: []FatBool,
    //         countries: [][]u8,
    //         private: ?struct {
    //             owner: []u8,
    //             operators: [][]u8
    //         }
    //     };
    // };

    pub const LeaveRoom = struct {
        pub const code = 15;

        room: []const u8,

        pub const Response = struct {
            room: []u8,
        };
    };

    pub const UserJoinedRoom = struct {
        pub const code = 16;

        pub const Response = struct {
            room: []u8,
            username: []u8,
            status: Status,
            stats: UserStats,
            slotsful: FatBool,
            countrycode: []u8
        };
    };

    pub const UserLeftRoom = struct {
        pub const code = 17;

        pub const Response = struct {
            room: []u8,
            username: []u8,
        };
    };

    // TODO: ConnectionType
    // pub const ConnectToPeer = struct {
    //     pub const code = 18;

    //     token: u32,
    //     username: []u8,
    //     type: []u8,

    //     pub const Response = struct {
    //         username: []u8,
    //         type: ConnectionType,
    //         ip: u32,
    //         port: u32,
    //         token: u32,
    //         privileged: bool,
    //         obfuscation: Obfuscation
    //     };
    // };

    pub const MessageUser = struct {
        pub const code = 22;

        username: []u8,
        message: []u8,

        pub const Response = struct {
            username: []u8,
        };
    };

    pub const MessageAcked = struct {
        pub const code = 23;

        id: u32,
    };

    pub const FileSearch = struct {
        pub const code = 26;

        token: u32,
        query: []u8,

        pub const Response = struct {
            username: []u8,
            token: u32,
            query: []u8,
        };
    };

    pub const SetStatus = struct {
        pub const code = 28;

        status: Status,
    };

    pub const ServerPing = struct {
        pub const code = 32;
    };

    pub const SharedFoldersfiles = struct {
        pub const code = 35;

        dirs: u32,
        files: u32
    };

    /// Request stats about a user.
    pub const GetUserStats = struct {
        pub const code = 36;

        username: []const u8,

        pub const Response = struct {
            username: []u8,
            stats: UserStats,
        };
    };

    pub const Relogged = struct {
        pub const code = 41;
        pub const Response = void;
    };


    pub const UserSearch = struct { 
        pub const code = 42;
    };
};

/// A tagged union for every implemented soulseek protocol response.
const Response = blk: {
    const decls = @typeInfo(messages).@"struct".decls;
    var filtered: [decls.len]Type.Declaration = undefined;

    var count = 0;
    for (decls) |decl| {
        const Request = @field(messages, decl.name);
        if (@hasDecl(Request, "Response")) {
            filtered[count] = decl;
            count += 1;
        }
    }

    const attrs: [count]Type.UnionField.Attributes = @splat(.{ .@"align" = null });
    var types: [count]type = undefined;
    var values: [count]u32 = undefined;
    var names: [count][]const u8 = undefined;

    for (filtered[0..count], &names, &types, &values) |decl, *name, *T, *value| {
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
