FROM debian:jessie
RUN apt-get update -y
RUN apt-get install -y libcrypto++-dev libevent-dev libssl-dev redis-server wget
RUN wget http://master.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list
RUN apt-get update -y && apt-get -y --allow-unauthenticated install --reinstall d-apt-keyring
RUN apt-get update -y
RUN apt-get install -y --no-install-recommends dmd-bin dub
RUN wget -qO- http://code.dlang.org/files/dub-1.2.1-linux-x86_64.tar.gz | tar zxf -
RUN mv dub /usr/local/bin
RUN mkdir -p /opt/gamewatcher
WORKDIR /opt/gamewatcher
COPY ./dub.json .
COPY ./dub.selections.json .
COPY ./config.json .
COPY ./public ./public
COPY ./source ./source
COPY ./views ./views
RUN dub build
EXPOSE 27080
CMD service redis-server start && ./gamewatcher