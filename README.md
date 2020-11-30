# Contents of this Repository
This repository contains a single fish file which is used to build the packages listed in the package-list file and then create/update a pacman database and finally pushing it to nexus-oss.

## Script file
The options this script file provides:

* ``-b/--build-dir`` The directory yay will build the packages in
* ``-p/--package-list`` The path of the file containing the list of packages to build
* ``-n/--db-name`` The path of the database without the file suffix
* ``-c/--compression`` The compression to use for the database, given as a tar suffix (xz for xzlib)
* ``-a/--arch`` The architecture of the packages which should be built