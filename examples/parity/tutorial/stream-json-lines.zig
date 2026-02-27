const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/stream-json-lines/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    const chunks = [_][]const u8{
        "{\"page\":\"tutorial/stream-json-lines/\",\"step\":1}\n",
        "{\"page\":\"tutorial/stream-json-lines/\",\"step\":2}\n",
        "{\"done\":true}\n",
    };
    return zigmund.Response.streamChunks(allocator, &chunks, "application/x-ndjson");
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/stream-json-lines", implemented, .{
        .summary = "Parity implementation for tutorial/stream-json-lines/",
        .tags = &.{ "parity", "tutorial" },
    });
}
