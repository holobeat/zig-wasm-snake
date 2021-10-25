const std = @import("std");
const fifo = std.fifo;

extern fn consoleLog(msg_ptr: [*]const u8, msg_len: usize) void;
extern fn abort() void;
extern fn resetDelta() void;
extern fn paintField(index: i32, r: i32, g: i32, b: i32) void;
extern fn drawGameArena(arenaSideSize: i32) void;
extern fn showScore(score: i32) void;
extern fn showPage(page: i32) void;
extern fn showMessage(msg_ptr: [*]const u8, msg_len: usize) void;
extern fn hideMessage() void;
extern fn getRandomInt(max: i32) i32;

const introPage: i32 = 0;
const gamePage: i32 = 1;
const winningScore: i32 = 50;

const Point = struct {
    x: i32,
    y: i32,
};

const Direction = enum {
    none,
    up,
    down,
    left,
    right,
};

const CollisionResult = enum {
    noCollision,
    hitTheWall,
    bitItself,
    ateFood,
    snakeIsFull,
};

const GameStatus = enum {
    notStarted,
    playing,
    paused,
    aborted,
    gameOver,
};

const FifoType = fifo.LinearFifo(Direction, fifo.LinearFifoBufferType{ .Static = 2 });
var directionBuffer: FifoType = FifoType.init();

const snakeMaxLength: u8 = 100;
const Snake = struct {
    buffer: [snakeMaxLength]i32 = undefined,
    length: u8 = 4,
    lastTailIndex: i32 = undefined,
    headPoint: Point = undefined,

    pub fn move(self: *Snake, direction: Direction, grow: bool) void {
        var p: Point = nextCoord(self.headPoint, direction);
        var newHeadIndex = coordToIndex(p);
        var i = if (grow) self.length else self.length - 1;
        self.lastTailIndex = self.buffer[i];
        while (i > 0) : (i -= 1) {
            self.buffer[i] = self.buffer[i - 1];
        }
        self.buffer[0] = newHeadIndex;
        if (grow) {
            self.length += 1;
        }
        self.headPoint = p;
    }

    pub fn init(self: *Snake, p: Point, direction: Direction, length: u8) void {
        self.headPoint = p;
        var i: u8 = 0;
        while (i < length) : (i += 1) {
            self.buffer[i] = coordToIndex(switch (direction) {
                Direction.none => unreachable,
                Direction.up => .{ .x = p.x, .y = p.y + i },
                Direction.down => .{ .x = p.x, .y = p.y - i },
                Direction.left => .{ .x = p.x + i, .y = p.y },
                Direction.right => .{ .x = p.x - i, .y = p.y },
            });
        }
        self.length = length;
        self.lastTailIndex = self.buffer[length - 1];
    }
};

const foodMaxBatch: u8 = 5;
const Food = struct {
    buffer: [foodMaxBatch]i32 = [1]i32{-1} ** foodMaxBatch,

    pub fn fill(self: *Food, max: i32, except: []i32) void {
        var i: i32 = undefined;
        for (self.buffer) |*u| {
            if (u.* == -1) {
                while (true) {
                    i = getRandomInt(max);
                    // avoid placing food on position of the snake
                    if (!std.mem.containsAtLeast(i32, except, 1, ([1]i32{i})[0..])) {
                        u.* = i;
                        break;
                    }
                }
            }
        }
    }

    pub fn remove(self: *Food, value: i32) void {
        for (self.buffer) |*u| {
            if (u.* == value) {
                u.* = -1;
                break;
            }
        }
    }

    pub fn remaining(self: *Food) usize {
        return @as(usize, foodMaxBatch) - std.mem.count(i32, self.buffer[0..], ([1]i32{-1})[0..]);
    }
};

const Model = struct {
    activePage: i32 = introPage,
    gameStatus: GameStatus,
    arenaSideSize: i32,
    direction: Direction,
    snake: Snake,
    food: Food,
    speed: i32, // delta
    score: i8,
    fn init() Model {
        return .{
            .gameStatus = GameStatus.notStarted,
            .arenaSideSize = 30,
            .direction = Direction.right,
            .snake = Snake{},
            .food = Food{},
            .speed = 250, // delta
            .score = 0,
        };
    }
};

var model: Model = undefined;

export fn init(arenaSideSize: i32) void {
    model = Model.init();
    model.arenaSideSize = arenaSideSize;
    showPage(introPage);
}

fn paintSnake() void {
    var i: u8 = 0;
    while (i < model.snake.length) : (i += 1) {
        paintField(model.snake.buffer[i], 0, 200, 0);
    }
    if (model.gameStatus == GameStatus.playing) {
        // remove end of tail
        paintField(model.snake.lastTailIndex, 61, 35, 14);
    }
}

fn paintFood() void {
    for (model.food.buffer) |i| {
        if (i != -1) paintField(i, 200, 0, 0);
    }
}

fn intToStr(buff: []u8, value: anytype) []const u8 {
    _ = std.fmt.bufPrint(buff, "{}", .{value}) catch null;
    return std.mem.trimRight(u8, buff[0..], ([1]u8{0})[0..]);
}

fn nextCoord(p: Point, direction: Direction) Point {
    switch (direction) {
        Direction.none => unreachable,
        Direction.up => return .{ .x = p.x, .y = p.y - 1 },
        Direction.down => return .{ .x = p.x, .y = p.y + 1 },
        Direction.left => return .{ .x = p.x - 1, .y = p.y },
        Direction.right => return .{ .x = p.x + 1, .y = p.y },
    }
}

fn coordToIndex(p: Point) i32 {
    return p.x - 1 + ((p.y - 1) * model.arenaSideSize);
}

fn collisionTest() CollisionResult {
    const p = nextCoord(model.snake.headPoint, model.direction);
    const headIndex = coordToIndex(p);
    // check for out of bounds / hitting the wall
    if (p.x < 1 or p.x > model.arenaSideSize or p.y < 1 or p.y > model.arenaSideSize) {
        return .hitTheWall;
    }
    // food
    for (model.food.buffer) |i| {
        if (headIndex == i) return .ateFood;
    }
    // ate itself
    if (std.mem.containsAtLeast(i32, model.snake.buffer[0..model.snake.length], 1, ([1]i32{headIndex})[0..])) {
        return .bitItself;
    }
    // snake is full
    if (model.score == winningScore) {
        return .snakeIsFull;
    }
    return .noCollision;
}

fn speedUp() void {
    if (model.speed > 250) {
        model.speed -= 50;
    } else if (model.speed > 150) {
        model.speed -= 25;
    } else if (model.speed > 70) {
        model.speed -= 10;
    } else if (model.speed > 40) {
        model.speed -= 5;
    } else if (model.speed > 20) {
        model.speed -= 2;
    }
}

fn isDirectionKey(key: u8) bool {
    return switch (key) {
        'w', 's', 'a', 'd' => true,
        else => false,
    };
}

fn evalKeyIntroPage(key: u8) void {
    switch (key) {
        ' ' => startGame(),
        else => {},
    }
}

fn evalKeyGamePage(key: u8) void {
    if (model.gameStatus == .gameOver and key == ' ') {
        hideMessage();
        init(model.arenaSideSize);
        return;
    }
    if (isDirectionKey(key)) {
        const d = model.direction; // current direction
        // ignore opposite direction key
        const direction: Direction = switch (key) {
            'w' => if (d == Direction.down) Direction.none else Direction.up,
            's' => if (d == Direction.up) Direction.none else Direction.down,
            'a' => if (d == Direction.right) Direction.none else Direction.left,
            'd' => if (d == Direction.left) Direction.none else Direction.right,
            else => unreachable,
        };
        if (direction == Direction.none) return;
        if (directionBuffer.readableLength() < 2) {
            directionBuffer.writeItem(direction) catch unreachable;
        }
    } else switch (key) {
        // pause
        'p' => model.gameStatus = if (model.gameStatus == .playing) .paused else .playing,
        // spacebar, continue/new game after game over
        ' ' => startGame(),
        else => {},
    }
}

fn startGame() void {
    const size = model.arenaSideSize;
    showPage(gamePage);
    model.activePage = gamePage;
    drawGameArena(size);
    model.snake.init(.{ .x = 6, .y = 15 }, model.direction, 4);
    model.food.fill(size * size - 1, model.snake.buffer[0..model.snake.length]);
    paintFood();
    paintSnake();
    showScore(model.score);
    model.gameStatus = GameStatus.playing;
}

export fn onKeyDown(key: u8) void {
    switch (model.activePage) {
        introPage => evalKeyIntroPage(key),
        gamePage => evalKeyGamePage(key),
        else => unreachable,
    }
}

export fn update(delta: i32) void {
    if (delta >= model.speed) {
        if (model.gameStatus == GameStatus.playing) {
            // logMessage("playing");
            if (directionBuffer.readableLength() > 0) {
                model.direction = directionBuffer.readItem().?;
            }
            switch (collisionTest()) {
                .noCollision => {
                    model.snake.move(model.direction, false);
                    paintSnake();
                },
                .hitTheWall => {
                    model.gameStatus = GameStatus.gameOver;
                    showMessage_("YOU HIT THE WALL !<br>PRESS SPACE TO RESTART THE GAME");
                },
                .ateFood => {
                    model.score += 1;
                    showScore(model.score);
                    model.snake.move(model.direction, true);
                    model.food.remove(coordToIndex(model.snake.headPoint));
                    if (model.food.remaining() == 1) {
                        model.food.fill(
                            model.arenaSideSize * model.arenaSideSize - 1,
                            model.snake.buffer[0..model.snake.length],
                        );
                    }
                    speedUp();
                    paintSnake();
                    paintFood();
                },
                .bitItself => {
                    model.gameStatus = GameStatus.gameOver;
                    showMessage_("YOU BIT YOURSELF !<br>PRESS SPACE TO RESTART THE GAME");
                },
                .snakeIsFull => {
                    model.gameStatus = GameStatus.gameOver;
                    showMessage_("CONGRATULATIONS ! YOU WON, SNAKE IS FULL !<br>PRESS SPACE TO RESTART THE GAME");
                },
            }
        }
        // reset direction buffer after game is over
        if (model.gameStatus == .gameOver) {
            directionBuffer.discard(directionBuffer.readableLength());
        }
        resetDelta();
    }
}

fn showMessage_(msg: []const u8) void {
    showMessage(msg.ptr, msg.len);
}

fn logMessage(msg: []const u8) void {
    consoleLog(msg.ptr, msg.len);
}
