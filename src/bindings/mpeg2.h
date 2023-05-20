//zig translate-c src/bindings/mpeg2.h $(pkg-config --cflags-only-I --keep-system-cflags libmpeg2) > src/bindings/mpeg2.zig

#include <stdint.h>
#include <mpeg2.h>