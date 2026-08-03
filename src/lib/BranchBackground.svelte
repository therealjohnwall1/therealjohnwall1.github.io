<script lang="ts">
    import { onMount } from "svelte";

    // Bracketed OL-system, example (e) from Prusinkiewicz & Lindenmayer,
    // "The Algorithmic Beauty of Plants", fig. 1.24:
    //   n = 7, delta = 25.7 deg
    //   axiom: X
    //   X -> F[+X][-X]FX
    //   F -> FF
    const AXIOM = "X";
    const RULES: Record<string, string> = { X: "F[+X][-X]FX", F: "FF" };
    const ITERATIONS = 8;
    const DELTA = (25.7 * Math.PI) / 180;

    // Per-tree nudge, in fractions of the viewport, applied on top of each
    // tree's anchor. x: negative moves left, positive right. y: negative
    // moves UP, positive down. So { x: -0.1, y: 0 } shifts that tree left by
    // a tenth of the screen width. Both default to the same values, which is
    // what a single shared offset used to do; change one to pull the trees
    // apart independently.
    const DELTA_RIGHT = { x: 0.3, y: 0.05 };
    const DELTA_LEFT = { x: 0.3, y: 0.05 };

    // A tree per screen edge, facing each other. `angle` is the direction
    // the trunk grows (0 = right, 90 = down, 180 = left, -90 = up),
    // `anchorX/Y` is where the root sits as a fraction of the viewport,
    // `flipY` reflects the canopy, and `delta` is that tree's own nudge.
    // The flip is what makes the pair read as a mirror across the screen's
    // midline -- rotation alone would make the second tree a point
    // reflection, which reads as lopsided. Drop either entry to go back to
    // a single tree.
    //
    // Laid on its side the tree is 2.02:1 along its growth axis, close to a
    // 16:9 screen, so each one spans the width with nothing cropped.
    const SIDEWAYS = [
        { angle: 180, anchorX: 1, anchorY: 0.5, flipY: 1, delta: DELTA_RIGHT },
        { angle: 0, anchorX: 0, anchorY: 0.5, flipY: -1, delta: DELTA_LEFT },
    ];

    // Portrait: rooted at the bottom and top edges instead. A sideways tree
    // in a portrait window leaves most of the screen bare, and upright the
    // tree's 0.50 aspect happens to match a phone almost exactly. There is
    // no left and right here, so the bottom tree borrows DELTA_RIGHT and the
    // top one DELTA_LEFT.
    const UPRIGHT = [
        { angle: -90, anchorX: 0.5, anchorY: 1, flipY: 1, delta: DELTA_RIGHT },
        { angle: 90, anchorX: 0.5, anchorY: 0, flipY: -1, delta: DELTA_LEFT },
    ];

    // 0 = whole tree on screen, 1 = it covers the viewport in both axes at
    // the cost of running off the edges. Low values keep the tip inside the
    // far edge; raise it to push the canopy past the screen.
    const FILL = 0.5;

    // The trunk is laid directly on the parabola y = k*x^2 rather than
    // approximated by turning, so every center-line vertex sits exactly on
    // the curve. k is set relative to trunk length L as CURVE / L, which
    // keeps the shape identical no matter how ITERATIONS changes L: the tip
    // lands CURVE * L off the axis, leaving at an angle of atan(2 * CURVE).
    // 0 is a straight trunk; negative bows the other way; past ~0.5 the
    // tree curls back on itself and stops spanning a wide screen.
    const CURVE = 0;

    // Vertical drift. This is a CSS transform on the canvas element, not a
    // redraw: the compositor slides the already-rasterized texture on the
    // GPU, so it costs no JS and no canvas work per frame no matter how
    // many segments are on screen. The canvas is grown by SLIDE_PX on each
    // side and offset to match, so sliding never exposes a bare strip at
    // the top or bottom. Set SLIDE_PX to 0 to hold still.
    const SLIDE_PX = 40;
    const SLIDE_MS = 9000;

    const GROW_MS = 3000;

    type Segment = { x1: number; y1: number; x2: number; y2: number; depth: number };

    let canvas: HTMLCanvasElement;

    function expand(): string {
        let word = AXIOM;
        for (let i = 0; i < ITERATIONS; i++) {
            let next = "";
            for (const c of word) next += RULES[c] ?? c;
            word = next;
        }
        return word;
    }

    // Turtle walk. Segments come out in depth-first order, which is what
    // makes the growth read branch by branch: the turtle finishes one limb
    // before backtracking to start its sibling.
    function trace(word: string): Segment[] {
        const segs: Segment[] = [];
        const stack: { x: number; y: number; a: number; depth: number }[] = [];
        let x = 0;
        let y = 0;
        let a = 0; // canonical: grows along +x from the root at the origin,
        let depth = 0; // rotated into place at layout time

        // The center line is the run of unbracketed F's. Counting them first
        // gives the parabola a length to scale itself against.
        let trunkLen = 0;
        let d = 0;
        for (const c of word) {
            if (c === "[") d++;
            else if (c === "]") d--;
            else if (c === "F" && d === 0) trunkLen++;
        }

        const k = CURVE / trunkLen;
        let px = 0; // how far along the parabola's x axis the trunk has run

        for (const c of word) {
            switch (c) {
                case "F": {
                    let nx: number;
                    let ny: number;
                    if (depth === 0) {
                        // Advance one unit of arc length along y = k*x^2:
                        // dx = 1/sqrt(1 + slope^2) makes the step unit-long,
                        // and the vertex is read straight off the parabola.
                        const slope = 2 * k * px;
                        px += 1 / Math.sqrt(1 + slope * slope);
                        nx = px;
                        ny = k * px * px;
                    } else {
                        nx = x + Math.cos(a);
                        ny = y + Math.sin(a);
                    }
                    segs.push({ x1: x, y1: y, x2: nx, y2: ny, depth });
                    x = nx;
                    y = ny;
                    // Hand branches the parabola's tangent so limbs fork off
                    // in the direction the trunk is actually heading.
                    if (depth === 0) a = Math.atan(2 * k * px);
                    break;
                }
                case "+":
                    a -= DELTA;
                    break;
                case "-":
                    a += DELTA;
                    break;
                case "[":
                    stack.push({ x, y, a, depth });
                    depth++;
                    break;
                case "]": {
                    const s = stack.pop();
                    if (s) ({ x, y, a, depth } = s);
                    break;
                }
            }
        }
        return segs;
    }

    // Trunk heavy, twigs hairline.
    const widthFor = (depth: number) => Math.max(0.55, 2.4 * Math.pow(0.76, depth));

    onMount(() => {
        const ctx = canvas.getContext("2d");
        if (!ctx) return;

        const model = trace(expand());

        type Placement = {
            angle: number;
            anchorX: number;
            anchorY: number;
            flipY: number;
            delta: { x: number; y: number };
        };

        // Reflect, then rotate. Every tree is the same traced model read
        // through a different transform.
        function basis(p: Placement) {
            const rot = (p.angle * Math.PI) / 180;
            const cos = Math.cos(rot);
            const sin = Math.sin(rot);
            return {
                x: (x: number, y: number) => x * cos - y * p.flipY * sin,
                y: (x: number, y: number) => x * sin + y * p.flipY * cos,
            };
        }

        let placed: Segment[][] = [];
        let cssW = 0;
        let cssH = 0;

        function layout() {
            cssW = window.innerWidth;
            cssH = window.innerHeight;

            // Taller than the viewport by the slide amplitude on each side.
            // Drawing is shifted down by SLIDE_PX so layout coordinates stay
            // viewport-relative and the extra strips sit off-screen.
            const dpr = window.devicePixelRatio || 1;
            canvas.width = Math.round(cssW * dpr);
            canvas.height = Math.round((cssH + 2 * SLIDE_PX) * dpr);
            ctx!.setTransform(dpr, 0, 0, dpr, 0, SLIDE_PX * dpr);

            const trees = cssH > cssW ? UPRIGHT : SIDEWAYS;

            // Sizing comes from one tree, not the pair: each should span the
            // viewport on its own and overlap in the middle. Fitting their
            // combined extent would shrink both to half the screen.
            const f = basis(trees[0]);
            let minX = Infinity;
            let maxX = -Infinity;
            let minY = Infinity;
            let maxY = -Infinity;
            for (const s of model) {
                const ax = f.x(s.x1, s.y1);
                const ay = f.y(s.x1, s.y1);
                const bx = f.x(s.x2, s.y2);
                const by = f.y(s.x2, s.y2);
                minX = Math.min(minX, ax, bx);
                maxX = Math.max(maxX, ax, bx);
                minY = Math.min(minY, ay, by);
                maxY = Math.max(maxY, ay, by);
            }
            const modelW = maxX - minX || 1;
            const modelH = maxY - minY || 1;

            // Geometric blend between contain and cover so FILL feels linear.
            const contain = Math.min(cssW / modelW, cssH / modelH);
            const cover = Math.max(cssW / modelW, cssH / modelH);
            const scale = contain * Math.pow(cover / contain, FILL);

            placed = trees.map((tree) => {
                const t = basis(tree);
                // Offsets place the root itself, since it sits at the origin.
                const offX = (tree.anchorX + tree.delta.x) * cssW;
                const offY = (tree.anchorY + tree.delta.y) * cssH;
                return model.map((s) => ({
                    x1: t.x(s.x1, s.y1) * scale + offX,
                    y1: t.y(s.x1, s.y1) * scale + offY,
                    x2: t.x(s.x2, s.y2) * scale + offX,
                    y2: t.y(s.x2, s.y2) * scale + offY,
                    depth: s.depth,
                }));
            });
        }

        // Gruvbox yellow, tuned per theme: the light palette needs a little
        // more alpha to stay visible against #fbf1c7.
        function palette() {
            const dark = document.documentElement.classList.contains("dark");
            return dark
                ? { color: "#fabd2f", alpha: 0.13 }
                : { color: "#d79921", alpha: 0.18 };
        }

        // One Path2D per line width: stroking each bucket once keeps
        // overlapping joints from compounding into darker blobs at these
        // low alphas. The grown prefix only ever extends, so paths are
        // appended to across frames instead of rebuilt.
        let buckets = new Map<number, Path2D>();
        let built = 0;

        const bucketFor = (w: number) => {
            const key = Math.round(w * 10) / 10;
            let path = buckets.get(key);
            if (!path) buckets.set(key, (path = new Path2D()));
            return path;
        };

        function resetPaths() {
            buckets = new Map();
            built = 0;
        }

        function render(progress: number) {
            ctx!.clearRect(0, -SLIDE_PX, cssW, cssH + 2 * SLIDE_PX);
            const count = placed[0]?.length ?? 0;
            if (count === 0) return;

            const { color, alpha } = palette();
            ctx!.globalAlpha = alpha;
            ctx!.strokeStyle = color;
            ctx!.lineCap = "round";

            const shown = progress * count;
            const full = Math.min(Math.floor(shown), count);
            const frac = shown - full;

            // Every tree is the same model, so one index walks them all and
            // they grow together rather than one finishing before the next.
            for (; built < full; built++) {
                for (const tree of placed) {
                    const s = tree[built];
                    const path = bucketFor(widthFor(s.depth));
                    path.moveTo(s.x1, s.y1);
                    path.lineTo(s.x2, s.y2);
                }
            }

            for (const [w, path] of buckets) {
                ctx!.lineWidth = w;
                ctx!.stroke(path);
            }

            // The growing tips live in a throwaway path so they can be
            // extruded continuously rather than stepping a whole segment.
            if (frac > 0 && full < count) {
                for (const tree of placed) {
                    const s = tree[full];
                    const tip = new Path2D();
                    tip.moveTo(s.x1, s.y1);
                    tip.lineTo(s.x1 + (s.x2 - s.x1) * frac, s.y1 + (s.y2 - s.y1) * frac);
                    ctx!.lineWidth = widthFor(s.depth);
                    ctx!.stroke(tip);
                }
            }

            ctx!.globalAlpha = 1;
        }

        const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
        let progress = 0;
        let frame = 0;
        let start = 0;

        function grow(now: number) {
            if (!start) start = now;
            const t = Math.min((now - start) / GROW_MS, 1);
            progress = 1 - Math.pow(1 - t, 1.6); // eases out as it fills in
            render(progress);
            if (t < 1) frame = requestAnimationFrame(grow);
        }

        layout();
        if (reduceMotion.matches) {
            progress = 1;
            render(progress);
        } else {
            frame = requestAnimationFrame(grow);
        }

        const onResize = () => {
            layout();
            resetPaths(); // cached paths hold the old scale/offset
            render(progress);
        };
        window.addEventListener("resize", onResize);

        // The layout toggles `dark` on <html> when the OS scheme changes.
        const themeObserver = new MutationObserver(() => render(progress));
        themeObserver.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["class"],
        });

        return () => {
            cancelAnimationFrame(frame);
            window.removeEventListener("resize", onResize);
            themeObserver.disconnect();
        };
    });
</script>

<canvas
    bind:this={canvas}
    aria-hidden="true"
    style="--slide: {SLIDE_PX}px; --slide-ms: {SLIDE_MS}ms;"
></canvas>

<style>
    canvas {
        position: fixed;
        left: 0;
        /* Overhangs the viewport by --slide top and bottom so the drift
           never uncovers a bare strip at either edge. */
        top: calc(-1 * var(--slide));
        width: 100%;
        height: calc(100% + 2 * var(--slide));
        z-index: -1;
        pointer-events: none;
        animation: drift var(--slide-ms) ease-in-out infinite alternate;
    }

    /* Transform-only, so this stays on the compositor and never triggers
       layout, paint, or a canvas redraw. */
    @keyframes drift {
        from {
            transform: translateY(calc(-1 * var(--slide)));
        }
        to {
            transform: translateY(var(--slide));
        }
    }

    @media (prefers-reduced-motion: reduce) {
        canvas {
            animation: none;
        }
    }
</style>
