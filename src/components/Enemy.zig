const math = @import("math");
const Vector3 = math.f32.Vector3;

pub const Timer = struct {
    duration: f32,
    elapsed: f32,

    pub fn init(duration: f32, state: enum { finished, running }) Timer {
        return switch (state) {
            .finished => .{ .duration = duration, .elapsed = duration + 0.1 },
            .running => .{ .duration = duration, .elapsed = 0.0 },
        };
    }

    pub inline fn up(self: *Timer) bool {
        return self.duration <= self.elapsed;
    }

    pub inline fn reset(self: *Timer) void {
        self.elapsed = 0.0;
    }

    /// Returns true if the timer is up.
    pub inline fn pass(self: *Timer, delta_time: f32) bool {
        const done = self.up();
        if (!done) self.elapsed += delta_time;

        return done;
    }
};

pub const State = enum {
    patrol,
    follow,
    attack,
};

state: State,

vision: struct {
    memory: Timer,
    distance: f32,
    angle: f32,
},

follow: struct {
    accuracy: f32,
    distance: f32,
    speed: f32,
},

patrol: struct {
    path: struct {
        waypoints: [4]Vector3,
        i: usize = 0,

        pub inline fn next(self: *@This(), random: usize) void {
            const new = (self.i + random) % self.waypoints.len;

            if (self.i == new) {
                self.i = (self.i + 1) % self.waypoints.len;
                return;
            }

            self.i = new;
        }

        pub inline fn current(self: @This()) Vector3 {
            return self.waypoints[self.i];
        }
    },

    wait: Timer,
    accuracy: f32,
    speed: f32,
},

attack: struct {
    range: f32,

    move: struct {
        speed: f32,
        distance: struct {
            current: f32 = 0.0,
            max: f32,
            min: f32,
            change: Timer,
        },
    },

    weapon: struct {
        // TODO: SHOTGUN
        type: union(enum) {
            burst: struct {
                length: Timer,
                rpm: Timer,
            },
            single: void,
        },

        cooldown: Timer,

        bullet: struct {
            speed: f32,
            damage: f32,
        },
    },

    jump: struct {
        force: f32,
        cooldown: Timer,
    },

    strafe: struct {
        speed: f32,
        direction: f32 = 0.0,
        change: Timer,
    },
},
