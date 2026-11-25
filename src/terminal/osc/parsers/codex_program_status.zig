const std = @import("std");
const osc = @import("../../osc.zig");

/// Parse the status fields emitted by the Codex TUI. Only Codex reports and
/// the app-less clear event are forwarded. All blocking kinds share one state.
pub fn parse(parser: *osc.Parser, _: ?u8) ?*osc.Command {
    const capture = if (parser.capture) |*value| value else return null;
    var fields = std.mem.splitScalar(u8, capture.trailing(), ':');
    var status: ?osc.Command.CodexProgramStatus = null;
    var app: ?[]const u8 = null;
    while (fields.next()) |field| {
        const separator = std.mem.indexOfScalar(u8, field, '=') orelse return null;
        const name = field[0..separator];
        const value = field[separator + 1 ..];
        if (std.mem.eql(u8, name, "state")) {
            if (status != null) return null;
            status = std.meta.stringToEnum(
                osc.Command.CodexProgramStatus,
                value,
            ) orelse return null;
        } else if (std.mem.eql(u8, name, "app")) {
            if (app != null) return null;
            app = value;
        }
    }
    const result = status orelse return null;
    if (app) |name| {
        if (!std.mem.eql(u8, name, "codex")) return null;
    } else if (result != .clear) return null;

    parser.command = .{ .codex_program_status = result };
    return &parser.command;
}

test "OSC 7501: Codex program status" {
    const cases = .{
        .{ "7501;state=working:app=codex", .working },
        .{ "7501;state=blocked:app=codex:kind=permission", .blocked },
        .{ "7501;state=idle:app=codex", .idle },
        .{ "7501;state=done:app=codex", .done },
        .{ "7501;state=error:app=codex", .@"error" },
        .{ "7501;state=clear", .clear },
    };
    inline for (cases) |case| {
        var parser: osc.Parser = .init(null);
        defer parser.deinit();
        for (case[0]) |byte| parser.next(byte);
        const command = parser.end('\\').?.*;
        try std.testing.expectEqual(
            @as(osc.Command, .{ .codex_program_status = case[1] }),
            command,
        );
    }
}

test "OSC 7501: ignore invalid or unrelated program status" {
    const cases = .{
        "7501;state=working",
        "7501;state=working:app=other",
        "7501;state=clear:app=other",
        "7501;state=working:state=idle:app=codex",
        "7501;state=unknown:app=codex",
        "7501;app=codex",
        "7501;",
    };
    inline for (cases) |input| {
        var parser: osc.Parser = .init(null);
        defer parser.deinit();
        for (input) |byte| parser.next(byte);
        try std.testing.expect(parser.end('\\') == null);
    }
}
