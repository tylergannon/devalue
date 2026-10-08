const std = @import("std");
const d = @import("devalue");
const Pair = struct { expected: d.Handle, actual: d.Handle };
// Compare against independently constructed native expectations. A bijection
// between handles checks both shared identity and distinct equal objects.
pub fn equal(expected: *d.Graph, ev: d.Value, actual: *d.Graph, av: d.Value) !void {
    var pairs: std.ArrayList(Pair) = .empty;
    defer pairs.deinit(std.testing.allocator);
    try visit(expected, ev, actual, av, &pairs);
}
fn visit(e: *d.Graph, ev: d.Value, a: *d.Graph, av: d.Value, pairs: *std.ArrayList(Pair)) anyerror!void {
    try std.testing.expectEqual(std.meta.activeTag(ev), std.meta.activeTag(av));
    if (ev != .ref) {
        try std.testing.expect(d.equal(ev, av));
        if (ev == .number and ev.number == 0) try std.testing.expectEqual(std.math.signbit(ev.number), std.math.signbit(av.number));
        return;
    }
    for (pairs.items) |pair| {
        if (pair.expected == ev.ref) {
            try std.testing.expectEqual(pair.actual, av.ref);
            return;
        }
        try std.testing.expect(pair.actual != av.ref);
    }
    try pairs.append(std.testing.allocator, .{ .expected = ev.ref, .actual = av.ref });
    const en = try e.node(ev);
    const an = try a.node(av);
    try std.testing.expectEqual(std.meta.activeTag(en), std.meta.activeTag(an));
    switch (en) {
        .object => |o| {
            try std.testing.expectEqual(o.null_proto, an.object.null_proto);
            try std.testing.expectEqual(o.properties.items.len, an.object.properties.items.len);
            for (o.properties.items, an.object.properties.items) |x, y| {
                try std.testing.expectEqualStrings(x.key, y.key);
                try visit(e, x.value, a, y.value, pairs);
            }
        },
        .array => |arr| {
            try std.testing.expectEqual(arr.length, an.array.length);
            try std.testing.expectEqual(arr.elements.items.len, an.array.elements.items.len);
            for (arr.elements.items, an.array.elements.items) |x, y| {
                try std.testing.expectEqual(x.index, y.index);
                try visit(e, x.value, a, y.value, pairs);
            }
        },
        .map => |m| {
            try std.testing.expectEqual(m.entries.items.len, an.map.entries.items.len);
            for (m.entries.items, an.map.entries.items) |x, y| {
                try visit(e, x.key, a, y.key, pairs);
                try visit(e, x.value, a, y.value, pairs);
            }
        },
        .set => |s| {
            try std.testing.expectEqual(s.values.items.len, an.set.values.items.len);
            for (s.values.items, an.set.values.items) |x, y| try visit(e, x, a, y, pairs);
        },
        .boxed => |v| try visit(e, v, a, an.boxed, pairs),
        .date => |ms| try std.testing.expectEqual(ms, an.date),
        .regexp => |re| {
            try std.testing.expectEqualStrings(re.source, an.regexp.source);
            try std.testing.expectEqualStrings(re.flags, an.regexp.flags);
        },
        .array_buffer => |bytes| try std.testing.expectEqualSlices(u8, bytes, an.array_buffer),
    }
}
