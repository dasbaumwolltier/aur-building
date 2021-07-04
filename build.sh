#!/bin/bash

DEBUG=1

[ $DEBUG ] && set -x

BUILD_DIR=$(realpath build)
PACKAGE_LIST=$(realpath package-list)
PACMAN_DB_NAME=$(realpath dasbaumwolltier)
CRTFILE=$(realpath sign.crt)
KEYFILE=$(realpath sign.key)
COMPRESSION=zst
ARCH=x86_64

PACMAN_CONF=$(realpath pacman.conf)

POSITIONAL=()
while [[ $# -gt 0 ]]; do

key="$1"

case $key in
    -b|--build-dir)
    BUILD_DIR="$2"
    shift; shift
    ;;
    -p|--package-list)
    PACKAGE_LIST="$2"
    shift; shift
    ;;
    -n|--db-name)
    PACMAN_DB_NAME="$2"
    shift; shift
    ;;
    -c|--compression)
    COMPRESSION="$2"
    shift; shift
    ;;
    -a|--arch)
    ARCH="$2"
    shift; shift
    ;;
    *)
    POSITIONAL+=("$1")
    shift
    ;;
esac
done

mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/packages"

cp $PACMAN_DB_NAME.db.* "$BUILD_DIR/"
cp $PACMAN_DB_NAME.files.* "$BUILD_DIR/"

cp -avR /build/personal "$BUILD_DIR/personal"

PACMAN_DB_NAME="$BUILD_DIR/$(basename $PACMAN_DB_NAME)"

if [ ! -f $PACKAGE_LIST ]; then
    exit 1
fi

function install_packages {
    for p in $@; do
        sudo pacman -S --noconfirm --needed $p
    done

    return $?
}

function call_makepkg {
    makepkg --skippgpcheck --sign --key "$SIGN_EMAIL" $@
    return $?
}

function install_yay {
    install_packages go

    git clone https://aur.archlinux.org/yay.git "$BUILD_DIR/yay-used"
    cd "$BUILD_DIR/yay-used"

    makepkg
    sudo pacman -U --noconfirm yay-*.pkg.tar.*

    cd ../..
    return $?
}

function aur_download_pkgbuild {
    yay -G --noconfirm --nopgpfetch $@
}

function personal_download_pkgbuild {
    return 0
}

function get_version {
    GET_VERSION="$(pacman -Sib "$BUILD_DIR/database" --config "$PACMAN_CONF" "$1" | awk '($1=="Version"){print $3;}')"
    GET_ARCH="$(pacman -Sib "$BUILD_DIR/database" --config "$PACMAN_CONF" "$1" | awk '($1=="Architecture"){print $3;}')"
}

function download_file {
    #set +x

    for file in $@; do
        wget "$REPO_URL/$ARCH/$file" --read-timeout=5 --tries=5 -O "$file" || (rm "$file" && return 1)
    done

    #[ $DEBUG ] && set -x
}

function upload_file {
    set +x
    curl --user "$REPO_USER:$REPO_PASS" --upload-file "$1" "$REPO_URL/$ARCH/$(basename $1)"

    [ $DEBUG ] && set -x
}

MAKE_DEPENDS=()
DEPENDS=()
GET_VERSION=""
GET_ARCH=""
PKGBUILD_VERSION=""

function get_make_depends {
    IFS=' ' read -ra MAKE_DEPENDS <<< "$(. "$1/PKGBUILD"; echo ${makedepends[@]})"
}

function aur_get_make_depends {
    # IFS=' ' read -ra MAKE_DEPENDS <<< "$(yay -Sai "$1" | grep -i 'Make Deps' | cut -d':' -f2 | sed 's/^ //g' | sed 's/None//g')"
    get_make_depends "$BUILD_DIR/$1"
}

function personal_get_make_depends {
    get_make_depends "$BUILD_DIR/personal/$1"
}

function get_depends {
    IFS=' ' read -ra DEPENDS <<< "$(. "$1/PKGBUILD"; echo ${depends[@]})"
}

function aur_get_depends {
    # IFS=' ' read -ra DEPENDS <<< "$(yay -Sai "$1" | grep -i 'Depends' | cut -d':' -f2 | sed 's/^ //g' | sed 's/None//g')"
    get_depends "$BUILD_DIR/$1"
}

function personal_get_depends {
    # IFS=' ' read -ra DEPENDS <<< "$(yay -Sai "$1" | grep -i 'Depends' | cut -d':' -f2 | sed 's/^ //g' | sed 's/None//g')"
    get_depends "$BUILD_DIR/personal/$1"
}

function get_pkgbuild_version {
    local is_function
    (. "$1/PKGBUILD"; pkgver); is_function=$?

    if [ $is_function -eq 127 ]; then
        local tmp
        IFS=' ' read -ra tmp <<< "$(. "$1/PKGBUILD"; echo ${pkgver})"
        PKGBUILD_VERSION="$tmp"

        IFS=' ' read -ra tmp <<< "$(. "$1/PKGBUILD"; echo ${pkgrel})"
        if [ -n "$tmp" ]; then
            PKGBUILD_VERSION="$PKGBUILD_VERSION-$tmp"
        fi

        IFS=' ' read -ra tmp <<< "$(. "$1/PKGBUILD"; echo ${epoch})"
        if [ -n "$tmp" ]; then
            PKGBUILD_VERSION="$tmp:$PKGBUILD_VERSION"
        fi        

        return 0
    fi

    return 1
}

function aur_get_pkgbuild_version {
    get_pkgbuild_version "$BUILD_DIR/$1"
}

function personal_get_pkgbuild_version {
    get_pkgbuild_version "$BUILD_DIR/personal/$1"
}

function compare_versions {
    if "$2_get_pkgbuild_version" $1; then
        return $(vercmp "$PKGBUILD_VERSION" "$GET_VERSION")
    fi

    return 127
}

function aur_compare_versions {
    compare_versions $1 "aur"
}

function personal_compare_versions {
    compare_versions $1 "personal"
}

function try_download {
    args=(${@})

    res=$1
    depend=$2
    pkgnames=(${args[@]:2})

    for pkgname in "${pkgnames[@]}"; do
        if [ -n "$GET_VERSION" ]; then
            download_file "$pkgname-$GET_VERSION-$GET_ARCH.pkg.tar.$COMPRESSION" && \
            download_file "$pkgname-$GET_VERSION-$GET_ARCH.pkg.tar.$COMPRESSION.sig" || \
            return 1
        fi

        if [ $res -eq 255 ] || [ $res -eq 0 ]; then
            if $depend; then
                sudo pacman -U --noconfirm $pkgname*.pkg.tar.$COMPRESSION
            fi

            cp $pkgname*.pkg.tar.$COMPRESSION "$BUILD_DIR/packages/" && \
            cp $pkgname*.pkg.tar.$COMPRESSION.sig "$BUILD_DIR/packages/" || \
            return 1
        else
            return 1
        fi
    done

    return 0
}

# IFS=$'\n' read -d'\n' -ra PACKAGES < $PACKAGE_LIST

sudo pacman -Syu --noconfirm
install_packages git base-devel sudo

gpg --import "$CRTFILE"
gpg --import "$KEYFILE"
sudo pacman-key --add "$CRTFILE"
sudo pacman-key --add "$KEYFILE"
sudo pacman-key --lsign-key "$SIGN_EMAIL"

if [ ! -f /usr/bin/yay ]; then
    install_yay
fi

cat "$PACKAGE_LIST"

mkdir -p "$BUILD_DIR/database/sync"
ls -la /build
cp "$PACMAN_DB_NAME.db.tar.$COMPRESSION" "$BUILD_DIR/database/sync/$(basename $PACMAN_DB_NAME).db"
cp "$PACMAN_DB_NAME.db.tar.$COMPRESSION.sig" "$BUILD_DIR/database/sync/$(basename $PACMAN_DB_NAME).sig"

while read -u10 package_name; do
    if [ -z "$package_name" ]; then
        continue
    fi
    
    case "$package_name" in
        \#*) continue ;;
    esac

    echo $package_name

    IFS=' ' read -ra splitted <<< "$package_name"

    depend=false
    noinstall=false
    makepkg_options=""
    pkgnames=(${splitted[1]})
    dirname="${splitted[1]}"

    for opt in ${splitted[@]:2}; do
        case "$opt" in
            depend) depend=true ;;
            noinstall) noinstall=true ;;
            nocheck) makepkg_options="$makepkg_options --nocheck" ;;
            dirname=*) dirname="$(echo $opt | awk -F= '{print $2}')" ;;
            pkgnames=*) pkgnames=($(echo $opt | awk -F= '{print $2}' | tr ',' ' ')) ;;
            *) ;;
        esac
    done

    get_version "${splitted[1]}"

    cd "$BUILD_DIR"
    "${splitted[0]}_download_pkgbuild" ${splitted[1]}

    "${splitted[0]}_get_make_depends" $dirname
    "${splitted[0]}_get_depends" $dirname

    "${splitted[0]}_compare_versions" $dirname $GET_VERSION
    res=$?

    if [ "${splitted[0]}" == "personal" ]; then
        cd "personal"
    fi

    cd "$dirname"
    if try_download $res $depend ${pkgnames[@]}; then
        continue
    fi

    if [ ${#MAKE_DEPENDS[@]} -ne 0 ]; then
        echo "Installing Make Dependencies"
        install_packages ${MAKE_DEPENDS[@]}
    fi

    if [ ${#DEPENDS[@]} -ne 0 ]; then
        echo "Installing Dependencies"
        install_packages ${DEPENDS[@]}
    fi

    CUR_DIR="$(pwd)"

    call_makepkg "$makepkg_options"

    for pkgname in "${pkgnames[@]}"; do
        for f in $CUR_DIR/$pkgname*.pkg.tar.$COMPRESSION; do
            res=0
            if ! $noinstall; then
                sudo pacman -U --noconfirm "$f"
                res=$?
            fi

            if $noinstall || [ $res -eq 0 ]; then
                cp "$f" "$BUILD_DIR/packages/" &&\
                cp "$f.sig" "$BUILD_DIR/packages/"
            fi
        done
    done

    cd ../..
done 10< "$PACKAGE_LIST"

cd "$BUILD_DIR/packages"
ls -la

for file in $BUILD_DIR/packages/*.pkg.tar.$COMPRESSION; do
    repo-add --sign --prevent-downgrade --key "$SIGN_EMAIL" "$PACMAN_DB_NAME.db.tar.$COMPRESSION" "$file" \
        && upload_file "$file" && upload_file "$file.sig"
done

cp "$PACMAN_DB_NAME.db.tar.$COMPRESSION" "$PACMAN_DB_NAME.db"
cp "$PACMAN_DB_NAME.db.tar.$COMPRESSION.sig" "$PACMAN_DB_NAME.db.sig"
cp "$PACMAN_DB_NAME.files.tar.$COMPRESSION" "$PACMAN_DB_NAME.files"
cp "$PACMAN_DB_NAME.files.tar.$COMPRESSION.sig" "$PACMAN_DB_NAME.files.sig"

upload_file "$PACMAN_DB_NAME.db"
upload_file "$PACMAN_DB_NAME.db.sig"
upload_file "$PACMAN_DB_NAME.db.tar.$COMPRESSION"
upload_file "$PACMAN_DB_NAME.db.tar.$COMPRESSION.sig"
upload_file "$PACMAN_DB_NAME.files"
upload_file "$PACMAN_DB_NAME.files.sig"
upload_file "$PACMAN_DB_NAME.files.tar.$COMPRESSION"
upload_file "$PACMAN_DB_NAME.files.tar.$COMPRESSION.sig"