FROM nginx:stable-alpine

ARG APP_VERSION=v42
LABEL org.opencontainers.image.version="${APP_VERSION}"

RUN printf '%s\n' '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Contoso Orders</title></head><body><h1>Contoso Orders</h1><p>Demo website is running.</p><p><a href="/version.txt">Image version</a></p></body></html>' > /usr/share/nginx/html/index.html \
    && printf '%s\n' "$APP_VERSION" > /usr/share/nginx/html/version.txt

EXPOSE 80
