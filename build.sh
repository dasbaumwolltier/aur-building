#!/bin/bash

BUILD_DIR=$(realpath build)
PACKAGE_LIST=$(realpath package-list)
PACMAN_DB_NAME=$(realpath dasbaumwolltier)
CRTFILE=$(realpath sign.crt)
KEYFILE=$(realpath sign.key)
SIGN_EMAIL=daemons@guldner.eu
COMPRESSION=zst
ARCH=x86_64

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

if ! gpg --list-public-keys "$SIGN_EMAIL" &> /dev/null ; then
    gpg --import "$CRTFILE"
fi

if ! gpg --list-secret-keys "$SIGN_EMAIL" &> /dev/null; then
    gpg --import "$KEYFILE"
fi

mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/packages"

if [ ! -f $PACKAGE_LIST ]; then
    exit 1
fi

function install_packages {
    for package in $@; do
        sudo pacman -S --noconfirm --needed $package
    done

    return $?
}

function call_makepkg {
    makepkg --sign --key "$SIGN_EMAIL" $@
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

function download_pkgbuild {
    yay -Ga --noconfirm --nopgpfetch $@
    return $?
}

function upload_file {
    curl --user "$REPO_USER:$REPO_PASS" --upload-file "$1" "$REPO_URL/$ARCH/$(basename $1)"
}

MAKE_DEPENDS=()
DEPENDS=()

function aur_get_make_depends {
    # IFS=' ' read -ra MAKE_DEPENDS <<< "$(yay -Sai "$1" | grep -i 'Make Deps' | cut -d':' -f2 | sed 's/^ //g' | sed 's/None//g')"
    IFS=' ' read -ra MAKE_DEPENDS <<< "$(. "$BUILD_DIR/$1/PKGBUILD"; echo ${makedepends[@]})"
}

function private_get_make_depends {
    IFS=' ' read -ra MAKE_DEPENDS <<< "$(yay -Sai "$1" | grep -i 'Make Deps' | cut -d':' -f2 | sed 's/^ //g' | sed 's/None//g')"
}

function aur_get_depends {
    # IFS=' ' read -ra DEPENDS <<< "$(yay -Sai "$1" | grep -i 'Depends' | cut -d':' -f2 | sed 's/^ //g' | sed 's/None//g')"
    IFS=' ' read -ra DEPENDS <<< "$(. "$BUILD_DIR/$1/PKGBUILD"; echo ${depends[@]})"
}

# IFS=$'\n' read -d'\n' -ra PACKAGES < $PACKAGE_LIST

sudo pacman -Syu --noconfirm
install_packages git base-devel sudo

if [ ! -f /usr/bin/yay ]; then
    install_yay
fi

while read -r package; do
    if [ -z "$package" ]; then
        continue
    fi

    echo $package

    IFS=' ' read -ra splitted <<< "$package"

    cd build
    download_pkgbuild "${splitted[1]}"

    "${splitted[0]}_get_make_depends" ${splitted[1]}
    "${splitted[0]}_get_depends" ${splitted[1]}

    if [ ${#MAKE_DEPENDS[@]} -ne 0 ]; then
        echo "Installing Make Dependencies"
        install_packages ${MAKE_DEPENDS[@]}
    fi

    if [ ${#DEPENDS[@]} -ne 0 ]; then
        echo "Installing Dependencies"
        install_packages ${DEPENDS[@]}
    fi

    cd "${splitted[1]}"
    call_makepkg
    cp $BUILD_DIR/${splitted[1]}/${splitted[1]}*.pkg.tar.* "$BUILD_DIR/packages/"

    sudo pacman -U --noconfirm $BUILD_DIR/${splitted[1]}/${splitted[1]}*.pkg.tar.*

    cd ../..
done < "$PACKAGE_LIST"

cd "$BUILD_DIR/packages"
ls -la
repo-add --sign --verify --key "$SIGN_EMAIL" "$PACMAN_DB_NAME.db.tar.$COMPRESSION" $BUILD_DIR/packages/*.pkg.tar.*

for f in $BUILD_DIR/packages/*.pkg.tar.*; do
    upload_file "$f"
done

upload_file "$PACMAN_DB_NAME.db"
upload_file "$PACMAN_DB_NAME.db.sig"
upload_file "$PACMAN_DB_NAME.db.tar.$COMPRESSION"
upload_file "$PACMAN_DB_NAME.db.tar.$COMPRESSION.sig"
upload_file "$PACMAN_DB_NAME.files"
upload_file "$PACMAN_DB_NAME.files.sig"
upload_file "$PACMAN_DB_NAME.files.tar.$COMPRESSION"
upload_file "$PACMAN_DB_NAME.files.tar.$COMPRESSION.sig"