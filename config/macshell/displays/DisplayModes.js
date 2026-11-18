.pragma library

function isBuiltIn(monitor) {
    return /^(eDP|LVDS|DSI)-/i.test(monitor.name);
}

function displayName(monitor, fallback) {
    if (!monitor) return fallback;
    const model = monitor.model || "";
    const make = monitor.make || "";
    let name = [make, model].filter(Boolean).join(" ") || monitor.description || "";
    // Descriptions can include a connector suffix or the EDID serial.
    if (name.endsWith(" (" + monitor.name + ")"))
        name = name.slice(0, -monitor.name.length - 3);
    if (monitor.serial && name.endsWith(" " + monitor.serial))
        name = name.slice(0, -monitor.serial.length - 1);
    name = name.replace(/(?:^|\s+)(?:0x[\da-f]+|\(0x[\da-f]+\))(?=\s|$)/gi, " ")
        .replace(/\s+/g, " ").trim();
    return name && name !== monitor.name ? name : fallback;
}

function modesOf(monitor) {
    if (!monitor) return [];
    const modes = new Map();
    for (const value of monitor.availableModes || []) {
        const match = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(value);
        if (match)
            modes.set(match[0].slice(0, -2), { width: Number(match[1]), height: Number(match[2]), hz: Number(match[3]) });
    }
    if (!Array.from(modes.values()).some(mode => matchesMode(monitor, mode)))
        modes.set("current", { width: monitor.width, height: monitor.height, hz: monitor.refreshRate });
    return Array.from(modes.values()).sort((a, b) => b.width * b.height - a.width * a.height || b.hz - a.hz);
}

function matchesMode(monitor, mode) {
    return monitor.width === mode.width && monitor.height === mode.height
        && Math.abs(monitor.refreshRate - (mode.hz ?? mode.refreshRate)) < 0.01;
}

function resolution(mode) {
    return mode.width + " × " + mode.height;
}

function logicalSize(mode, scale, transform) {
    const rotated = transform % 2 === 1;
    return {
        width: Math.round((rotated ? mode.height : mode.width) / scale),
        height: Math.round((rotated ? mode.width : mode.height) / scale)
    };
}

function validScale(mode, scale) {
    return scale > 0 && Number.isInteger(mode.width / scale) && Number.isInteger(mode.height / scale);
}

function availableScales(mode) {
    const scales = [];
    // Hyprland searches in 1/120 increments and requires whole logical pixels on both axes.
    for (let step = 120; step <= 480; ++step) {
        if (validScale(mode, step / 120))
            scales.push(step / 120);
    }
    return scales;
}

function closest(scales, target) {
    return scales.reduce((best, scale) =>
        Math.abs(scale - target) < Math.abs(best - target) ? scale : best);
}

function presets(monitor) {
    if (!monitor) return [];
    const pool = availableScales(monitor);
    const result = [monitor.scale];
    const baseline = monitor.width >= 2560 ? 2 : 1;
    for (const multiplier of [1, 1.25, 0.8, 1.5, 0.6]) {
        if (result.length >= 5 || !pool.length) break;
        const choice = closest(pool, baseline * multiplier);
        if (!result.some(scale => Math.abs(scale - choice) < 0.0001))
            result.push(choice);
        pool.splice(pool.indexOf(choice), 1);
    }
    return result.sort((a, b) => b - a);
}

function overlaps(aStart, aSize, bStart, bSize) {
    return aStart < bStart + bSize && bStart < aStart + aSize;
}

function followEdge(displays, changed, axis, size, crossAxis, crossSize, delta) {
    if (delta === 0) return;
    // Carry the size change through screens touching the same edge, preserving their alignment.
    const followers = new Set([changed]);
    for (const display of followers) {
        for (const next of displays) {
            if (display[axis] + display[size] === next[axis]
                && overlaps(display[crossAxis], display[crossSize], next[crossAxis], next[crossSize]))
                followers.add(next);
        }
    }
    followers.delete(changed);
    for (const display of followers) display[axis] += delta;
}

function layoutBoxes(monitors) {
    return monitors.filter(m => !m.mirrorOf || m.mirrorOf === "none").map(m => Object.assign(
        { name: m.name, monitor: m, x: m.x, y: m.y }, logicalSize(m, m.scale, m.transform)
    ));
}

function intersects(a, b) {
    return overlaps(a.x, a.width, b.x, b.width) && overlaps(a.y, a.height, b.y, b.height);
}

function validLayout(boxes) {
    return boxes.every((box, index) => boxes.slice(index + 1).every(other => !intersects(box, other)));
}

function bounds(boxes) {
    return {
        left: Math.min(...boxes.map(box => box.x)),
        top: Math.min(...boxes.map(box => box.y)),
        right: Math.max(...boxes.map(box => box.x + box.width)),
        bottom: Math.max(...boxes.map(box => box.y + box.height))
    };
}

function snappedPosition(boxes, moving, x, y, threshold) {
    const others = boxes.filter(box => box.name !== moving.name);
    let best = null;
    let shortest = Infinity;
    // Consider each neighbor's four edges and keep a shared segment for cursor movement.
    for (const other of others) {
        const vertical = snapAlong(y, moving.height, other.y, other.height, threshold);
        const horizontal = snapAlong(x, moving.width, other.x, other.width, threshold);
        for (const [candidateX, candidateY] of [
            [other.x - moving.width, vertical], [other.x + other.width, vertical],
            [horizontal, other.y - moving.height], [horizontal, other.y + other.height]
        ]) {
            const candidate = Object.assign({}, moving, { x: candidateX, y: candidateY });
            const distance = Math.hypot(candidate.x - x, candidate.y - y);
            if (distance >= shortest || others.some(box => intersects(candidate, box))) continue;
            shortest = distance;
            best = candidate;
        }
    }
    return best;
}

function snapAlong(value, length, start, neighborLength, threshold) {
    const alignments = [start, start + neighborLength - length, start + (neighborLength - length) / 2];
    const aligned = closest(alignments, value);
    if (Math.abs(aligned - value) <= threshold) return Math.round(aligned);
    const shared = Math.min(96, length, neighborLength);
    return Math.round(Math.max(start - length + shared, Math.min(start + neighborLength - shared, value)));
}

function layoutKey(boxes) {
    return JSON.stringify(boxes.map(box => box.name).sort());
}

function plan(monitors, monitor, mode, scale) {
    const displays = layoutBoxes(monitors);
    const changed = displays.find(d => d.name === monitor.name);
    if (!changed) return [];
    const size = logicalSize(mode, scale, monitor.transform);
    followEdge(displays, changed, "x", "width", "y", "height", size.width - changed.width);
    followEdge(displays, changed, "y", "height", "x", "width", size.height - changed.height);
    Object.assign(changed, size);
    if (!validLayout(displays)) return [];
    return displays.filter(d => d === changed || d.x !== d.monitor.x || d.y !== d.monitor.y).map(d => Object.assign({}, d.monitor, {
        x: d.x, y: d.y,
        width: d === changed ? mode.width : d.monitor.width,
        height: d === changed ? mode.height : d.monitor.height,
        refreshRate: d === changed ? mode.hz ?? mode.refreshRate : d.monitor.refreshRate,
        scale: d === changed ? scale : d.monitor.scale
    }));
}
