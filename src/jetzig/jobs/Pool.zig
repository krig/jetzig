const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Pool = @This();

allocator: std.mem.Allocator,
jet_kv: *jetzig.jetkv.JetKV,
job_definitions: []const jetzig.jobs.JobDefinition,
logger: jetzig.loggers.Logger,
pool: std.Thread.Pool = undefined,
workers: std.ArrayList(*jetzig.jobs.Worker),

/// Initialize a new worker thread pool.
pub fn init(
    allocator: std.mem.Allocator,
    jet_kv: *jetzig.jetkv.JetKV,
    job_definitions: []const jetzig.jobs.JobDefinition,
    logger: jetzig.loggers.Logger,
) Pool {
    return .{
        .allocator = allocator,
        .jet_kv = jet_kv,
        .job_definitions = job_definitions,
        .logger = logger,
        .workers = std.ArrayList(*jetzig.jobs.Worker).init(allocator),
    };
}

/// Free pool resources and destroy workers.
pub fn deinit(self: *Pool) void {
    self.pool.deinit();
    for (self.workers.items) |worker| self.allocator.destroy(worker);
    self.workers.deinit();
}

/// Spawn a given number of threads and start processing jobs, sleep for a given interval (ms)
/// when no jobs are in the queue. Each worker operates its own work loop.
pub fn work(self: *Pool, threads: usize, interval: usize) !void {
    try self.pool.init(.{ .allocator = self.allocator });

    for (0..threads) |index| {
        const worker = try self.allocator.create(jetzig.jobs.Worker);
        worker.* = jetzig.jobs.Worker.init(
            self.allocator,
            self.logger,
            index,
            self.jet_kv,
            self.job_definitions,
            interval,
        );
        try self.workers.append(worker);
        try self.pool.spawn(jetzig.jobs.Worker.work, .{worker});
    }
}