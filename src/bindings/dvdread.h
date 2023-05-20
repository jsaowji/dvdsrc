//zig translate-c src/bindings/dvdread.h $(pkg-config --cflags-only-I --keep-system-cflags dvdread) > src/bindings/dvdread.zig

#include <dvdread/dvd_reader.h>
#include <dvdread/ifo_read.h>
#include <dvdread/ifo_print.h>
