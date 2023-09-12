#!/usr/bin/env bash

#zig translate-c src/bindings/dvdread.h -Dtarget=x86_64-windows -Ilibdvdread-6.1.3/src -lc > src/bindings/dvdread.zig
zig translate-c src/bindings/vapoursynth.h -Dtarget=x86_64-windows -Ivapoursynth-R62/include -lc  > src/bindings/vapoursynth.zig
zig translate-c src/bindings/mpeg2.h -Dtarget=x86_64-windows -Ilibmpeg2-0.5.1/include > src/bindings/mpeg2.zig
zig translate-c src/bindings/a52.h -Dtarget=x86_64-windows -Ia52dec-c388f3b6d911c246e0b2a7b2c436c3de2e79c74d/include > src/bindings/a52.zig


sed -i '/registerFunction/ { c \
registerFunction: ?*const fn ([*c]const u8, [*c]const u8, [*c]const u8, ?*const anyopaque, ?*anyopaque, ?*VSPlugin) callconv(.C) c_int,
}' src/bindings/vapoursynth.zig
