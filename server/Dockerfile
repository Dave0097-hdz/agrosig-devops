FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
RUN node -e "require('bcrypt')"

FROM node:20-alpine AS runtime
RUN apk add --no-cache tini
ENV NODE_ENV=production TZ=America/Mexico_City

WORKDIR /app

COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json index.js config.js swagger.config.js database.json ./
COPY --chown=node:node migrations ./migrations
COPY --chown=node:node src ./src

RUN mkdir -p src/uploads/profile && chown node:node src/uploads/profile

USER node
EXPOSE 4000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "node_modules/.bin/db-migrate up -e production && exec node index.js"]