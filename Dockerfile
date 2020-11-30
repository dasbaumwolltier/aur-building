FROM archlinux

RUN pacman -Suy --noconfirm &&\
    pacman -S sudo fish --noconfirm &&\
    useradd yay &&\
    echo "tom ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /build &&\
    chown -R yay:yay /build

USER yay

COPY build.fish /build
COPY package-list /build
COPY dasbaumwolltier* /build

ENTRYPOINT /usr/bin/fish /build/build.fish