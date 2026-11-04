FROM node:24-alpine

WORKDIR /app
ARG APP_VERSION=v42
ENV APP_VERSION=${APP_VERSION}
COPY web/server.mjs ./server.mjs

USER node
EXPOSE 80
CMD ["node", "server.mjs"]
