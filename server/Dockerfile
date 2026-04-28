# ─── Stage 1: Flutter 웹 빌드 ──────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /flutter-app
COPY app/pubspec.yaml ./
COPY app/pubspec.lock* ./
RUN flutter pub get
COPY app/ ./

ARG COACHDESK_API_BASE_URL=""
ARG APPLE_WEB_SERVICE_ID=""
RUN flutter build web --release \
    --dart-define=COACHDESK_API_BASE_URL="$COACHDESK_API_BASE_URL" \
    --dart-define=APPLE_WEB_SERVICE_ID="$APPLE_WEB_SERVICE_ID"

# ─── Stage 2: 서버 TS 빌드 ─────────────────────────────
FROM node:20-alpine AS server-builder

WORKDIR /app
COPY server/package.json server/package-lock.json* ./
RUN npm ci
COPY server/prisma/ ./prisma/
RUN npx prisma generate
COPY server/tsconfig.json ./
COPY server/src/ ./src/
RUN npm run build

# ─── Stage 3: 런타임 ──────────────────────────────────
FROM node:20-alpine

WORKDIR /app
COPY server/package.json server/package-lock.json* ./
RUN npm ci --omit=dev
COPY server/prisma/ ./prisma/
RUN npx prisma generate
COPY --from=server-builder /app/dist ./dist
COPY --from=flutter-builder /flutter-app/build/web /app/build/web
COPY server/docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["./docker-entrypoint.sh"]
