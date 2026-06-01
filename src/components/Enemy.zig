const math = @import("math");
const Vector3 = math.f32.Vector3;

pub const Timer = struct {
    duration: f32,
    elapsed: f32 = 0.0,

    pub inline fn up(self: *Timer) bool {
        return self.duration <= self.elapsed;
    }

    pub inline fn reset(self: *Timer) void {
        self.elapsed = 0.0;
    }

    /// Returns true if the timer is up.
    pub inline fn pass(self: *Timer, delta_time: f32) bool {
        self.elapsed += delta_time;
        return self.up();
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
    speed: f32,
    distance: f32, // Ideal combat distance while strafing

    weapon: struct {
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
        direction: Vector3,
        @"switch": Timer, // When to switch directions
    },
},
