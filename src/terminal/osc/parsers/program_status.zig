const std = @import("std");
const osc = @import("../../osc.zig");

const ProgramStatus = osc.Command.ProgramStatus;

pub fn parse(parser: *osc.Parser, _: ?u8) ?*osc.Command {
    const capture = if (parser.capture) |*value| value else return null;
    const payload = capture.trailing();
    if (std.mem.eql(u8, payload, "?")) {
        parser.command = .{ .program_status = .{ .state = .query } };
        return &parser.command;
    }

    var fields = std.mem.splitScalar(u8, payload, ':');
    var state: ?ProgramStatus.State = null;
    var app: ?ProgramStatus.App = null;
    while (fields.next()) |field| {
        const separator = std.mem.indexOfScalar(u8, field, '=') orelse return null;
        const name = field[0..separator];
        const value = field[separator + 1 ..];
        if (std.mem.eql(u8, name, "state")) {
            if (state != null) return null;
            state = std.meta.stringToEnum(ProgramStatus.State, value) orelse return null;
            if (state == .query) return null;
        } else if (std.mem.eql(u8, name, "app")) {
            if (app != null) return null;
            app = if (std.mem.eql(u8, value, "codex"))
                .codex
            else if (std.mem.eql(u8, value, "claude-code"))
                .claude_code
            else
                return null;
        }
    }

    const result = state orelse return null;
    if (app == null and result != .clear) return null;
    parser.command = .{ .program_status = .{
        .app = app orelse .unspecified,
        .state = result,
        .payload = payload,
    } };
    return &parser.command;
}

test "OSC 7501: program status and capability query" {
    const Case = struct {
        payload: []const u8,
        app: ProgramStatus.App = .unspecified,
        state: ProgramStatus.State,
    };
    const cases = [_]Case{
        .{ .payload = "?", .state = .query },
        .{ .payload = "state=working:app=codex", .app = .codex, .state = .working },
        .{ .payload = "state=idle:app=codex", .app = .codex, .state = .idle },
        .{ .payload = "state=done:app=codex", .app = .codex, .state = .done },
        .{
            .payload = "state=blocked:app=claude-code:id=task:kind=permission",
            .app = .claude_code,
            .state = .blocked,
        },
        .{
            .payload = "state=done:app=claude-code:id=task:title=SGk=:msg=RG9uZQ==",
            .app = .claude_code,
            .state = .done,
        },
        .{ .payload = "state=error:app=claude-code", .app = .claude_code, .state = .@"error" },
        .{ .payload = "state=clear", .state = .clear },
        .{ .payload = "state=clear:id=task", .state = .clear },
    };
    for (cases) |case| {
        var parser: osc.Parser = .init(null);
        defer parser.deinit();
        for ("7501;") |byte| parser.next(byte);
        for (case.payload) |byte| parser.next(byte);
        const report = parser.end('\\').?.program_status;
        try std.testing.expectEqual(case.app, report.app);
        try std.testing.expectEqual(case.state, report.state);
        try std.testing.expectEqualStrings(
            if (case.state == .query) "" else case.payload,
            report.payload,
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
        "7501;state=query:app=claude-code",
        "7501;?bad",
        "7501;",
    };
    inline for (cases) |input| {
        var parser: osc.Parser = .init(null);
        defer parser.deinit();
        for (input) |byte| parser.next(byte);
        try std.testing.expect(parser.end('\\') == null);
    }
}
