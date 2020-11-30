set BUILD_DIR (realpath build)
set PACKAGE_LIST (realpath package-list)
set PACMAN_DB_NAME (realpath repository)
set COMPRESSION zst
set ARCH x86_64

argparse --name=build 'b/build-dir=' 'p/package-list=' 'n/db-name' 'c/compression' 'a/arch' -- $argv

if set -q _flag_build_dir
    set BUILD_DIR (realpath _flag_build_dir)
end

if set -q _flag_package_list
    set PACKAGE_LIST (realpath _flag_package_list)
end

if set -q _flag_db_name
    set PACMAN_DB_NAME (realpath _flag_db_name)
end

if set -q _flag_compression
    set COMPRESSION _flag_compression
end

if set -q _flag_arch
    set ARCH _flag_arch
end

mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/packages"

if test ! -f $PACKAGE_LIST
    exit 1
end

function install_yay
    git clone https://aur.archlinux.org/yay.git "$BUIL_DIR/yay-used"
    cd "$BUILD_DIR/yay-used"
    makepkg
    sudo pacman -U --noconfirm yay-*.pkg.tar.*
    return $status
end

function download_pkgbuild
    yay -Ga --noconfirm --nopgpfetch $argv[1..-1]
    return $status
end

function install_packages
    sudo pacman -S --noconfirm --needed $argv[1..-1]
    return $status
end

function call_makepkg
    makepkg --skippgpcheck $argv[1..-1]
    return $status
end

function upload_file -a filename
    curl -v --user "$REPO_USER:$REPO_PASS" --upload-file "$filename" "$REPO_URL/$ARCH/"(basename $filename)
end

set MAKE_DEPENDS ()
set DEPENDS ()

function aur_get_make_depends -a package
    set MAKE_DEPENDS (string split ' ' (yay -Sai "$package" | grep -i "Make Deps" | cut -d':' -f2 | sed 's/^ //g'))
end

function private_get_make_depends -a package
    set MAKE_DEPENDS (string split ' ' (yay -Sai "$package" | grep -i "Make Deps" | cut -d':' -f2 | sed 's/^ //g'))
end

function aur_get_depends -a package
    set DEPENDS (string split ' ' (yay -Sai "$package" | grep -i "Depends" | cut -d':' -f2 | sed 's/^ //g'))
end

set PACKAGES (cat $PACKAGE_LIST)
# set AUR_PACKAGES (echo $PACKAGES | grep "^aur")

sudo pacman -Syu --noconfirm
# cp "$PACMAN_DB_NAME" "$BUILD_DIR/packages/"

if not yay -V
    install_yay
end

for package in $PACKAGES
    set splitted (string split ' ' (echo "$package"))
    "$splitted[1]_get_make_depends" $splitted[2]
    "$splitted[1]_get_depends" $splitted[2]

    install_packages $MAKE_DEPENDS
    # install_packages $DEPENDS

    cd build
    download_pkgbuild "$splitted[2]"
    cd "$splitted[2]"
    call_makepkg
    cp $BUILD_DIR/$splitted[2]/$splitted[2]*.pkg.tar.* "$BUILD_DIR/packages/"

    cd ../..
end

cd "$BUILD_DIR/packages"
ls -la
repo-add "$PACMAN_DB_NAME.db.tar.$COMPRESSION" $BUILD_DIR/packages/*.pkg.tar.*

for f in $BUILD_DIR/packages/*.pkg.tar.*
    upload_file "$f"
end

upload_file "$PACMAN_DB_NAME.db"
upload_file "$PACMAN_DB_NAME.db.tar.$COMPRESSION"
upload_file "$PACMAN_DB_NAME.files"
upload_file "$PACMAN_DB_NAME.files.tar.$COMPRESSION"