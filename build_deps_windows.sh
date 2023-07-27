#!/usr/bin/env bash

wget -nc https://libmpeg2.sourceforge.io/files/libmpeg2-0.5.1.tar.gz
wget -nc https://codeload.github.com/vapoursynth/vapoursynth/tar.gz/refs/tags/R62
wget -nc http://download.videolan.org/pub/videolan/libdvdread/last/libdvdread-6.1.3.tar.bz2

rm -rf libmpeg2-0.5.1
rm -rf libdvdread-6.1.3
rm -rf libdvdread-6.1.3
rm -rf vapoursynth-R62

tar -xvf libdvdread-6.1.3.tar.bz2
tar -xvf libmpeg2-0.5.1.tar.gz
tar -xvf R62

cd libmpeg2-0.5.1
AR="zig ar" RANLIB="zig ranlib" CC="zig cc --target=x86_64-windows -D__CRT__NO_INLINE -mno-ms-bitfields" ./configure --host="x86_64-windows" --disable-sdl --disable-directx && make
cd ..

cd libdvdread-6.1.3
AR="zig ar" RANLIB="zig ranlib" CC="zig cc --target=x86_64-windows -D__CRT__NO_INLINE -mno-ms-bitfields" ./configure --host="x86_64-windows" && make
cd ..

cp libmpeg2-0.5.1/libmpeg2/.libs/libmpeg2.a .
cp libdvdread-6.1.3/.libs/libdvdread.a .

mv vapoursynth-R62/include/ vapoursynth-R62/lolol/
mkdir vapoursynth-R62/include/
mkdir vapoursynth-R62/include/vapoursynth
mv vapoursynth-R62/lolol/*.h vapoursynth-R62/include/vapoursynth