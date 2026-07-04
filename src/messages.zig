const std = @import("std");
const Allocator = std.mem.Allocator;
const ascii = std.ascii;
const Type = std.builtin.Type;
const Md5 = std.crypto.hash.Md5;
const meta = std.meta;

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

const Recommendation = struct {
    recommendation: []u8,
    recommendations: i32
};

pub const server = struct {
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

        username: []const u8,
        message: []const u8,

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

    pub const AddThingILike = struct {
        pub const code = 51;

        item: []const u8,
    };

    pub const RemoveThingILike = struct {
        pub const code = 52;

        item: []const u8,
    };

    // TODO
    // pub const Recommendations = struct {
    //     pub const code = 54;

    //     pub const Response = struct {
    //         recommendations: []Recommendation,
    //         unrecommendations: []Recommendation,
    //     };
    // };

    // pub const GlobalRecommendations = struct {
    //     pub const code = 56;
    //     pub const Response = Recommendations.Response;
    // };

    // TODO:
    // pub const UserInterests = struct {
    //     pub const code = 57;

    //     username: []const u8,

    //     pub const Response = struct {
    //         username: []u8,
    //         liked: [][]u8,
    //         hated: [][]u8,
    //     };
    // };

    // TODO:
    // pub const RoomList = struct {
    //     pub const code = 64;

    //     pub const Response = struct {
    //         const List = struct {
    //             names: [][]u8,
    //             users: [][]u32,
    //         };

    //         public: List,
    //         private: List,
    //         abandoned: List,
    //     };
    // };

    pub const AdminMessage = struct {
        pub const code = 66;

        pub const Response = struct {
            message: []u8
        };
    };

    // TODO:
    // pub const PrivilegedUsers = struct {
    //     pub const code = 69;

    //     pub const Response = struct {
    //         users: [][]u8
    //     };
    // };

    pub const HaveNoParent = struct {
        pub const code = 71;

        no_parent: Bool
    };

    pub const ParentIp = struct {
        pub const code = 73;

        ip: u32
    };

    pub const ParentMinSpeed = struct {
        pub const code = 83;

        pub const Response = struct {
            speed: u32
        };
    };

    pub const ParentSpeedRatio = struct {
        pub const code = 84;

        pub const Response = struct {
            ratio: u32
        };
    };

    pub const CheckPrivileges = struct {
        pub const code = 92;

        pub const Response = struct {
            seconds: u32
        };
    };

    // TODO:
    // pub const EmbeddedMessage = struct {
    //     pub const code = 93;

    //     pub const Response = struct {
    //         message: main.Response,
    //     };
    // };

    pub const AcceptChildren = struct {
        pub const code = 100;

        accept: Bool
    };

    // TODO:
    // pub const PossibleParents = struct {
    //     pub const code = 102;

    //     pub const Response = struct {
    //         parents: []struct {
    //             username: []u8,
    //             ip: u32,
    //             port: u32
    //         }
    //     };
    // };

    pub const WishlistSearch = struct {
        pub const code = 103;

        token: u32,
        query: []const u8,
    };

    pub const WishlistInterval = struct {
        pub const code = 104;

        pub const Response = struct {
            interval: u32
        };
    };

    // TODO:
    // pub const SimilarUsers = struct {
    //     pub const code = 110;

    //     pub const Response = struct {
    //         users: []struct {
    //             username: []u8,
    //             rating: u32
    //         }
    //     };
    // };

    // TODO:
    // pub const ItemRecommendations = struct {
    //     pub const code = 111;

    //     item: []const u8,

    //     pub const Response = struct {
    //         item: []u8,
    //         recommendations: []Recommendation
    //     };
    // };

    // TODO:
    // pub const ItemSimilarUsers = struct {
    //     pub const code = 112;

    //     item: []const u8,

    //     pub const Response = struct {
    //         item: []u8,
    //         users: [][]u32
    //     };
    // };

    // TODO:
    // pub const RoomTickers = struct {
    //     pub const code = 113;

    //     pub const Response = struct {
    //         room: []u8,
    //         users: []struct {
    //             username: []u8,
    //             tickers: []u8
    //         }
    //     };
    // };

    pub const RoomTickerAdded = struct {
        pub const code = 114;

        pub const Response = struct {
            room: []u8,
            username: []u8,
            ticker: []u8
        };
    };

    pub const RoomTickerRemoved = struct {
        pub const code = 115;

        pub const Response = struct {
            room: []u8,
            ticker: []u8
        };
    };

    pub const SetRoomTicker = struct {
        pub const code = 116;

        room: []const u8,
        ticker: []const u8,
    };

    pub const AddThingIHate = struct {
        pub const code = 117;

        item: []const u8
    };

    pub const RemoveThingIHate = struct {
        pub const code = 118;

        item: []const u8
    };

    pub const RoomSearch = struct {
        pub const code = 120;

        room: []const u8,
        token: u32,
        query: []const u8,
    };

    pub const SendUploadSpeed = struct {
        pub const code = 121;

        speed: u32
    };

    pub const UserPrivileged = struct {
        pub const code = 122;

        username: []const u8,

        pub const Response = struct {
            username: []u8,
            privileged: Bool
        };
    };

    pub const GivePrivileges = struct {
        pub const code = 123;

        username: []const u8,
        days: u32
    };

    pub const NotifyPrivileges = struct {
        pub const code = 124;

        token: u32,
        username: []const u8,

        pub const Response = struct {
            token: u32,
            username: []u8,
        };
    };

    pub const AckNotifyPrivileges = struct {
        pub const code = 125;

        token: u32,
    };

    pub const BranchLevel = struct {
        pub const code = 126;

        level: u32
    };

    pub const BranchRoot = struct {
        pub const code = 127;

        root: []const u8
    };

    pub const ResetDistributed = struct {
        pub const code = 130;
    };

    // TODO:
    // pub const RoomMembers = struct {
    //     pub const code = 133;

    //     pub const Response = struct {
    //         room: []u8,
    //         members: [][]u8,
    //     };
    // };

    // It is tempting to make room and username into a struct that could be
    // used here and in other places as well, but I'm not sure how to handle
    // the differing constness of the child slices cleanly in zig. A function
    // that returns a type feels over the top here.
    pub const AddRoomMember = struct {
        pub const code = 134;

        room: []const u8,
        username: []const u8,

        pub const Response = struct {
            room: []u8,
            username: []u8,
        };
    };

    pub const RemoveRoomMember = struct {
        pub const code = 135;

        room: []const u8,
        username: []const u8,

        pub const Response = struct {
            room: []u8,
            username: []u8,
        };
    };

    pub const CancelRoomMembership = struct {
        pub const code = 136;

        room: []const u8
    };

    pub const CancelRoomOwnership = struct {
        pub const code = 137;

        room: []const u8
    };

    pub const RoomMembershipGranted = struct {
        pub const code = 139;

        pub const Response = struct {
            room: []u8
        };
    };

    pub const RoomMembershipRevoked = struct {
        pub const code = 140;

        pub const Response = struct {
            room: []u8
        };
    };

    pub const EnableRoomInvitations = struct {
        pub const code = 141;

        enable: Bool,

        pub const Response = struct {
            enable: Bool,
        };
    };

    pub const ChangePassword = struct {
        pub const code = 142;

        pass: []const u8,

        pub const Response = struct {
            pass: []u8
        };
    };

    pub const AddRoomOperator = struct {
        pub const code = 143;

        room: []const u8,
        username: []const u8,

        pub const Response = struct {
            room: []u8,
            username: []u8,
        };
    };

    pub const RemoveRoomOperator = struct {
        pub const code = 144;

        room: []const u8,
        username: []const u8,

        pub const Response = struct {
            room: []u8,
            username: []u8,
        };
    };

    pub const RoomOperatorshipGranted = struct {
        pub const code = 145;

        pub const Response = struct {
            room: []u8
        };
    };

    pub const RoomOperatorshipRevoked = struct {
        pub const code = 146;

        pub const Response = struct {
            room: []u8
        };
    };

    // TODO:
    // pub const RoomOperators = struct {
    //     pub const code = 148;

    //     pub const Response = struct {
    //         room: []u8,
    //         operators: [][]u8
    //     };
    // };

    pub const MessageUsers = struct {
        pub const code = 149;

        // TODO:
        users: []const []const u8,
    };

    pub const JoinGlobalRoom = struct {
        pub const code = 150;
    };

    pub const LeaveGlobalRoom = struct {
        pub const code = 151;
    };

    pub const GlobalRoomMessage = struct {
        pub const code = 152;

        pub const response = struct { 
            room: []u8,
            username: []u8,
            message: []u8
        };
    };

    // pub const ExcludedSearchPhrases = struct {
    //     pub const code = 160;

    //     pub const Response = struct {
    //         phrases: [][]u8
    //     };
    // };

    pub const CantConnectToPeer = struct {
        pub const code = 1001;

        token: u32,
        username: []const u8,

        pub const Response = struct {
            token: u32
        };
    };

    pub const CantCreateRoom = struct {
        pub const code = 1003;

        pub const Response = struct {
            room: []u8
        };
    };
};

/// Tagged unions for different response types.
pub const responses = struct {
    fn Responses(Messages: type) type {
        const decls = @typeInfo(Messages).@"struct".decls;
        var filtered: [decls.len]Type.Declaration = undefined;

        var count = 0;
        for (decls) |decl| {
            const Request = @field(Messages, decl.name);
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
            const Request = @field(Messages, decl.name);
            T.* = Request.Response;
            value.* = Request.code;
            name.* = .{ ascii.toLower(decl.name[0]) } ++ decl.name[1..];
        }

        const Tag = @Enum(u32, .exhaustive, &names, &values);
        return @Union(.@"auto", Tag, &names, &types, &attrs);
    }

    pub const Server = Responses(server);
};
