# Rocketchat

FROM debian

RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y wget \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 22322 drgroup \
 && adduser --disabled-password --gecos '' -u 22322 --gid 22322 druser

USER druser
COPY ["./drunner","/drunner"]
