FROM dasbaumwolltier/archlinux-yay

ARG REPOSITORY_NAME=dasbaumwolltier

USER root
RUN pacman-key --init &&\
    pacman-key --populate archlinux &&\
    pacman -Suy --noconfirm &&\
    pacman -S sudo git go base-devel clang wget --noconfirm

RUN mkdir /build &&\
    chown -R 1000:1000 /build &&\
    echo "[${REPOSITORY_NAME}]" >> /build/pacman.conf

USER 1000
COPY build.sh /build
COPY package-list /build

WORKDIR /build

ENTRYPOINT /bin/bash /build/build.sh