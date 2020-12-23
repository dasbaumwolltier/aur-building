FROM dasbaumwolltier/archlinux-yay

ARG REPOSITORY_NAME=dasbaumwolltier

RUN pacman-key --init &&\
    pacman-key --populate archlinux &&\
    pacman -Suy --noconfirm &&\
    pacman -S sudo git go base-devel clang wget --noconfirm

# RUN mkdir -p /build &&\
#     chown -R yay:yay /build &&\
RUN echo "[${REPOSITORY_NAME}]" >> /build/pacman.conf

# USER yay

# RUN mkdir -p /tmp &&\
#     cd /tmp &&\
#     git clone https://aur.archlinux.org/yay.git &&\
#     cd yay &&\
#     makepkg

# USER root
# RUN cd /tmp/yay &&\
#     pacman -U --noconfirm yay-*.pkg.tar.*

USER yay

COPY build.sh /build
COPY package-list /build

WORKDIR /build

ENTRYPOINT /bin/bash /build/build.sh