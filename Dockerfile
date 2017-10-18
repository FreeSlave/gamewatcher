FROM debian:jessie
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libcrypto++-dev libevent-dev libssl-dev wget libcurl3 gcc && \
    wget http://downloads.dlang.org/releases/2.x/2.076.1/dmd_2.076.1-0_amd64.deb && dpkg -i dmd_2.076.1-0_amd64.deb && \
    apt-get remove -y wget && \
    apt-get -y clean && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*
RUN mkdir -p /opt/gamewatcher
WORKDIR /opt/gamewatcher
COPY ./dub.json .
COPY ./dub.selections.json .
COPY ./config.json .
COPY ./public ./public
COPY ./source ./source
COPY ./views ./views
RUN dub build && useradd gamewatcher && mkdir -p /etc/vibe/ && echo '{"user": "gamewatcher","group": "gamewatcher"}"' > /etc/vibe/vibe.conf
EXPOSE 27080
ENTRYPOINT ["./gamewatcher"]
