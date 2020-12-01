FROM archlinux

RUN pacman -Suy --noconfirm &&\
    pacman -S sudo fish git go base-devel --noconfirm &&\
    useradd yay &&\
    mkdir -p /home/yay &&\
    chown -R yay:yay /home/yay &&\
    echo "yay ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /build &&\
    chown -R yay:yay /build

USER yay

RUN mkdir -p /tmp &&\
    cd /tmp &&\
    git clone https://aur.archlinux.org/yay.git &&\
    cd yay &&\
    makepkg

USER root
RUN cd /tmp/yay &&\
    pacman -U --noconfirm yay-*.pkg.tar.*

USER yay

COPY build.fish /build
COPY package-list /build
COPY dasbaumwolltier* /build/

WORKDIR /build

ENTRYPOINT /usr/bin/fish /build/build.fish