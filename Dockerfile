FROM hibiken/asynqmon:latest AS asynqmon-source

FROM alpine:latest

RUN apk add --no-cache \
    nginx \
    apache2-utils \
    ca-certificates \
    tzdata \
    tini

COPY --from=asynqmon-source /asynqmon /usr/local/bin/asynqmon

RUN id -u nginx 2>/dev/null || adduser -D -s /bin/false nginx && \
    mkdir -p /var/lib/nginx/tmp /var/log/nginx /run/nginx /etc/nginx/conf.d

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/asynqmon

RUN adduser -D -s /bin/sh appuser

EXPOSE 80

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]