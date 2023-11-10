# Vapoursynth dvd source

deprecated use dvdsrc2 with vs-source instead.

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
