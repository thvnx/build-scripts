#!/usr/bin/env bash
set -eu

## Set these for using specific revision
SHA1_LLVM=${SHA1_LLVM:-HEAD}
SHA1_BINUTILS=${SHA1_BINUTILS:-HEAD}
SHA1_NEWLIB=${SHA1_NEWLIB:-HEAD}

TARGET=${TARGET:-kvx-elf}
TRIPLE=kvx-kalray-osp
PREFIX=$(realpath "$1")

PARALLEL_JOBS=-j6


mkdir -p "$PREFIX"
export PATH="$PREFIX/bin:$PATH"

function git_clone() {
    local repo=$1
    local sha1=$2
    local branch=$3

    if [[ "${branch}" == "-" ]];
    then
        branch=""
    else
        branch="-b ${branch}"
    fi

    repo_dir=$(basename "${repo}" ".git")
    echo "Cloning ${repo} (${repo_dir}) sha1: ${sha1}"
    if [ -d "${repo_dir}" ]; then
        (
            cd "${repo_dir}"
            git fetch
        )
    else
	      git clone ${branch} "${repo}"
    fi

    if [[ ! -z "${sha1}" ]]
    then
        (
            cd "${repo_dir}"
            git reset --hard "${sha1}"
        )
    fi
}

git_clone https://github.com/kalray/gdb-binutils.git "${SHA1_BINUTILS}" -
git_clone https://github.com/kalray/newlib.git "${SHA1_NEWLIB}" coolidge
git_clone https://github.com/kalray/llvm-project "${SHA1_LLVM}" kalray/12.x/kvx-12.0.0

mkdir -p build-binutils
pushd build-binutils
../gdb-binutils/configure \
    --prefix="$PREFIX" \
    --target="$TARGET" \
    --disable-initfini-array  \
    --disable-gdb \
    --without-gdb \
    --disable-werror   \
    --with-expat=yes \
    --with-babeltrace=no \
    --with-bugurl=no

make all "$PARALLEL_JOBS" > /dev/null
make install
popd

mkdir -p build-llvm
pushd build-llvm

cmake -G Ninja -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
      -DLLVM_TARGETS_TO_BUILD=KVX -DLLVM_DEFAULT_TARGET_TRIPLE=$TRIPLE \
      -DCMAKE_BUILD_TYPE=Release -DLLVM_INCLUDE_EXAMPLES=False \
      -DLLVM_PARALLEL_LINK_JOBS=2 -DLLVM_USE_LINKER=gold \
      -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_INSTALL_PREFIX=$PREFIX \
      ../llvm-project/llvm

cmake --build . --target install
popd

mkdir -p build-newlib
pushd build-newlib
CC_FOR_TARGET=clang \
CFLAGS_FOR_TARGET=" --target=kvx-osp --sysroot=$PREFIX" \
AS_FOR_TARGET=${TARGET}-as \
LD_FOR_TARGET=${TARGET}-ld \
RANLIB_FOR_TARGET=${TARGET}-ranlib \
AR_FOR_TARGET=${TARGET}-ar \
    ../newlib/configure \
    --with-sysroot="$PREFIX" \
    --target=kvx-llvmosp \
    --prefix="$PREFIX" \
    --enable-multilib \
    --enable-target-optspace=no \
    --enable-initfini-array \
    --enable-newlib-io-c99-formats \
    --enable-newlib-multithread

make all "$PARALLEL_JOBS" > /dev/null
make install
popd

mkdir -p build-crt
pushd build-crt
# TODO
popd

echo "Finished"

