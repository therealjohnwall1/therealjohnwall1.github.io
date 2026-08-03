<script lang="ts">
    import "../css/global.css";
    import { base } from "$app/paths";

    let { children } = $props();

    // Theming is entirely in global.css, off prefers-color-scheme. Doing it
    // here instead would mean a light-mode flash on every load: the pages are
    // prerendered, so the browser paints long before this file runs.
</script>

<header>
    <nav>
        <a href="{base}/">Home</a>
        <a href="{base}/experience">Experience</a>
        <a href="{base}/projects">Projects</a>
        <a href="{base}/contact">Contact</a>
    </nav>
</header>

<main>
    {@render children?.()}
</main>
