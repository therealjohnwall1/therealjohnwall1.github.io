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

    // The bare lower stem is ~30% of the height but under 2% of the branch
    // mass. Framing on just the canopy drops that dead space so foliage,
    // not stem, gets the screen.
    const CANOPY = 0.5;

    // 0 = whole canopy visible (letterboxed), 1 = canopy covers the viewport
    // in both axes (heavily cropped). The canopy is far taller than any
    // normal screen is, so the useful range is in between: raise it to push
    // branches further into the left/right margins at the cost of cropping
    // more off the top and bottom.
    const FILL = 0.4;

    // Nudge the tree around, in fractions of the viewport. 0 = centered.
    // X: negative moves left, positive right. Y: negative moves UP,
    // positive down. So -0.1 shifts by a tenth of the screen.
    const OFFSET_X = 0;
    const OFFSET_Y = 0;

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
        let a = -Math.PI / 2; // pointing up; canvas y grows downward
        let depth = 0;

        for (const c of word) {
            switch (c) {
                case "F": {
                    const nx = x + Math.cos(a);
                    const ny = y + Math.sin(a);
                    segs.push({ x1: x, y1: y, x2: nx, y2: ny, depth });
                    x = nx;
                    y = ny;
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

        let minX = Infinity;
        let maxX = -Infinity;
        let minY = Infinity;
        let maxY = -Infinity;
        for (const s of model) {
            minX = Math.min(minX, s.x1, s.x2);
            maxX = Math.max(maxX, s.x1, s.x2);
            minY = Math.min(minY, s.y1, s.y2);
            maxY = Math.max(maxY, s.y1, s.y2);
        }
        const modelW = maxX - minX || 1;
        const modelH = maxY - minY || 1;

        // Frame on the canopy: the top CANOPY fraction of the bounding box,
        // measured from the tip down. Everything below is bare stem.
        const canopyH = modelH * CANOPY;
        const canopyMidY = minY + canopyH / 2;
        const canopyMidX = minX + modelW / 2;

        let placed: Segment[] = [];
        let cssW = 0;
        let cssH = 0;

        function layout() {
            cssW = window.innerWidth;
            cssH = window.innerHeight;

            const dpr = window.devicePixelRatio || 1;
            canvas.width = Math.round(cssW * dpr);
            canvas.height = Math.round(cssH * dpr);
            ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);

            // Geometric blend between contain and cover so FILL feels linear.
            const contain = Math.min(cssW / modelW, cssH / canopyH);
            const cover = Math.max(cssW / modelW, cssH / canopyH);
            const scale = contain * Math.pow(cover / contain, FILL);

            const offX = cssW / 2 - canopyMidX * scale + OFFSET_X * cssW;
            const offY = cssH / 2 - canopyMidY * scale + OFFSET_Y * cssH;

            placed = model.map((s) => ({
                x1: s.x1 * scale + offX,
                y1: s.y1 * scale + offY,
                x2: s.x2 * scale + offX,
                y2: s.y2 * scale + offY,
                depth: s.depth,
            }));
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
            ctx!.clearRect(0, 0, cssW, cssH);
            if (placed.length === 0) return;

            const { color, alpha } = palette();
            ctx!.globalAlpha = alpha;
            ctx!.strokeStyle = color;
            ctx!.lineCap = "round";

            const shown = progress * placed.length;
            const full = Math.min(Math.floor(shown), placed.length);
            const frac = shown - full;

            for (; built < full; built++) {
                const s = placed[built];
                const path = bucketFor(widthFor(s.depth));
                path.moveTo(s.x1, s.y1);
                path.lineTo(s.x2, s.y2);
            }

            for (const [w, path] of buckets) {
                ctx!.lineWidth = w;
                ctx!.stroke(path);
            }

            // The growing tip lives in its own throwaway path so it can be
            // extruded continuously rather than stepping a whole segment.
            if (frac > 0 && full < placed.length) {
                const s = placed[full];
                const tip = new Path2D();
                tip.moveTo(s.x1, s.y1);
                tip.lineTo(s.x1 + (s.x2 - s.x1) * frac, s.y1 + (s.y2 - s.y1) * frac);
                ctx!.lineWidth = widthFor(s.depth);
                ctx!.stroke(tip);
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

<canvas bind:this={canvas} aria-hidden="true"></canvas>

<style>
    canvas {
        position: fixed;
        inset: 0;
        width: 100%;
        height: 100%;
        z-index: -1;
        pointer-events: none;
    }
</style>
