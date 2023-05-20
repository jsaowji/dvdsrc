//zig translate-c src/bindings/vapoursynth.h $(pkg-config --cflags-only-I --keep-system-cflags vapoursynth) > src/bindings/vapoursynth.zig

#include <vapoursynth/VSConstants4.h>
#include <vapoursynth/VapourSynth4.h>
#include <vapoursynth/VSScript4.h>
#include <vapoursynth/VSHelper4.h>