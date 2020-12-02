#!/bin/sh

DEBUG=1

[ $DEBUG ] && set -x

BUILD_DIR=$(realpath build)
PACKAGE_LIST=$(realpath package-list)
PACMAN_DB_NAME=$(realpath dasbaumwolltier)
CRTFILE=$(realpath sign.crt)
KEYFILE=$(realpath sign.key)
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
    set +x
    curl --user "$REPO_USER:$REPO_PASS" --upload-file "$1" "$REPO_URL/$ARCH/$(basename $1)"

    [ $DEBUG ] && set -x
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

gpg --import "$CRTFILE"
gpg --import "$KEYFILE"
sudo pacman-key --add "$CRTFILE"
sudo pacman-key --add "$KEYFILE"
sudo pacman-key --lsign-key "$SIGN_EMAIL"

if [ ! -f /usr/bin/yay ]; then
    install_yay
fi

cat "$PACKAGE_LIST"

while read package; do
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

    sudo pacman -U --noconfirm $BUILD_DIR/${splitted[1]}/${splitted[1]}*.pkg.tar.$COMPRESSION

    cd ../..
done < "$PACKAGE_LIST"

cd "$BUILD_DIR/packages"
ls -la
repo-add --sign --verify --key "$SIGN_EMAIL" "$PACMAN_DB_NAME.db.tar.$COMPRESSION" $BUILD_DIR/packages/*.pkg.tar.$COMPRESSION

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