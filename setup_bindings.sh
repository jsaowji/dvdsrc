#!/usr/bin/env bash

zig translate-c src/bindings/vapoursynth.h $(pkg-config --cflags-only-I --keep-system-cflags vapoursynth) > src/bindings/vapoursynth.zig
zig translate-c src/bindings/mpeg2.h $(pkg-config --cflags-only-I --keep-system-cflags libmpeg2) > src/bindings/mpeg2.zig
zig translate-c src/bindings/a52.h $(pkg-config --cflags-only-I --keep-system-cflags liba52) > src/bindings/a52.zig
#zig translate-c src/bindings/dvdread.h $(pkg-config --cflags-only-I --keep-system-cflags dvdread) > src/bindings/dvdread.zig

sed -i '/registerFunction/ { c \
registerFunction: ?*const fn ([*c]const u8, [*c]const u8, [*c]const u8, ?*const anyopaque, ?*anyopaque, ?*VSPlugin) callconv(.C) c_int,
}' src/bindings/vapoursynth.zig