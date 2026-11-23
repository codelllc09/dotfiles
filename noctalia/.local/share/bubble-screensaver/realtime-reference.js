imports.gi.versions.Gtk = '3.0';
const {Gtk, Gdk, GtkLayerShell: Layer, GLib} = imports.gi;
const C = imports.cairo;
const tau = 2 * Math.PI;
const random = (a, b) => a + Math.random() * (b - a);

function hue(angle) {
    return [0, -tau / 3, tau / 3].map(offset => 0.5 + 0.49 * Math.cos(angle + offset));
}

function sprite(r, tint) {
    const side = 2 * r + 6;
    const surface = new C.ImageSurface(C.Format.ARGB32, side, side);
    const c = new C.Context(surface);
    c.translate(side / 2, side / 2);
    c.scale(r, r);
    c.arc(0, 0, 0.98, 0, tau);
    c.clip();
    const film = new C.RadialGradient(0, 0, 0, 0, 0, 1);
    for (const [at, rgb, alpha] of [
        [0, hue(tint), 0.035], [0.64, hue(tint + 1), 0.07],
        [0.83, hue(tint + 0.3), 0.22], [0.92, hue(tint - 1), 0.48],
        [0.954, [0.92, 0.98, 1], 0.73], [0.98, [0.08, 0.16, 0.29], 0.63]
    ]) film.addColorStopRGBA(at, ...rgb, alpha);
    c.setSource(film);
    c.paint();
    for (let i = 0; i < 9; i++) {
        const a = tint + i * tau / 9;
        const x = 0.96 * Math.cos(a), y = 0.96 * Math.sin(a);
        const reflection = new C.RadialGradient(x, y, 0, x, y, 0.62);
        const color = hue(tint + i * 0.86);
        reflection.addColorStopRGBA(0, ...color, 0.7);
        reflection.addColorStopRGBA(0.5, ...color, 0.21);
        reflection.addColorStopRGBA(1, ...color, 0);
        c.setSource(reflection);
        c.paint();
    }
    c.save();
    c.translate(-0.35, -0.57);
    c.rotate(-0.53);
    c.scale(0.44, 0.135);
    const sheen = new C.RadialGradient(0, 0, 0, 0, 0, 1);
    sheen.addColorStopRGBA(0, 1, 1, 1, 0.98);
    sheen.addColorStopRGBA(0.55, 1, 1, 1, 0.60);
    sheen.addColorStopRGBA(1, 1, 1, 1, 0);
    c.setSource(sheen);
    c.paint();
    c.restore();
    c.setLineWidth(0.018);
    c.arc(0, 0, 0.891, 3.63, 4.53);
    c.setSourceRGBA(1, 1, 1, 0.86);
    c.stroke();
    c.arc(0, 0, 0.913, 0.68, 1.31);
    c.setSourceRGBA(1, 1, 1, 0.48);
    c.stroke();
    c.$dispose();
    return surface;
}

Gtk.init(null);
if (!Layer.is_supported()) throw new Error('Wayland layer shell unavailable');
const win = new Gtk.Window({decorated: false, app_paintable: true});
const screen = win.get_screen();
win.set_visual(screen.get_rgba_visual());
Layer.init_for_window(win);
Layer.set_namespace(win, 'niri-black-bubbles-preview');
Layer.set_layer(win, Layer.Layer.OVERLAY);
Layer.set_exclusive_zone(win, -1);
Layer.set_keyboard_mode(win, Layer.KeyboardMode.NONE);
const display = Gdk.Display.get_default();
for (let i = 0; i < display.get_n_monitors(); i++) {
    if (screen.get_monitor_plug_name(i) === ARGV[0]) {
        Layer.set_monitor(win, display.get_monitor(i));
        break;
    }
}
for (const edge of [Layer.Edge.TOP, Layer.Edge.BOTTOM, Layer.Edge.LEFT, Layer.Edge.RIGHT])
    Layer.set_anchor(win, edge, true);
win.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.TOUCH_MASK);
win.connect('button-press-event', () => {Gtk.main_quit(); return true;});
win.connect('touch-event', () => {Gtk.main_quit(); return true;});

const bubbles = [];
let lastTime = 0;
let timeRunning = 0;
let verifiedMotion = false;

function setCourse(b, angle, scale) {
    b.angle = angle;
    b.speed = scale * random(0.095, 0.165);
    b.turn = 0;
    b.targetTurn = random(-0.35, 0.35);
    b.nextTurn = random(0.8, 2.8);
}

function enterFromEdge(b, width, height) {
    const edge = Math.floor(random(0, 4));
    const inward = [0, Math.PI, Math.PI/2, -Math.PI/2];
    const inset = b.r * 0.7;
    if (edge < 2) {
        b.x = edge === 0 ? -inset : width + inset;
        b.y = random(b.r, height - b.r);
    } else {
        b.x = random(b.r, width - b.r);
        b.y = edge === 2 ? -inset : height + inset;
    }
    setCourse(b, inward[edge] + random(-0.63, 0.63), Math.min(width, height));
    b.nextTurn += 1.2;
}

function seed(width, height) {
    const scale = Math.min(width, height);
    for (let i = 0; i < 11; i++) {
        const r = Math.round(random(0.031, 0.078) * scale);
        const b = {r, surface: sprite(r, random(0, tau))};
        if (i < 8) {
            for (let attempt = 0; attempt < 18; attempt++) {
                b.x = random(r, width-r);
                b.y = random(r, height-r);
                if (bubbles.every(q => Math.hypot(b.x-q.x, b.y-q.y) > 0.83*(q.r+r))) break;
            }
            setCourse(b, random(0,tau), scale);
        } else {
            enterFromEdge(b, width, height);
        }
        b.startX = b.x;
        b.startY = b.y;
        bubbles.push(b);
    }
}

function advance(b, dt, width, height) {
    b.nextTurn -= dt;
    if (b.nextTurn <= 0) {
        b.nextTurn = random(0.9, 3.2);
        b.targetTurn = random(-0.50, 0.50);
    }
    b.turn += (b.targetTurn - b.turn) * (1 - Math.exp(-2 * dt));
    b.angle += b.turn * dt;
    b.x += Math.cos(b.angle) * b.speed * dt;
    b.y += Math.sin(b.angle) * b.speed * dt;
    if (b.x < -b.r-2 || b.x > width+b.r+2 || b.y < -b.r-2 || b.y > height+b.r+2)
        enterFromEdge(b, width, height);
}

win.connect('draw', (w, c) => {
    const width = w.get_allocated_width(), height = w.get_allocated_height();
    c.setOperator(C.Operator.SOURCE);
    c.setSourceRGB(0, 0, 0);
    c.paint();
    c.setOperator(C.Operator.OVER);
    if (width < 20 || height < 20) return true;
    if (!bubbles.length) {
        seed(width, height);
        print('Black bubbles frame ' + width + 'x' + height);
    }
    const now = GLib.get_monotonic_time();
    const dt = lastTime ? Math.min(0.12, (now-lastTime) / 1e6) : 0;
    lastTime = now;
    timeRunning += dt;
    for (const b of bubbles) {
        advance(b, dt, width, height);
        const x = Math.round(b.x - b.r - 3), y = Math.round(b.y - b.r - 3), side = 2*b.r + 6;
        c.setSourceSurface(b.surface, x, y);
        c.rectangle(x, y, side, side);
        c.fill();
    }
    if (!verifiedMotion && timeRunning >= 2.0) {
        const travelled = bubbles.map(b => Math.hypot(b.x-b.startX, b.y-b.startY)).sort((a,b)=>a-b);
        print('Median bubble displacement at 2s: ' + Math.round(travelled[Math.floor(travelled.length/2)]) + ' logical pixels');
        verifiedMotion = true;
    }
    return true;
});
win.show_all();
GLib.timeout_add(GLib.PRIORITY_DEFAULT, 40, () => {win.queue_draw(); return GLib.SOURCE_CONTINUE;});
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 120, () => {Gtk.main_quit(); return GLib.SOURCE_REMOVE;});
Gtk.main();
