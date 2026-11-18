FROM node:22-bookworm-slim AS build

ENV NEXT_TELEMETRY_DISABLED=1

WORKDIR /app
COPY package.json package-lock.json .npmrc ./
RUN npm ci --no-audit --no-fund

COPY . .

# `npm run build` would sync the catalogs with upstream's translation.io
# project, so extract and compile them without the service. Every locale
# falls back to the English source.
RUN npx lingui extract --config lingui.container.config.js \
 && npx lingui compile --config lingui.container.config.js

# Standalone output is set here rather than in next.config.js so the fork
# never conflicts with upstream over that file.
#
# Built without NEXT_PUBLIC_ALCHEMY_API_KEY on purpose. Next inlines a
# NEXT_PUBLIC_ variable only when it is set at build time; left unset, the API
# routes read it from the environment when the server runs, so the key never
# lands in the image or in the browser bundle.
RUN echo 'module.exports.output = "standalone";' >> next.config.js \
 && npx next build --webpack \
 && ! grep -rq cloudflareinsights .next

FROM node:22-bookworm-slim

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    HOSTNAME=0.0.0.0 \
    PORT=8080

WORKDIR /app
# Incremental static regeneration rewrites pages under .next at runtime, and
# the OG image route reads fonts and icons from public/.
COPY --from=build --chown=node:node /app/.next/standalone ./
COPY --from=build --chown=node:node /app/.next/static ./.next/static
COPY --from=build /app/public ./public

EXPOSE 8080
USER node
CMD ["node", "server.js"]
