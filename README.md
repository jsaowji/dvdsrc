# Vapoursynth dvd source
namespace and api not final
WIP

# supoort 
video: 
mpeg1: ?
mpeg2: Y (NTCS and PAL should work)

audio: (not much tested, especally non stereo)
ac3: Y
lpcm: Y
other: not yet


## Usage examples
```
from pydvdcompanion import *

exa = st_pgc_full(DVD("<dvdpath>"),1,1)
exa.set_output()
#output0: exa.video
#output1..: exa.audios
```

# Build for linux/win under linux
- see github actions


# python wrappers
- put this folder into PYTHONPATH

# Dependencies
- put into bindings/ https://github.com/nlohmann/json/releases/download/v3.7.3/json.hpp
- zig-dev-bin 1:0.11.0_dev.3892
- libmpeg2
- libdvdread
- liba52

# Cache directory
HOME/.cache/dvdsrc

%userprofile%/.vsdvdsrc