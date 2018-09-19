#!/bin/bash
HOST=x86_64-w64-mingw32
CXX=x86_64-w64-mingw32-g++-posix
CC=x86_64-w64-mingw32-gcc-posix
PREFIX="$(pwd)/depends/$HOST"


cd depends/ && make HOST=$HOST V=1 && cd ../

./autogen.sh

CXXFLAGS="-DPTW32_STATIC_LIB -DCURVE_ALT_BN128 -fopenmp -pthread" CONFIG_SITE=$PWD/depends/x86_64-w64-mingw32/share/config.site  ./configure --prefix=/  --enable-static --disable-shared  --disable-zmq --disable-rust  --disable-tests  --disable-gui-tests --disable-bench
CC="${CC}" CXX="${CXX}" make V=1 -j3
