using BinaryBuilder

name = "JpegTurbo"
version = v"2.1.2"

# Collection of sources required to build Ogg
sources = [
    ArchiveSource("https://github.com/libjpeg-turbo/libjpeg-turbo/archive/$(version).tar.gz",
                  "e7fdc8a255c45bc8fbd9aa11c1a49c23092fcd7379296aeaeb14d3343a3d1bed"),
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/libjpeg-turbo-*/

mkdir build
cd build

cmake .. -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TARGET_TOOLCHAIN}"
make -j${nproc}
make install
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = supported_platforms()

# The products that we will ensure are always built
products = [
    LibraryProduct("libjpeg", :libjpeg),
    LibraryProduct("libturbojpeg", :libturbojpeg),
    ExecutableProduct("cjpeg", :cjpeg),
    ExecutableProduct("djpeg", :djpeg),
    ExecutableProduct("jpegtran", :jpegtran),
]

# Dependencies that must be installed before this package can be built
dependencies = [
    # Avengers; ASSEMBLE!
    HostBuildDependency("YASM_jll"),
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.6")
