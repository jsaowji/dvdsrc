# Vapoursynth dvd source
namespace and api not final


## Usage
    dvdsrc.Full(str dvd, int vts, int domain)

- dvd: Path to dvd. ISO or parent of VIDEO_TS

- vts: Title set number VTS_X_..

- domain:
    - 0 = menu vobs (VTS_XX_0)
    - 1 = titlevobs (VTS_XX_1,VTS_XX_2,...)


# Dependencies
- zig-dev-bin 1:0.11.0_dev
- libmpeg2
- libdvdread


# Cache directory
HOME/.cache/dvdsrc

%userprofile%/.vsdvdsrc


# How to build linux
```
zig translate-c src/bindings/vapoursynth.h $(pkg-config --cflags-only-I --keep-system-cflags vapoursynth) > src/bindings/vapoursynth.zig
zig translate-c src/bindings/mpeg2.h $(pkg-config --cflags-only-I --keep-system-cflags libmpeg2) > src/bindings/mpeg2.zig
zig translate-c src/bindings/dvdread.h $(pkg-config --cflags-only-I --keep-system-cflags dvdread) > src/bindings/dvdread.zig
zig build
```


# How to cross compile for windows on linux
```
wget https://libmpeg2.sourceforge.io/files/libmpeg2-0.5.1.tar.gz
wget https://codeload.github.com/vapoursynth/vapoursynth/tar.gz/refs/tags/R62
wget http://download.videolan.org/pub/videolan/libdvdread/last/libdvdread-6.1.3.tar.bz2

rm -rf libmpeg2-0.5.1
rm -rf libdvdread-6.1.3
rm -rf libdvdread-6.1.3

tar -xvf libdvdread-6.1.3.tar.bz2
tar -xvf libmpeg2-0.5.1.tar.gz
tar -xvf R62

cd libmpeg2-0.5.1
AR="zig ar" RANLIB="zig ranlib" CC="zig cc --target=x86_64-windows -D__CRT__NO_INLINE" ./configure --host="x86_64-windows" --disable-sdl --disable-directx && make
cd ..

cd libdvdread-6.1.3
AR="zig ar" RANLIB="zig ranlib" CC="zig cc --target=x86_64-windows -D__CRT__NO_INLINE" ./configure --host="x86_64-windows" && make
cd ..

cp libmpeg2-0.5.1/libmpeg2/.libs/libmpeg2.a dvdsrc
cp libdvdread-6.1.3/.libs/libdvdread.a dvdsrc
cd dvdsrc

zig translate-c src/bindings/dvdread.h -Dtarget=x86_64-windows -I../libdvdread-6.1.3/src -lc > src/bindings/dvdread.zig
zig translate-c src/bindings/vapoursynth.h -Dtarget=x86_64-windows -I../vapoursynth-R62/include -lc  > src/bindings/vapoursynth.zig
zig translate-c src/bindings/mpeg2.h -Dtarget=x86_64-windows -I../libmpeg2-0.5.1/include > src/bindings/mpeg2.zig

zig build -Dtarget=x86_64-windows
```


# How to build on windows
No idea tbh.



# TODO
- error handling
- dvd aware parsing like angel and stuff
- make sure nothing missdecodes
- demux audio
- export chapters
- cut on title/chapter/pgc/cell/bytes/gops ????

