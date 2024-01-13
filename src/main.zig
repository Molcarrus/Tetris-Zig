// TODO: High score in the `update` function in the `Game` struct

const std = @import("std");
const rand = std.rand;
const debug = std.debug;

const raylib = @cImport({
    @cInclude("raylib.h");
});

const grid_width: i32 = 10;
const grid_height: i32 = 20;
const grid_cell_size: i32 = 32;
const margin: i32 = 20;
const piece_preview_width = grid_cell_size * 5;
const screen_width: i32 = grid_width*grid_cell_size + margin*2 + piece_preview_width + margin;
const screen_height: i32 = grid_height*grid_cell_size + margin;

fn rgb(r: u8, g: u8, b: u8) raylib.Color {
    return .{ 
        .r = r,
        .g = g,
        .b = b,
        .a = 255,
    };
}

fn rgba(r: u8, g: u8, b: u8, a: u8) raylib.Color {
    return .{ 
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
}

const BackgroundColor = rgb(29, 38, 57);
const BackgroundHighlightColor = rgb(39, 48, 67);
const BorderColor = rgb(3, 2, 1);

const State = enum {
    StartScreen,
    Play,
    Pause,
    GameOver,
};

const Pos = struct {
    x: i32,
    y: i32,
};

fn p(x: i32, y: i32) Pos {
    return Pos{ .x = x, .y = y };
}

const Type = enum {
    Cube,
    Long,
    Z,
    S,
    T,
    L,
    J,
};

fn piece_color(t: Type) raylib.Color {
    return switch(t) {
        Type.Cube => rgb(241, 211, 90),
        Type.Long => rgb(83, 179, 219),
        Type.L => rgb(92, 205, 162),
        Type.J => rgb(231, 111, 124),
        Type.T => rgb(195, 58, 47),
        Type.S => rgb(96, 150, 71),
        Type.Z => rgb(233, 154, 56),
    };
}

fn random_type(rng: *rand.DefaultPrng) Type {
    return rng.random().enumValue(Type);
}

const Rotation = enum { 
    A,
    B,
    C,
    D,
};

const Square = struct {
    color: raylib.Color,
    active: bool,
};

const Level = struct {
    tick_rate: i32,
    value: usize,

    pub fn get_level(piece_count: usize) Level {
        return switch(piece_count) {
            0...10 => Level{ .value = 1, .tick_rate = 30 },
            11...25 => Level{ .value = 2, .tick_rate = 30 },
            26...50 => Level{ .value = 3, .tick_rate = 25 },
            51...100 => Level{ .value = 4, .tick_rate = 25 },
            101...150 => Level{ .value = 5, .tick_rate = 20 },
            151...200 => Level{ .value = 6, .tick_rate = 20 },
            201...250 => Level{ .value = 7, .tick_rate = 15 },
            251...300 => Level{ .value = 8, .tick_rate = 15 },
            301...350 => Level{ .value = 9, .tick_rate = 12 },
            351...400 => Level{ .value = 10, .tick_rate = 12 },
            401...450 => Level{ .value = 11, .tick_rate = 10 },
            451...500 => Level{ .value = 12, .tick_rate = 10 },
            501...600 => Level{ .value = 13, .tick_rate = 8 },
            601...700 => Level{ .value = 14, .tick_rate = 8 },
            701...800 => Level{ .value = 15, .tick_rate = 6 },
            else => Level{ .value = 16, .tick_rate = 5 },
        };
    }
};

const Game = struct {
    grid: [grid_width*grid_height]Square,
    square: [4]Pos,
    rng: rand.DefaultPrng,
    state: State,
    t: Type,
    next_type: Type,
    r: Rotation,
    tick: i32,
    freeze_down: i32,
    freeze_input: i32,
    freeze_space: i32,
    x: i32,
    y: i32,
    score: usize,
    piece_count: usize,
    rows_this_tick: usize,
    level: Level,

    pub fn init() Game {
        var grid: [grid_width*grid_height]Square = undefined;
        for (&grid) |*item| {
            item.* = Square{ .color = raylib.WHITE, .active = false };
        }

        var buf: [8]u8 = undefined;
        std.crypto.random.bytes(buf[0..8]);
        const seed = std.mem.readInt(u64, buf[0..8], std.builtin.Endian.little);
        var r = rand.DefaultPrng.init(seed);

        const t = random_type(&r);
        const next_type = random_type(&r);
        const squares = Game.get_squares(t, Rotation.A);

        return Game {
            .grid = grid,
            .square = squares,
            .rng = r,
            .state = State.StartScreen,
            .t = t,
            .next_type = next_type,
            .r = Rotation.A,
            .tick = 0,
            .freeze_down = 0,
            .freeze_input = 0,
            .freeze_space = 0,
            .x = 4,
            .y = 0,
            .score = 0,
            .piece_count = 1,
            .rows_this_tick = 0,
            .level = Level.get_level(1),
        };
    }

    fn anykey(self: *Game) bool {
        _ = self;
        const k = raylib.GetKeyPressed();
        if (k != raylib.KEY_NULL) {
            return true;
        } else {
            if ((raylib.IsKeyReleased(raylib.KEY_DOWN)) or 
               (raylib.IsKeyReleased(raylib.KEY_LEFT)) or
               (raylib.IsKeyReleased(raylib.KEY_RIGHT)) or
               (raylib.IsKeyReleased(raylib.KEY_DOWN)) or
                (raylib.IsKeyReleased(raylib.KEY_ENTER))) {
                 return true;
            }
        }

        return false;
    }

    pub fn update(self: *Game) void {
        switch (self.state) {
            State.StartScreen => {
                if (self.anykey()) {
                    self.freeze_space = 30;
                    self.state = State.Play;
                }
            },
            State.GameOver => {
                if (self.anykey() and self.freeze_input == 0) {
                    self.reset();
                    self.piece_reset();
                    self.tick = 0;
                    self.score = 0;
                    self.rows_this_tick = 0;
                    self.state = State.Play;
                }
            },
            State.Play => {
                if (raylib.IsKeyReleased(raylib.KEY_ESCAPE)) {
                    self.state = State.Pause;
                    return;
                }
                if (raylib.IsKeyPressed(raylib.KEY_RIGHT) or raylib.IsKeyPressed(raylib.KEY_D)) {
                    self.move_right();
                }
                if (raylib.IsKeyPressed(raylib.KEY_LEFT) or raylib.IsKeyPressed(raylib.KEY_A)) {
                    self.move_left();
                } 
                if (raylib.IsKeyDown(raylib.KEY_DOWN) or raylib.IsKeyPressed(raylib.KEY_S)) {
                    if (self.freeze_down <= 0) {
                        const moved = self.move_down();
                        if (!moved) {
                            self.freeze_down = 60;
                        }
                    }
                }
                if (raylib.IsKeyReleased(raylib.KEY_DOWN) or raylib.IsKeyReleased(raylib.KEY_S)) {
                    self.freeze_down = 0;
                }
                if (raylib.IsKeyPressed(raylib.KEY_RIGHT_CONTROL) or raylib.IsKeyPressed(raylib.KEY_W)) {
                    self.rotate();
                }
                if (self.tick >= self.level.tick_rate) {
                    _ = self.move_down();
                    self.remove_full_rows();
                    self.tick = 0;
                    self.update_score();
                    self.update_level();
                }
                self.tick += 1;
            },
            State.Pause => {
                if (raylib.IsKeyReleased(raylib.KEY_ESCAPE)) {
                    self.state = State.Play;
                }
            },
        }
        if (self.freeze_down > 0) {
            self.freeze_down -= 1;
        }
        if (self.freeze_space > 0) {
            self.freeze_space -= 1;
        }
        if (self.freeze_input > 0) {
            self.freeze_input -= 1;
        }
    }

    fn update_score(self: *Game) void {
        const bonus: usize = switch (self.rows_this_tick) {
            0 => 0,
            1 => 1,
            2 => 3,
            3 => 5,
            4 => 8,
            else => unreachable,
        };
        self.score += bonus;
        self.rows_this_tick = 0;
    }

    fn update_level(self: *Game) void {
        const previous_level = self.level;
        self.level = Level.get_level(self.piece_count);
        if (self.level.value != previous_level.value) {
            debug.print("level: {}, speed: {}\n", .{self.level.value, self.level.tick_rate});
        }
    }

    fn row_is_full(self: Game, y: i32) bool {
        if (y >= self.grid.len or y < 0) {
            debug.print("Row index out of bounds {}", .{y});
            return false;
        }
        var x: i32 = 0;
        
        return while (x < grid_width) : (x+=1) {
            if (!self.get_active(x, y)) {
                break false;
            } 
        } else true;
    }

    fn copy_row(self: *Game, y1: i32, y2: i32) void {
        if (y1 == y2) {
            debug.print("Invalid copy, {} must not equal {}\n", .{y1, y2});
            return;
        }
        if (y2 < 0 or y1 >= grid_height or y2 >= grid_height) {
            debug.print("Invalid copy, {} or {} is out of bounds\n", .{y1, y2});
            return;
        } 
        var x: i32 = 0;
        while (x < grid_width) : (x+=1) {
            if (y1 < 0) {
                self.set_active_state(x, y2, false);
                self.set_grid_color(x, y2, raylib.WHITE);
            } else {
                self.set_active_state(x, y2, self.get_active(x, y1));
                self.set_grid_color(x, y2, self.get_grid_color(x, y1));
            }
        }
    }

    fn copy_rows(self: *Game, src_y: i32, dst_y: i32) void {
        if (src_y >= dst_y) {
            debug.print("{} must be less than {}\n", .{src_y, dst_y});
            return;
        }
        var y1: i32 = src_y;
        var y2: i32 = dst_y;
        while (y2 > -1) {
            self.copy_row(y1, y2);
            y1 -= 1;
            y2 -= 1;
        }
    }

    pub fn remove_full_rows(self: *Game) void {
        var y: i32 = grid_height - 1;
        var cp_y: i32 = y;
        while (y > -1) {
            if (self.row_is_full(cp_y)) {
                while (self.row_is_full(cp_y)) {
                    self.rows_this_tick += 1;
                    cp_y -= 1;
                }
                self.copy_rows(cp_y, y);
                cp_y = y;
            }
            y -= 1;
            cp_y -= 1;
        }
    }

    pub fn get_active(self: Game, x: i32, y: i32) bool {
        if (x < 0) {
            return true;
        }
        if (y < 0) {
            return false;
        }
        const index: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(grid_width)) + @as(usize, @intCast(x));
        if (index >= self.grid.len) {
            return true;
        }

        return self.grid[index].active;
    }

    pub fn get_grid_color(self: Game, x: i32, y: i32) raylib.Color {
        if (x < 0) {
            return raylib.LIGHTGRAY;
        }
        if (y < 0) {
            return raylib.WHITE;
        }
        const index: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(grid_width)) + @as(usize, @intCast(x));
        if (index >= self.grid.len) {
            return raylib.LIGHTGRAY;
        }

        return self.grid[index].color;
    }

    pub fn set_active_state(self: *Game, x: i32, y: i32, state: bool) void {
        if (x < 0 or y < 0) {
            return;
        }
        const index: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(grid_width)) + @as(usize, @intCast(x));
        if (index >= self.grid.len) {
            return;
        }
        self.grid[index].active = state;
    }

    pub fn set_grid_color(self: *Game, x: i32, y: i32, color: raylib.Color) void {
        if (x < 0 or y < 0) {
            return;
        }
        const index: usize = @as(usize, @intCast(y)) * @as(usize, @intCast(grid_width)) + @as(usize, @intCast(x));
        if (index >= self.grid.len) {
            return;
        }
        self.grid[index].color = color;
    }

    pub fn reset(self: *Game) void {
        self.piece_count = 0;
        for (&self.grid) |*item| {
            item.* = Square{ .color = raylib.WHITE, .active = false };
        }
    }

    pub fn piece_reset(self: *Game) void {
        self.piece_count += 1;
        self.y = 0;
        self.x = 4;
        self.t = self.next_type;
        self.next_type = random_type(&self.rng);
        self.r = Rotation.A;
        self.square = Game.get_squares(self.t, self.r);
        if (self.check_collision(self.square)) {
            self.state = State.GameOver;
            self.freeze_input = 60;
        }
    }

    fn piece_shade(self: *Game) raylib.Color {
        return switch (self.t) {
            Type.Cube => rgb(241, 211, 90),
            Type.Long => rgb(83, 179, 219),
            Type.L => rgb(92, 205, 162),
            Type.J => rgb(231, 111, 124),
            Type.T => rgb(195, 58, 47),
            Type.S => rgb(96, 150, 71),
            Type.Z => rgb(233, 154, 56),
        };
    }

    fn piece_ghost(self: *Game) raylib.Color {
        return switch (self.t) {
            Type.Cube => rgba(241, 211, 90, 175),
            Type.Long => rgba(83, 179, 219, 175),
            Type.L => rgba(92, 205, 162, 175),
            Type.J => rgba(231, 111, 124, 175),
            Type.T => rgba(195, 58, 47, 175),
            Type.S => rgba(96, 150, 71, 175),
            Type.Z => rgba(233, 154, 56, 175),
        };
    }

    pub fn draw(self: *Game) void {
        raylib.ClearBackground(BorderColor);
        var y: i32 = 0;
        var upper_left_y: i32 = 0;
        while (y < grid_height) {
            var x: i32 = 0;
            var upper_left_x: i32 = margin;
            while (x < grid_width) {
                if (self.get_active(x, y)) {
                    raylib.DrawRectangle(upper_left_x, upper_left_y, grid_cell_size, grid_cell_size, self.get_grid_color(x, y));
                } else {
                    raylib.DrawRectangle(upper_left_x, upper_left_y, grid_cell_size, grid_cell_size, BackgroundHighlightColor);
                    raylib.DrawRectangle(upper_left_x+1, upper_left_y+1, grid_cell_size-2, grid_cell_size-2, BackgroundColor);
                }

                upper_left_x += grid_cell_size;
                x += 1;
            }
            upper_left_y += grid_cell_size;
            y += 1;
        }

        if (self.state != State.StartScreen) {
            const ghost_square_offset = self.get_ghost_square_offset();
            for (self.square) |pos| {
                raylib.DrawRectangle((self.x + pos.x) * grid_cell_size + margin, (self.y + ghost_square_offset + pos.y) * grid_cell_size, grid_cell_size, grid_cell_size, self.piece_ghost());
                raylib.DrawRectangle((self.x + pos.x) * grid_cell_size + margin, (self.y + pos.y) * grid_cell_size, grid_cell_size, grid_cell_size, piece_color(self.t));
            }
        }

        const right_bar = margin + (10 * grid_cell_size) + margin;
        var draw_height = margin;
        raylib.DrawText("Score:", right_bar, draw_height, 20, raylib.LIGHTGRAY);
        draw_height += 20;
        var score_text_buf = [_]u8{0} ** 21;
        const score_text = std.fmt.bufPrintZ(score_text_buf[0..], "{}", .{self.score}) catch unreachable;
        raylib.DrawText(score_text, right_bar, draw_height, 20, raylib.LIGHTGRAY);
        draw_height += 20;

        draw_height += margin;
        raylib.DrawRectangle(right_bar, draw_height, piece_preview_width, piece_preview_width, BackgroundColor);
        if (self.state != State.StartScreen) {
            const next_squares = switch (self.next_type) {
                Type.Long => Game.get_squares(self.next_type, Rotation.B),
                else => Game.get_squares(self.next_type, Rotation.A),
            };
            var max_x: i32 = 0;
            var min_x: i32 = 0;
            var max_y: i32 = 0;
            var min_y: i32 = 0;
            for (next_squares) |pos| {
                min_x = @min(min_x, pos.x);
                max_x = @max(max_x, pos.x);
                min_y = @min(min_y, pos.y);
                max_y = @max(max_y, pos.y);
            }
            const height = (max_y - min_y + 1) * grid_cell_size;
            const width = (max_x - min_x + 1) * grid_cell_size;

            const x_offset = min_x * -1;
            const y_offset = min_y * -1;
            const x_pixel_offset = @divFloor(piece_preview_width - width, 2);
            const y_pixel_offset = @divFloor(piece_preview_width - height, 2);
            for (next_squares) |pos| {
                raylib.DrawRectangle(right_bar + x_pixel_offset + (pos.x + x_offset) * grid_cell_size, draw_height + y_pixel_offset + (pos.y + y_offset) * grid_cell_size, grid_cell_size, grid_cell_size, piece_color(self.next_type));
            }
        }
        draw_height += piece_preview_width;

        if (self.state == State.Pause or self.state == State.GameOver or self.state == State.StartScreen) {
            raylib.DrawRectangle(0, (screen_height/2)-70, screen_width, 110, rgba(3, 2, 1, 100));
        }

        if (self.state == State.Pause) {
            raylib.DrawText("PAUSED", 75, screen_height/2 - 50, 50, raylib.WHITE);
            raylib.DrawText("Press ESCAPE to unpause", 45, screen_height/2, 20, raylib.LIGHTGRAY);
        }

        if (self.state == State.GameOver) {
            raylib.DrawText("GAME OVER", 45, screen_height/2 - 50, 42, raylib.WHITE);
            raylib.DrawText("Press any key to continue", 41, screen_height/2, 20, raylib.LIGHTGRAY);
        }

        if (self.state == State.StartScreen) {
            raylib.DrawText("TETRIS", 75, screen_height/2 - 50, 50, raylib.WHITE);
            raylib.DrawText("Press any key to continue", 41, screen_height / 2, 20, raylib.LIGHTGRAY);
        }
    }

    pub fn get_squares(t: Type, r: Rotation) [4]Pos {
        return switch (t) {
            Type.Cube => [_]Pos{
                p(0, 0), p(1, 0), p(0, 1), p(1, 1),
            },
            Type.Long => switch (r) {
                Rotation.A, Rotation.C => [_]Pos{
                    p(-1, 0), p(0, 0), p(1, 0), p(2, 0),
                },
                Rotation.B, Rotation.D => [_]Pos{
                    p(0, -1), p(0, 0), p(0, 1), p(0, 2),
                },
            },
            Type.Z => switch (r) {
                Rotation.A, Rotation.C => [_]Pos{
                    p(-1, 0), p(0, 0), p(0, 1), p(1, 1),
                },
                Rotation.B, Rotation.D => [_]Pos{
                    p(0, -1), p(-1, 0), p(0, 0), p(-1, 1),
                },
            },
            Type.S => switch (r) {
                Rotation.A, Rotation.C => [_]Pos{
                    p(0, 0), p(1, 0), p(-1, 1), p(0, 1),
                },
                Rotation.B, Rotation.D => [_]Pos {
                    p(0, -1), p(0, 0), p(1, 0), p(1, 1),
                },
            },
            Type.T => switch (r) {
                Rotation.A => [_]Pos{
                    p(0, -1), p(-1, 0), p(0, 0), p(1, 0),
                },
                Rotation.B => [_]Pos{
                    p(0, -1), p(0, 0), p(1, 0), p(0, 1),
                },
                Rotation.C => [_]Pos{
                    p(-1, 0), p(0, 0), p(1, 0), p(0, 1),
                },
                Rotation.D => [_]Pos{
                    p(0, -1), p(-1, 0), p(0, 0), p(0, 1),
                },
            },
            Type.L => switch (r) {
                Rotation.A => [_]Pos{
                    p(0, -1), p(0, 0), p(0, 1), p(1, 1),
                },
                Rotation.B => [_]Pos{
                    p(-1, 0), p(0, 0), p(1, 0), p(-1, 1),
                },
                Rotation.C => [_]Pos{
                    p(-1, -1), p(0, -1), p(0, 0), p(0, 1),
                },
                Rotation.D => [_]Pos{
                    p(1, -1), p(-1, 0), p(0, 0), p(1, 0),
                },
            },
            Type.J => switch (r) {
                Rotation.A => [_]Pos{
                    p(0, -1), p(0, 0), p(-1, 1), p(0, 1),
                },
                Rotation.B => [_]Pos{
                    p(-1, -1), p(-1, 0), p(0, 0), p(1, 0),
                },
                Rotation.C=> [_]Pos{
                    p(0, -1), p(1, -1), p(0, 0), p(0, 1),
                },
                Rotation.D => [_]Pos{
                    p(-1, 0), p(0, 0), p(1, 0), p(1, 1),
                },
            },
        };
    }

    pub fn get_ghost_square_offset(self: *Game) i32 {
        var offset: i32 = 0;
        while (true) {
            if (self.check_collision_offset(0, offset, self.square)) {
                break;
            }
            offset += 1;
        }
        return offset - 1;
    } 

    pub fn rotate(self: *Game) void {
        const r = switch (self.r) {
            Rotation.A => Rotation.B,
            Rotation.B => Rotation.C,
            Rotation.C => Rotation.D,
            Rotation.D => Rotation.A,
        };
        const squares = Game.get_squares(self.t, r);
        if (self.check_collision(squares)) {
            const x_offsets = [_]i32{ 1, -1, 2, -2 };
            for (x_offsets) |x_offset| {
                if (!self.check_collision_offset(x_offset, 0, squares)) {
                    self.x += x_offset;
                    self.square = squares;
                    self.r = r;
                    return;
                }
            }
        } else {
            self.square = squares;
            self.r = r;
        }
    }

    pub fn check_collision(self: *Game, squares: [4]Pos) bool {
        for (squares) |pos| {
            const x = self.x + pos.x;
            const y = self.y + pos.y;
            if ((x >= grid_width) or (x < 0) or (y >= grid_height) or self.get_active(x, y)) {
                return true;
            }
        }

        return false;
    }

    fn check_collision_offset(self: *Game, offest_x: i32, offset_y: i32, squares: [4]Pos) bool {
        for (squares) |pos| {
            const x = self.x + pos.x + offest_x;
            const y = self.y + pos.y + offset_y;
            if ((x >= grid_width) or (x < 0) or (y >= grid_height) or self.get_active(x, y)) {
                return true;
            }
        }

        return false;
    }

    pub fn move_right(self: *Game) void {
        const can_move = blk: {
            for (self.square) |pos| {
                const x = self.x + pos.x + 1;
                const y = self.y + pos.y;
                if ((x >= grid_width) or self.get_active(x, y)) {
                    break :blk false;
                }
            }
            break :blk true;
        };
        if (can_move) {
            self.x += 1;
        }
    }

    pub fn move_left(self: *Game) void {
        const can_move = blk: {
            for (self.square) |pos| {
                const x = self.x + pos.x - 1;
                const y = self.y + pos.y;
                if ((x < 0) or self.get_active(x, y)) {
                    break :blk false;
                }
            }
            break :blk true;
        };
        if (can_move) {
            self.x -= 1;
        }
    }

    fn can_move_down(self: *Game) bool {
        for (self.square) |pos| {
            const x = self.x + pos.x;
            const y = self.y + pos.y + 1;
            if ((y >= grid_height) or self.get_active(x, y)) {
                return false;
            }
        }

        return true;
    }

    pub fn drop(self: *Game) bool {
        var moved = false;
        while (self.can_move_down()) {
            self.y += 1;
            moved = true;
        }
        if (moved) {
            return true;
        } else {
            for (self.squares) |pos| {
                self.set_active_state(self.x + pos.x, self.y + pos.y, true);
                self.set_grid_color(self.x + pos.x, self.y + pos.y, self.piece_shade());
            }
            self.piece_reset();
            return false;
        }
    }

    pub fn move_down(self: *Game) bool {
        if (self.can_move_down()) {
            self.y += 1;
            return true;
        } else {
            for (self.square) |pos| {
                self.set_active_state(self.x + pos.x, self.y + pos.y, true);
                self.set_grid_color(self.x + pos.x, self.y + pos.y, self.piece_shade());
            }
            self.piece_reset();
            return false;
        }
    }
};
 
pub fn main() !void {
    var game = Game.init();
    raylib.InitWindow(screen_width, screen_height, "Tetris");
    defer raylib.CloseWindow();

    raylib.SetExitKey(raylib.KEY_F4);

    raylib.SetTargetFPS(60);

    raylib.SetTextureFilter(raylib.GetFontDefault().texture, raylib.TEXTURE_FILTER_POINT);

    while (!raylib.WindowShouldClose()) {
        game.update();
        raylib.BeginDrawing();
        game.draw();
        raylib.EndDrawing();
    }
}