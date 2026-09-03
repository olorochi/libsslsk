const std = @import("std");
const Allocator = mem.Allocator;
const ascii = std.ascii;
const Type = std.builtin.Type;
const Md5 = std.crypto.hash.Md5;
const mem = std.mem;

const FatBool = enum(u32) { false = 0, true = 1 };
const Bool = enum(u8) { false = 0, true = 1 };

const Obfuscation = enum(u32) { none = 0, rotated = 1 };

const Status = enum(u8) { offline = 0, away = 1, online = 2 };

const ConnectionType = [1]enum(u8) { p2p = 'P', file = 'F', distributed = 'D' };

const Hash = [Md5.digest_length * 2]u8;

const Recommendation = struct { recommendation: []const u8, recommendations: i32 };

pub fn Response(messages: type) type {
    const decls = @typeInfo(messages).@"struct".decls;
    const count = decls.len - 1;

    const attrs: [count]Type.UnionField.Attributes = @splat(.{ .@"align" = null });
    var types: [count]type = undefined;
    var values: [count]messages.Tag = undefined;
    var names: [count][]const u8 = undefined;

    var i = 0;
    for (decls) |decl| {
        if (mem.eql(u8, decl.name, "Tag")) continue;
        types[i] = @field(messages, decl.name);
        values[i] = types[i].code;
        names[i] = .{ascii.toLower(decl.name[0])} ++ decl.name[1..];
        i += 1;
    }

    const UTag = @Enum(messages.Tag, .exhaustive, &names, &values);
    return @Union(.auto, UTag, &names, &types, &attrs);
}

pub const client = struct {
    pub const Tag = u32;

    pub const Login = struct {
        pub const code: Tag = 1;

        username: []const u8,
        password: []const u8,
        major: u32 = 177,
        hash: Hash,
        minor: u32 = 1,

        pub fn init(gpa: Allocator, username: []const u8, password: []const u8) !Login {
            const concat = try mem.concat(gpa, u8, &.{ username, password });
            defer gpa.free(concat);
            var login: Login = .{ .username = username, .password = password, .hash = undefined };

            const hash = login.hash[0..16];
            Md5.hash(concat, hash, .{});
            @memmove(&login.hash, &std.fmt.bytesToHex(hash, .lower));

            return login;
        }
    };

    /// Tell the server what port the client is listening on.
    pub const SetWaitPort = struct {
        pub const code: Tag = 2;

        port: u32,
        /// This is rarely used. Nicotine+ does not even support it.
        obfuscation: ?struct { type: Obfuscation, port: u32 } = null,

        // TODO: obfuscated init
    };

    /// Ask for ip and port information about a peer.
    pub const GetPeerAddress = struct {
        pub const code: Tag = 3;

        username: []const u8,
    };

    /// Request stats about a user. The soulseek server does not actually send
    /// notifications for this anymore, but only an initial response. Consider
    /// GetUserStatus and GetUserStats.
    pub const WatchUser = struct {
        pub const code: Tag = 5;

        username: []const u8,
    };

    /// Stop watching user. Deprecated?
    pub const UnwatchUser = struct {
        pub const code: Tag = 6;

        username: []const u8,
    };

    pub const GetUserStatus = struct {
        pub const code: Tag = 7;

        username: []const u8,
    };

    pub const SayChatroom = struct {
        pub const code: Tag = 13;

        room: []const u8,
        message: []const u8,
    };

    pub const JoinRoom = struct {
        pub const code: Tag = 14;

        room: []const u8,
        private: u32,
    };

    pub const LeaveRoom = struct {
        pub const code: Tag = 15;

        room: []const u8,
    };

    pub const ConnectToPeer = struct {
        pub const code: Tag = 18;

        token: u32,
        username: []const u8,
        type: ConnectionType,
    };

    pub const MessageUser = struct {
        pub const code: Tag = 22;

        username: []const u8,
        message: []const u8,
    };

    pub const MessageAcked = struct {
        pub const code: Tag = 23;

        id: u32,
    };

    pub const FileSearch = struct {
        pub const code: Tag = 26;

        token: u32,
        query: []const u8,
    };

    pub const SetStatus = struct {
        pub const code: Tag = 28;

        status: Status,
    };

    pub const ServerPing = struct {
        pub const code: Tag = 32;
    };

    pub const SharedFoldersfiles = struct {
        pub const code: Tag = 35;

        dirs: u32,
        files: u32,
    };

    /// Request stats about a user.
    pub const GetUserStats = struct {
        pub const code: Tag = 36;

        username: []const u8,
    };

    pub const UserSearch = struct {
        pub const code: Tag = 42;

        username: []const u8,
        token: u32,
        query: []const u8,
    };

    pub const AddThingILike = struct {
        pub const code: Tag = 51;

        item: []const u8,
    };

    pub const RemoveThingILike = struct {
        pub const code: Tag = 52;

        item: []const u8,
    };

    pub const UserInterests = struct {
        pub const code: Tag = 57;

        username: []const u8,
    };

    pub const RoomList = struct {
        pub const code: Tag = 64;
    };

    pub const HaveNoParent = struct {
        pub const code: Tag = 71;

        no_parent: Bool,
    };

    pub const ParentIp = struct {
        pub const code: Tag = 73;

        ip: u32,
    };

    pub const CheckPrivileges = struct {
        pub const code: Tag = 92;
    };

    pub const AcceptChildren = struct {
        pub const code: Tag = 100;

        accept: Bool,
    };

    pub const WishlistSearch = struct {
        pub const code: Tag = 103;

        token: u32,
        query: []const u8,
    };

    pub const SimilarUsers = struct {
        pub const code: Tag = 110;
    };

    pub const ItemRecommendations = struct {
        pub const code: Tag = 111;

        item: []const u8,
    };

    pub const ItemSimilarUsers = struct {
        pub const code: Tag = 112;

        item: []const u8,
    };

    pub const SetRoomTicker = struct {
        pub const code: Tag = 116;

        room: []const u8,
        ticker: []const u8,
    };

    pub const AddThingIHate = struct {
        pub const code: Tag = 117;

        item: []const u8,
    };

    pub const RemoveThingIHate = struct {
        pub const code: Tag = 118;

        item: []const u8,
    };

    pub const RoomSearch = struct {
        pub const code: Tag = 120;

        room: []const u8,
        token: u32,
        query: []const u8,
    };

    pub const SendUploadSpeed = struct {
        pub const code: Tag = 121;

        speed: u32,
    };

    pub const UserPrivileged = struct {
        pub const code: Tag = 122;

        username: []const u8,
    };

    pub const GivePrivileges = struct {
        pub const code: Tag = 123;

        username: []const u8,
        days: u32,
    };

    pub const NotifyPrivileges = struct {
        pub const code: Tag = 124;

        token: u32,
        username: []const u8,
    };

    pub const AckNotifyPrivileges = struct {
        pub const code: Tag = 125;

        token: u32,
    };

    pub const BranchLevel = struct {
        pub const code: Tag = 126;

        level: u32,
    };

    pub const BranchRoot = struct {
        pub const code: Tag = 127;

        root: []const u8,
    };

    pub const ResetDistributed = struct {
        pub const code: Tag = 130;
    };

    pub const AddRoomMember = struct {
        pub const code: Tag = 134;

        room: []const u8,
        username: []const u8,
    };

    pub const RemoveRoomMember = struct {
        pub const code: Tag = 135;

        room: []const u8,
        username: []const u8,
    };

    pub const CancelRoomMembership = struct {
        pub const code: Tag = 136;

        room: []const u8,
    };

    pub const CancelRoomOwnership = struct {
        pub const code: Tag = 137;

        room: []const u8,
    };

    pub const EnableRoomInvitations = struct {
        pub const code: Tag = 141;

        enable: Bool,
    };

    pub const ChangePassword = struct {
        pub const code: Tag = 142;

        pass: []const u8,
    };

    pub const AddRoomOperator = struct {
        pub const code: Tag = 143;

        room: []const u8,
        username: []const u8,
    };

    pub const RemoveRoomOperator = struct {
        pub const code: Tag = 144;

        room: []const u8,
        username: []const u8,
    };

    pub const MessageUsers = struct {
        pub const code: Tag = 149;

        users: []const []const u8,
        message: []const u8,
    };

    pub const JoinGlobalRoom = struct {
        pub const code: Tag = 150;
    };

    pub const LeaveGlobalRoom = struct {
        pub const code: Tag = 151;
    };

    pub const CantConnectToPeer = struct {
        pub const code: Tag = 1001;

        token: u32,
        username: []const u8,
    };
};

pub const server = struct {
    pub const Tag = u32;

    const UserStats = struct {
        username: []const u8,
        avgspeed: u32,
        uploadnum: u32,
        unknown: u32,
        files: u32,
        dirs: u32,
    };

    pub const Login = union(Bool) {
        pub const code: Tag = 1;

        false: struct { reason: []const u8, details: ?[]const u8 },
        true: struct { greet: []const u8, ip: u32, hash: Hash, supporter: Bool },
    };

    pub const GetPeerAddress = struct {
        pub const code: Tag = 3;

        username: []const u8,
        ip: u32,
        port: u32,
        obfuscation: struct {
            type: Obfuscation,
            port: u16, // wtf? u16 ok but why be inconsistent?
        },
    };

    pub const WatchUser = struct {
        pub const code: Tag = 5;

        username: []const u8,
        stats: ?struct { status: Status, stats: UserStats, countrycode: ?[]const u8 },
    };

    pub const UnwatchUser = struct {
        pub const code: Tag = 6;

        username: []const u8,
        stats: UserStats,
    };

    pub const GetUserStatus = struct {
        pub const code: Tag = 7;

        username: []const u8,
        status: Status,
        privileged: Bool,
    };

    pub const SayChatroom = struct {
        pub const code: Tag = 13;

        room: []const u8,
        username: []const u8,
        message: []const u8,
    };

    pub const JoinRoom = struct {
        pub const code: Tag = 14;

        room: []const u8,
        users: []const []const u8,
        statuses: []const Status,
        stats: []const UserStats,
        slotsful: []const FatBool,
        countries: []const []const u8,
        private: ?struct { owner: []const u8, operators: []const []const u8 },
    };

    pub const LeaveRoom = client.LeaveRoom;

    pub const UserJoinedRoom = struct {
        pub const code: Tag = 16;

        room: []const u8,
        username: []const u8,
        status: Status,
        stats: UserStats,
        slotsful: FatBool,
        countrycode: []const u8,
    };

    pub const UserLeftRoom = struct {
        pub const code: Tag = 17;

        room: []const u8,
        username: []const u8,
    };

    pub const ConnectToPeer = struct {
        pub const code: Tag = 18;

        username: []const u8,
        type: ConnectionType,
        ip: u32,
        port: u32,
        token: u32,
        privileged: Bool,
        obfuscation: Obfuscation,
    };

    pub const MessageUser = struct {
        pub const code: Tag = 22;

        id: u32,
        timestamp: u32,
        username: []const u8,
        message: []const u8,
        new: Bool,
    };

    pub const SetStatus = struct {
        pub const code: Tag = 28;

        username: []const u8,
        token: u32,
        query: []const u8,
    };

    pub const GetUserStats = struct {
        pub const code: Tag = 36;

        username: []const u8,
        stats: UserStats,
    };

    pub const Relogged = struct {
        pub const code: Tag = 41;
    };

    pub const Recommendations = struct {
        pub const code: Tag = 54;

        recommendations: []const Recommendation,
        unrecommendations: []const Recommendation,
    };

    pub const GlobalRecommendations = struct {
        pub const code: Tag = 56;

        recommendations: []const Recommendation,
        unrecommendations: []const Recommendation,
    };

    pub const UserInterests = struct {
        pub const code: Tag = 57;

        username: []const u8,
        liked: []const []const u8,
        hated: []const []const u8,
    };

    pub const RoomList = struct {
        pub const code: Tag = 64;
        const List = struct {
            names: []const []const u8,
            users: []const u32,
        };

        public: List,
        owned: List,
        private: List,
        operated: []const []const u8,
    };

    pub const AdminMessage = struct {
        pub const code: Tag = 66;

        message: []const u8,
    };

    pub const PrivilegedUsers = struct {
        pub const code: Tag = 69;

        users: []const []const u8,
    };

    pub const ParentMinSpeed = struct {
        pub const code: Tag = 83;

        speed: u32,
    };

    pub const ParentSpeedRatio = struct {
        pub const code: Tag = 84;

        ratio: u32,
    };

    pub const CheckPrivileges = struct {
        pub const code: Tag = 92;

        seconds: u32
    };

    pub const EmbeddedMessage = distributed.DistribEmbeddedMessage;

    pub const PossibleParents = struct {
        pub const code: Tag = 102;

        parents: []const struct { username: []const u8, ip: u32, port: u32 },
    };

    pub const WishlistInterval = struct {
        pub const code: Tag = 104;

        interval: u32,
    };

    pub const SimilarUsers = struct {
        pub const code: Tag = 110;
        users: []const struct { username: []const u8, rating: u32 },
    };

    pub const ItemRecommendations = struct {
        pub const code: Tag = 111;

        item: []const u8,
        recommendations: []const Recommendation,
    };

    pub const ItemSimilarUsers = struct {
        pub const code: Tag = 112;

        item: []const u8,
        users: []const []const u32,
    };

    pub const RoomTickers = struct {
        pub const code: Tag = 113;

        room: []const u8,
        users: []const struct { username: []const u8, tickers: []const u8 },
    };

    pub const RoomTickerAdded = struct {
        pub const code: Tag = 114;

        room: []const u8,
        username: []const u8,
        ticker: []const u8,
    };

    pub const RoomTickerRemoved = struct {
        pub const code: Tag = 115;

        room: []const u8,
        ticker: []const u8,
    };

    pub const UserPrivileged = struct {
        pub const code: Tag = 122;

        username: []const u8,
        privileged: Bool,
    };

    pub const NotifyPrivileges = struct {
        pub const code: Tag = 124;

        token: u32,
        username: []const u8,
    };

    pub const AckNotifyPrivileges = struct {
        pub const code: Tag = 125;

        token: u32,
    };

    pub const RoomMembers = struct {
        pub const code: Tag = 133;

        room: []const u8,
        members: []const []const u8,
    };

    pub const AddRoomMember = client.AddRoomMember;
    pub const RemoveRoomMember = client.RemoveRoomMember;

    pub const RoomMembershipGranted = struct {
        pub const code: Tag = 139;

        room: []const u8,
    };

    pub const RoomMembershipRevoked = struct {
        pub const code: Tag = 140;

        room: []const u8,
    };

    pub const EnableRoomInvitations = client.EnableRoomInvitations;
    pub const ChangePassword = client.ChangePassword;

    pub const AddRoomOperator = client.AddRoomOperator;
    pub const RemoveRoomOperator = client.RemoveRoomOperator;

    pub const RoomOperatorshipGranted = struct {
        pub const code: Tag = 145;

        room: []const u8,
    };

    pub const RoomOperatorshipRevoked = struct {
        pub const code: Tag = 146;

        room: []const u8,
    };

    pub const RoomOperators = struct {
        pub const code: Tag = 148;

        room: []const u8,
        operators: []const []const u8,
    };

    pub const GlobalRoomMessage = struct {
        pub const code: Tag = 152;

        room: []const u8,
        username: []const u8,
        message: []const u8,
    };

    pub const ExcludedSearchPhrases = struct {
        pub const code: Tag = 160;

        phrases: []const []const u8,
    };

    pub const CantConnectToPeer = struct {
        pub const code: Tag = 1001;

        token: u32,
    };

    pub const CantCreateRoom = struct {
        pub const code: Tag = 1003;

        room: []const u8,
    };
};

pub const init = struct {
    pub const Tag = u8;

    pub const PeerInit = struct {
        pub const code: Tag = 1;

        username: []const u8,
        type: ConnectionType,
        token: u32 = 0,
    };

    pub const PeerInitResponse = struct {
        pub const code: Tag = 1;

        username: []const u8,
    };
};

pub const peer = struct {
    pub const Tag = u32;

    const TransferRejection = struct {
        const Reason = enum {
            Banned,
            Cancelled,
            Complete,
            @"File not shared.",
            @"File read error.",
            @"Pending shutdown.",
            Queued,
            @"Too many files",
            @"Too many megabytes",
        };

        string: []const u8,

        pub fn init(reason: Reason) TransferRejection {
            return TransferRejection{ .string = @tagName(reason) };
        }
    };

    const Directory = struct { directory: []const u8, files: []const File };
    const File = struct {
        // TODO: Detect attributes from file.
        const Attribute = struct {
            code: enum(u32) {
                bitrate = 0,
                duration = 1,
                vbr = 2,
                encoder = 3,
                sample_rate = 4,
                bit_depth = 5,
            },
            value: u32,
        };

        code: u8 = 1,
        name: []const u8,
        size: u64,
        /// Untrustworthy.
        extension: []const u8,
        attributes: []const Attribute,
    };

    pub const GetShareFileList = struct {
        pub const code: Tag = 4;
    };

    // TODO: zlib
    // pub const SharedFileListResponse = struct {
    //     pub const code: Tag = 5;

    //     public: []const Directory,
    //     unknown: u32 = 0,
    //     private: []const Directory,
    // };

    // pub const FileSearchResponse = struct {
    //     pub const code: Tag = 9;

    //     username: []const u8,
    //     token: u32,
    //     public:  []const File,
    //     slot_free: Bool,
    //     avgspeed: u32,
    //     queue: u32,
    //     unknown: u32 = 0,
    //     private: []const File
    // };

    pub const UserInfoRequest = struct {
        pub const code: Tag = 15;
    };

    pub const UserInfoResponse = struct {
        pub const code: Tag = 16;

        description: []const u8,
        picture: union(Bool) { false: void, true: []const u8 },
        upload: u32,
        queue: u32,
        slot_free: Bool,
        upload_permissions: ?enum(u32) { no_one = 0, everyone = 1, list = 2, permitted = 3 },
    };

    pub const FolderContentsRequest = struct {
        pub const code: Tag = 36;

        token: u32,
        folder: []const u8,
    };

    // TODO: zlib
    // pub const FolderContentsResponse = struct {
    //     pub const code: Tag = 37;

    //     token: u32,
    //     name: []const u8,
    //     folders: []const Directory,
    // };

    pub const TransferRequest = struct {
        pub const code: Tag = 40;

        direction: enum(u32) { download = 0, upload = 1 },
        token: u32,
        filename: []const u8,
        size: ?u64,
    };

    pub const TransferResponse = struct {
        pub const code: Tag = 41;

        token: u32,
        allowed: union(Bool) { false: TransferRejection, true: ?u64 },
    };

    pub const QueueUpload = struct {
        pub const code: Tag = 43;

        filename: []const u8,
    };

    pub const PlaceInQueueResponse = struct {
        pub const code: Tag = 44;

        filename: []const u8,
        place: u32,
    };

    pub const UploadFailed = struct {
        pub const code: Tag = 46;

        filename: []const u8,
    };

    pub const UploadDenied = struct {
        pub const code: Tag = 50;

        filename: []const u8,
        reason: TransferRejection,
    };

    pub const PlaceInQueueRequest = struct {
        pub const code: Tag = 51;

        filename: []const u8,
    };

    pub const UploadNotification = struct {
        pub const code: Tag = 52;
    };
};

pub const distributed = struct {
    pub const Tag = u8;

    const base = struct {
        pub const Tag = distributed.Tag;

        pub const DistribPing = struct {
            pub const code: base.Tag = 0;
        };

        pub const DistribSearch = struct {
            pub const code: base.Tag = 3;

            identifier: u32 = '1',
            username: []const u8,
            token: u32,
            query: []const u8,
        };

        pub const DistribBranchLevel = struct {
            pub const code: base.Tag = 4;

            level: i32,
        };

        pub const DistribBranchRoot = struct {
            pub const code: base.Tag = 5;

            root: []const u8,
        };
    };

    pub const DistribPing = base.DistribPing;
    pub const DistribSearch = base.DistribSearch;
    pub const DistribBranchLevel = base.DistribBranchLevel;
    pub const DistribBranchRoot = base.DistribBranchRoot;
    pub const DistribEmbeddedMessage = struct {
        pub const code: Tag = 93;

        message: Response(base),
    };
};
