# Vapoursynth dvd source
namespace and api not final


## dvd
    dvdsrc.Full(str dvd, int vts, int domain)

- dvd: Path to dvd. ISO or parent of VIDEO_TS

- vts: Title set number VTS_XX_..

- domain:
    - 0 = menu vobs (VTS_XX_0)
    - 1 = titlevobs (VTS_XX_1,VTS_XX_2,...)

## m2v
    dvdsrc.M2V(str path)

- dvd: Path to dvd. ISO or parent of VIDEO_TS


# Build for linux/win under linux
```
# build deps windows setup bindings
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe

# setup bindings
zig build
```


# pydvdcompanion
- put this folder into PYTHONPATH
- create symlink for vspreview_dvd into vspreview plugin path

# Dependencies
- put into bindings/ https://github.com/nlohmann/json/releases/download/v3.7.3/json.hpp
- zig-dev-bin 1:0.11.0_dev.3892
- libmpeg2
- libdvdread


# Cache directory
HOME/.cache/dvdsrc

%userprofile%/.vsdvdsrc