# Simple development container
FROM node:20-alpine

WORKDIR /app

# Expose the port the dev server runs on
EXPOSE 5173

# Install dependencies and start dev server
CMD ["sh", "-c", "npm install && npm run dev -- --host 0.0.0.0"]
