# sv

Everything you need to build a Svelte project, powered by [`sv`](https://github.com/sveltejs/cli).

## Creating a project

If you're seeing this, you've probably already done this step. Congrats!

```sh
# create a new project in the current directory
npx sv create

# create a new project in my-app
npx sv create my-app
```

## Developing

### Using Podman/Docker (Recommended)

Build and run the development server in a container:

```sh
# Build the container image
podman build -t svelte-site .

# Run the container with mounted filesystem
podman run -d -p 5173:5173 -v "$(pwd):/app:z" --name svelte-dev svelte-site

# View logs
podman logs -f svelte-dev

# Stop the container
podman stop svelte-dev

# Remove the container
podman rm svelte-dev
```

The site will be available at `http://localhost:5173`

### Using npm directly

Once you've created a project and installed dependencies with `npm install` (or `pnpm install` or `yarn`), start a development server:

```sh
npm run dev

# or start the server and open the app in a new browser tab
npm run dev -- --open
```

## Building

To create a production version of your app:

```sh
npm run build
```

You can preview the production build with `npm run preview`.

> To deploy your app, you may need to install an [adapter](https://svelte.dev/docs/kit/adapters) for your target environment.
