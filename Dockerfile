FROM debian:jessie
RUN apt-get update -y && apt-get install -yy libevent-2.0-5 libevent-pthreads-2.0-5 libssl1.0.0 libcrypto++9 redis-server
RUN mkdir -p /opt
WORKDIR /opt
COPY ./gamewatcher .
COPY ./config.json .
COPY ./public ./public
EXPOSE 27080
CMD service redis-server start && ./gamewatcher