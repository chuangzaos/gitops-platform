# syntax=docker/dockerfile:1

# Zero-dependency Node service - no npm install step required.
FROM node:20-alpine

WORKDIR /app

# Non-root user for the running process
RUN addgroup -S app && adduser -S app -G app

COPY package.json ./
COPY src ./src

USER app
EXPOSE 8080
ENV PORT=8080

CMD ["node", "src/server.js"]
