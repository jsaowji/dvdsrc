const vs = @import("bindings/vapoursynth.zig");
const std = @import("std");

const fullfilter = @import("vs/fullfilter.zig");
const fullac3filter = @import("vs/fullac3.zig");
const fulllpcmfilter = @import("vs/fulllpcm.zig");
const ifotofile = @import("vs/ifotofile.zig");
const m2vfilter = @import("vs/m2vfilter.zig");
const vobtofile = @import("vs/vobtofile.zig");
const ac3filter = @import("vs/ac3filter.zig");
const jsonfilter = @import("vs/jsonfilter.zig");
const vobget = @import("vs/vobget.zig");
const vobto = @import("vs/cutvob.zig");
const rawac3 = @import("vs/rawac3.zig");

export fn VapourSynthPluginInit2(plugin: ?*vs.VSPlugin, vspapi: *const vs.VSPLUGINAPI) void {
    _ = vspapi.configPlugin.?("com.jsaowji.dvdsrc", "dvdsrc", "VapourSynth DVD source", vs.VS_MAKE_VERSION(1, 0), vs.VAPOURSYNTH_API_VERSION, 0, plugin);

    _ = vspapi.registerFunction.?("Json", "dvd:data", "json:data;", jsonfilter.JsonFilter.jsonFilterCreate, vs.NULL, plugin);

    _ = vspapi.registerFunction.?("CutVob", "dvd:data;vts:int;domain:int;sectors:int[]", "clip:vnode;", vobto.VobFilter.vobfilterCreate, vs.NULL, plugin);

    _ = vspapi.registerFunction.?("FullM2V", "dvd:data;vts:int;domain:int;sectors:int[]", "clip:vnode;", fullfilter.FullFilter.fullFilterCreate, vs.NULL, plugin);
    _ = vspapi.registerFunction.?("FullAC3", "dvd:data;vts:int;domain:int;sectors:int[];audioidx:int", "clip:anode;", fullac3filter.FullAc3Filter.fullAc3FilterCreate, vs.NULL, plugin);
    _ = vspapi.registerFunction.?("FullLPCM", "dvd:data;vts:int;domain:int;sectors:int[];audioidx:int", "clip:anode;", fulllpcmfilter.FullLPCMFilter.fullLPCMFilterCreate, vs.NULL, plugin);
    _ = vspapi.registerFunction.?("RawAc3", "dvd:data;vts:int;domain:int;sectors:int[];audioidx:int", "clip:vnode;", rawac3.RawAc3Filter.rawAc3filterCreate, vs.NULL, plugin);
    _ = vspapi.registerFunction.?("VobGet", "dvd:data;vts:int;domain:int;sectors:int[]", "clip:vnode;", vobget.VobGetFilter.VobGetfilterCreate, vs.NULL, plugin);

    _ = vspapi.registerFunction.?("M2V", "path:data", "clip:vnode;", m2vfilter.M2vFilter.filterCreate, vs.NULL, plugin);
    _ = vspapi.registerFunction.?("AC3", "path:data", "clip:anode;", ac3filter.Ac3Filter.ac3filterCreate, vs.NULL, plugin);

    _ = vspapi.registerFunction.?("VobToFile", "dvd:data;vts:int;domain:int;sectors:int[];outfile:data;novideo:int", "", vobtofile.VobToFile.vobtoFileCreate, vs.NULL, plugin);
    _ = vspapi.registerFunction.?("IfoToFile", "dvd:data;ifo:int;outfile:data", "", ifotofile.IfoToFile.ifoToFileCreate, vs.NULL, plugin);
}
