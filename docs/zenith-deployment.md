# Zenith deployment

This repository runs a Bun monorepo with a Next.js app, a NestJS API, an Eve agent, and PostgreSQL.

## Build and runtime

- Docker build context: repository root.
- Dockerfile: `Dockerfile`.
- Image workflow: `.github/workflows/publish-container.yml`.
- Production platform: `linux/amd64`.
- Web app command: `bun run --filter=app start`.
- API smoke command: `bun run db:deploy && bun run --filter=api start`.
- Internal API port: `3001`.
- Internal app port: `3000`.
- Internal agent port: `2000`.
- Required service: PostgreSQL 17.
- Persistent application state: PostgreSQL data.

The container starts the web app. The image also contains the API and agent runtimes for service-level deployment wiring.
The API requires `DATABASE_URL`, `BETTER_AUTH_SECRET`, and `ALLOWED_SIGN_IN`.
The app uses `API_URL` or `NEXT_PUBLIC_API_URL` for the API origin.
The agent uses `AGENT_URL` and `AGENT_BRIDGE_SECRET` when the Agent panel is enabled.
OAuth, blob storage, cache, and provider keys remain optional capabilities.

## Verification

The publishing workflow builds an AMD64 image on pull requests.
It starts PostgreSQL, applies migrations, starts the API, and requests `/health`.
The default-branch workflow publishes an image to GHCR.
The workflow checks anonymous manifest and config access, pulls the AMD64 image anonymously, and repeats the API smoke test.
The workflow writes the verified immutable image reference to the `zenith-image-update` artifact.

## Zenith process

1. Merge the container PR.
2. Confirm the default-branch image workflow passes.
3. Confirm the GHCR image is anonymously pullable and runs the smoke test.
4. Use the verified image digest in `zenith-compose.yml`.
5. Open the compose PR for review.
6. Merge the compose PR.
7. Submit the repository through Zenith's Publish an app page.

A published image does not update the Zenith manifest.
A merged manifest does not submit or update a Zenith catalogue entry.
