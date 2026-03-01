FROM debian:bullseye

RUN apt-get -y update && \
    apt-get install nginx -y && \
    apt-get install openssl -y && \
    apt-get install curl -y

RUN mkdir -p /etc/ssl/certs/ && \
    mkdir -p /etc/ssl/private


COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]