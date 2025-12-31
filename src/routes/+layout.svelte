<script lang="ts">
    import favicon from "$lib/assets/favicon.svg";
    import "../css/global.css";
    import { base } from "$app/paths";
    import { onMount } from "svelte";

    let { children } = $props();
    let darkMode = $state(false);

    onMount(() => {
        const prefersDark = window.matchMedia(
            "(prefers-color-scheme: dark)",
        ).matches;
        darkMode = prefersDark;

        // Apply dark class to HTML element
        if (prefersDark) {
            document.documentElement.classList.add("dark");
        }

        // Listen for changes to color scheme preference
        const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
        const handleChange = (e: MediaQueryListEvent) => {
            darkMode = e.matches;
            if (e.matches) {
                document.documentElement.classList.add("dark");
            } else {
                document.documentElement.classList.remove("dark");
            }
        };
        mediaQuery.addEventListener("change", handleChange);

        return () => {
            mediaQuery.removeEventListener("change", handleChange);
        };
    });
</script>

<svelte:head>
    <link rel="icon" href={favicon} />
</svelte:head>

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
