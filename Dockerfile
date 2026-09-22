FROM node:24-bookworm-slim AS dependencies

WORKDIR /workspace
ENV DATABASE_URL=postgresql://postgres:postgres@postgres:5432/crm?schema=public
COPY package.json bun.lock turbo.json ./
COPY apps apps
COPY packages packages
RUN find apps packages -type f -name package.json -not -path '*/node_modules/*' -print0 | xargs -0 -I{} sh -c 'mkdir -p "$(dirname "{}")"'
RUN npm install --global bun@1.3.12 && bun install --frozen-lockfile
COPY . .

FROM dependencies AS build
ENV NODE_ENV=production
ENV API_URL=http://api:3001
ENV NEXT_PUBLIC_API_URL=http://api:3001
ENV BETTER_AUTH_SECRET=build-only-secret-regenerate-for-runtime
ENV ALLOWED_SIGN_IN=build@example.test
RUN bun run build

FROM dependencies AS runtime
ENV NODE_ENV=production
ENV API_URL=http://api:3001
ENV NEXT_PUBLIC_API_URL=http://api:3001
COPY --from=build /workspace /workspace
EXPOSE 3000 3001 2000
CMD ["bun", "run", "--filter=app", "start"]
