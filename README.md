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

# How to build
```
zig translate-c src/bindings/vapoursynth.h $(pkg-config --cflags-only-I --keep-system-cflags vapoursynth) > src/bindings/vapoursynth.zig
zig translate-c src/bindings/mpeg2.h $(pkg-config --cflags-only-I --keep-system-cflags libmpeg2) > src/bindings/mpeg2.zig
zig translate-c src/bindings/dvdread.h $(pkg-config --cflags-only-I --keep-system-cflags dvdread) > src/bindings/dvdread.zig
zig build
```


# TODO
- error handling
- dvd aware parsing like angel and stuff
- make sure nothing missdecodes
- demux audio
- export chapters
- cut on title/chapter/pgc/cell/bytes/gops ????

