# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg
using Base.BinaryPlatforms

const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "fancy_toys.jl"))
include(joinpath(YGGDRASIL_DIR, "platforms", "llvm.jl"))

name = "libclangex"
repo = "https://github.com/Gnimuc/ClangCompiler.jl.git"
version = v"0.2.0"

llvm_versions = [v"18.1.7"]

sources = [
    GitSource(repo, "7d599c3f41a183aae68e53f510915d64bbad3da7")
]

# Bash recipe for building across all platforms
script = raw"""
cd ClangCompiler.jl/deps/ClangExtra

if [[ "${bb_full_target}" == x86_64-apple-darwin* ]]; then
    # LLVM 15+ requires macOS SDK 10.14.
    pushd $WORKSPACE/srcdir/MacOSX10.*.sdk
    rm -rf /opt/${target}/${target}/sys-root/System
    cp -ra usr/* "/opt/${target}/${target}/sys-root/usr/."
    cp -ra System "/opt/${target}/${target}/sys-root/."
    export MACOSX_DEPLOYMENT_TARGET=10.14
    popd
fi

mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
     -DLLVM_DIR=${prefix}/lib/cmake/llvm \
     -DClang_DIR=${prefix}/lib/cmake/clang \
     -DCMAKE_BUILD_TYPE=Release
make -j${nproc}
make install
install_license ../COPYRIGHT ../LICENSE-APACHE ../LICENSE-MIT
"""

augment_platform_block = """
    using Base.BinaryPlatforms

    $(LLVM.augment)

    function augment_platform!(platform::Platform)
        augment_llvm!(platform)
    end"""

# determine exactly which tarballs we should build
builds = []
for llvm_version in llvm_versions, llvm_assertions in (false, true)
    # Dependencies that must be installed before this package can be built
    llvm_name = llvm_assertions ? "LLVM_full_assert_jll" : "LLVM_full_jll"
    dependencies = [
        RuntimeDependency("Clang_jll"),
        BuildDependency(PackageSpec(name=llvm_name, version=llvm_version))
    ]

    # The products that we will ensure are always built
    products = Product[
        # Clang_jll doesn't dlopen the library we depend on:
        # https://github.com/JuliaPackaging/Yggdrasil/blob/7e15aedbaca12e9c79cd1415fd03129665bcfeff/L/LLVM/common.jl#L517-L518
        # so loading the library will always fail. We fix this in ClangCompiler.jl
        LibraryProduct("libclangex", :libclangex, dont_dlopen=true),
    ]

    # These are the platforms we will build for by default, unless further
    # platforms are passed in on the command line
    platforms = expand_cxxstring_abis(supported_platforms())
    # disable riscv64
    filter!(p -> arch(p) != "riscv64", platforms)
    # disable aarch64 freebsd
    filter!(p -> !(Sys.isfreebsd(p) && arch(p) == "aarch64"), platforms)
    # disable i686-linux-musl
    filter!(p -> !(arch(p) == "i686" && libc(p) == "musl"), platforms)

    for platform in platforms
        augmented_platform = deepcopy(platform)
        augmented_platform[LLVM.platform_name] = LLVM.platform(llvm_version, llvm_assertions)

        platform_sources = BinaryBuilder.AbstractSource[sources...]
        if Sys.isapple(platform)
            push!(platform_sources,
                  ArchiveSource("https://github.com/phracker/MacOSX-SDKs/releases/download/10.15/MacOSX10.14.sdk.tar.xz",
                                "0f03869f72df8705b832910517b47dd5b79eb4e160512602f593ed243b28715f"))
        end

        should_build_platform(triplet(augmented_platform)) || continue
        push!(builds, (;
            dependencies, products, sources=platform_sources,
            platforms=[augmented_platform],
        ))
    end
end

# don't allow `build_tarballs` to override platform selection based on ARGS.
# we handle that ourselves by calling `should_build_platform`
non_platform_ARGS = filter(arg -> startswith(arg, "--"), ARGS)

# `--register` should only be passed to the latest `build_tarballs` invocation
non_reg_ARGS = filter(arg -> arg != "--register", non_platform_ARGS)

for (i,build) in enumerate(builds)
    build_tarballs(i == lastindex(builds) ? non_platform_ARGS : non_reg_ARGS,
                   name, version, build.sources, script,
                   build.platforms, build.products, build.dependencies;
                   preferred_gcc_version=v"10", julia_compat="1.12",
                   augment_platform_block)
end

# bump
