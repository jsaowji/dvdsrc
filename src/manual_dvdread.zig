pub const struct___va_list_tag = extern struct {
    gp_offset: c_uint,
    fp_offset: c_uint,
    overflow_arg_area: ?*anyopaque,
    reg_save_area: ?*anyopaque,
};
pub const __off_t = c_long;
pub const off_t = __off_t;

pub const struct_dvd_reader_s = opaque {};
pub const dvd_reader_t = struct_dvd_reader_s;
pub const struct_dvd_reader_device_s = opaque {};
pub const dvd_reader_device_t = struct_dvd_reader_device_s;
pub const struct_dvd_file_s = opaque {};
pub const dvd_file_t = struct_dvd_file_s;
pub const struct_dvd_reader_stream_cb = extern struct {
    pf_seek: ?*const fn (?*anyopaque, u64) callconv(.C) c_int,
    pf_read: ?*const fn (?*anyopaque, ?*anyopaque, c_int) callconv(.C) c_int,
    pf_readv: ?*const fn (?*anyopaque, ?*anyopaque, c_int) callconv(.C) c_int,
};
pub const dvd_reader_stream_cb = struct_dvd_reader_stream_cb;

pub const DVD_LOGGER_LEVEL_INFO: c_int = 0;
pub const DVD_LOGGER_LEVEL_ERROR: c_int = 1;
pub const DVD_LOGGER_LEVEL_WARN: c_int = 2;
pub const DVD_LOGGER_LEVEL_DEBUG: c_int = 3;
pub const dvd_logger_level_t = c_uint;

pub const DVD_READ_INFO_FILE: c_int = 0;
pub const DVD_READ_INFO_BACKUP_FILE: c_int = 1;
pub const DVD_READ_MENU_VOBS: c_int = 2;
pub const DVD_READ_TITLE_VOBS: c_int = 3;
pub const dvd_read_domain_t = c_uint;

pub const dvd_logger_cb = extern struct {
    pf_log: ?*const fn (?*anyopaque, dvd_logger_level_t, [*c]const u8, [*c]struct___va_list_tag) callconv(.C) void,
};
pub const dvd_stat_t = extern struct {
    size: off_t,
    nr_parts: c_int,
    parts_size: [9]off_t,
};
pub extern fn DVDOpen([*c]const u8) ?*dvd_reader_t;
pub extern fn DVDOpenStream(?*anyopaque, [*c]dvd_reader_stream_cb) ?*dvd_reader_t;
pub extern fn DVDOpen2(?*anyopaque, [*c]const dvd_logger_cb, [*c]const u8) ?*dvd_reader_t;
pub extern fn DVDOpenStream2(?*anyopaque, [*c]const dvd_logger_cb, [*c]dvd_reader_stream_cb) ?*dvd_reader_t;
pub extern fn DVDClose(?*dvd_reader_t) void;

pub extern fn DVDFileStat(?*dvd_reader_t, c_int, dvd_read_domain_t, [*c]dvd_stat_t) c_int;
pub extern fn DVDOpenFile(?*dvd_reader_t, c_int, dvd_read_domain_t) ?*dvd_file_t;
pub extern fn DVDCloseFile(?*dvd_file_t) void;
pub extern fn DVDReadBlocks(?*dvd_file_t, c_int, usize, [*c]u8) isize;
pub extern fn DVDFileSeek(?*dvd_file_t, i32) i32;
pub extern fn DVDReadBytes(?*dvd_file_t, ?*anyopaque, usize) isize;
pub extern fn DVDFileSize(?*dvd_file_t) isize;
pub extern fn DVDDiscID(?*dvd_reader_t, [*c]u8) c_int;
pub extern fn DVDUDFVolumeInfo(?*dvd_reader_t, [*c]u8, c_uint, [*c]u8, c_uint) c_int;
pub extern fn DVDFileSeekForce(?*dvd_file_t, offset: c_int, force_size: c_int) c_int;
pub extern fn DVDISOVolumeInfo(?*dvd_reader_t, [*c]u8, c_uint, [*c]u8, c_uint) c_int;
pub extern fn DVDUDFCacheLevel(?*dvd_reader_t, c_int) c_int;
pub const dvd_time_t = extern struct {
    hour: u8 align(1),
    minute: u8 align(1),
    second: u8 align(1),
    frame_u: u8 align(1),
};
pub const vm_cmd_t = extern struct {
    bytes: [8]u8 align(1),
}; // /usr/include/dvdread/ifo_types.h:82:17: warning: struct demoted to opaque type - has bitfield

pub const video_attr_t = packed struct {
    mpeg_version: u2,
    video_format: u2,
    display_aspect_ratio: u2,
    permitted_df: u2,

    line21_cc_1: bool,
    line21_cc_2: bool,
    unknown1: bool,
    bit_rate: bool,

    picture_size: u2,
    letterboxed: bool,
    film_mode: bool,

    comptime {
        @import("std").debug.assert(@sizeOf(@This()) == @sizeOf(u16));
        @import("std").debug.assert(@bitSizeOf(@This()) == @bitSizeOf(u16));
    }
};

pub const audio_attr_t = packed struct {
    audio_format: u3,
    multichannel_extension: u1,
    lang_type: u2,
    application_mode: u2,

    quantization: u2,
    sample_frequency: u2,
    unknown1: u1,
    channels: u3,
    lang_code: u16,
    lang_extension: u8,
    code_extension: u8,
    unknown3: u8,
    appinfo: u8,
};

pub const multichannel_ext_t = extern struct {
    a: [24]u8,
};

pub const subp_attr_t = extern struct {
    //code_mode: u3,
    //zero1: u3,
    //typeu: u2,
    flg0: u8,

    zero2: u8,
    lang_code: u16,
    lang_extension: u8,
    code_extension: u8,
};

pub const pgc_command_tbl_t = extern struct {
    nr_of_pre: u16 align(1),
    nr_of_post: u16 align(1),
    nr_of_cell: u16 align(1),
    last_byte: u16 align(1),
    pre_cmds: [*c]vm_cmd_t align(1),
    post_cmds: [*c]vm_cmd_t align(1),
    cell_cmds: [*c]vm_cmd_t align(1),
};
pub const pgc_program_map_t = u8;

pub const cell_playback_t = extern struct {
    //block_mode: u2,
    //block_type: u2,
    //seamless_play: u1,
    //interleaved: u1,
    //stc_discontinuity: u1,
    //seamless_angle: u1,
    //zero_1: u1,
    //playback_mode: u1,
    //restricted: u1,
    //cell_type: u5,
    flg0: u8,
    flg1: u8,

    still_time: u8,
    cell_cmd_nr: u8,
    playback_time: dvd_time_t,
    first_sector: u32,
    first_ilvu_end_sector: u32,
    last_vobu_start_sector: u32,
    last_sector: u32,
};

pub const cell_position_t = extern struct {
    vob_id_nr: u16 align(1),
    zero_1: u8 align(1),
    cell_nr: u8 align(1),
};

pub const user_ops_t = extern struct {
    a: u32,
};

pub const pgc_t = extern struct {
    zero_1: u16 align(1),
    nr_of_programs: u8 align(1),
    nr_of_cells: u8 align(1),
    playback_time: dvd_time_t align(1),
    prohibited_ops: user_ops_t align(1),
    audio_control: [8]u16 align(1),
    subp_control: [32]u32 align(1),
    next_pgc_nr: u16 align(1),
    prev_pgc_nr: u16 align(1),
    goup_pgc_nr: u16 align(1),
    pg_playback_mode: u8 align(1),
    still_time: u8 align(1),
    palette: [16]u32 align(1),
    command_tbl_offset: u16 align(1),
    program_map_offset: u16 align(1),
    cell_playback_offset: u16 align(1),
    cell_position_offset: u16 align(1),
    command_tbl: [*c]pgc_command_tbl_t align(1),
    program_map: [*c]pgc_program_map_t align(1),
    cell_playback: [*c]cell_playback_t align(1),
    cell_position: [*c]cell_position_t align(1),
    ref_count: c_int align(1),
};

pub const pgci_srp_t = extern struct {
    entry_id: u8,
    //block_mode: u2,
    //block_type: u2,
    //zero_1: u4,
    flg0: u8,

    ptl_id_mask: u16,
    pgc_start_byte: u32,
    pgc: [*c]pgc_t,

    comptime {
        @import("std").debug.assert(@bitSizeOf(@This()) == 8 * (8 + 8));
    }
};

pub const pgcit_t = extern struct {
    nr_of_pgci_srp: u16 align(1),
    zero_1: u16 align(1),
    last_byte: u32 align(1),
    pgci_srp: [*c]pgci_srp_t align(1),
    ref_count: c_int align(1),
};
pub const pgci_lu_t = extern struct {
    lang_code: u16 align(1),
    lang_extension: u8 align(1),
    exists: u8 align(1),
    lang_start_byte: u32 align(1),
    pgcit: [*c]pgcit_t align(1),
};
pub const pgci_ut_t = extern struct {
    nr_of_lus: u16 align(1),
    zero_1: u16 align(1),
    last_byte: u32 align(1),
    lu: [*c]pgci_lu_t align(1),
};
pub const cell_adr_t = extern struct {
    vob_id: u16 align(1),
    cell_id: u8 align(1),
    zero_1: u8 align(1),
    start_sector: u32 align(1),
    last_sector: u32 align(1),
};
pub const c_adt_t = extern struct {
    nr_of_vobs: u16 align(1),
    zero_1: u16 align(1),
    last_byte: u32 align(1),
    cell_adr_table: [*c]cell_adr_t align(1),
};
pub const vobu_admap_t = extern struct {
    last_byte: u32 align(1),
    vobu_start_sectors: [*c]u32 align(1),
};
pub const vmgi_mat_t = extern struct {
    vmg_identifier: [12]u8 align(1),
    vmg_last_sector: u32 align(1),
    zero_1: [12]u8 align(1),
    vmgi_last_sector: u32 align(1),
    zero_2: u8 align(1),
    specification_version: u8 align(1),
    vmg_category: u32 align(1),
    vmg_nr_of_volumes: u16 align(1),
    vmg_this_volume_nr: u16 align(1),
    disc_side: u8 align(1),
    zero_3: [19]u8 align(1),
    vmg_nr_of_title_sets: u16 align(1),
    provider_identifier: [32]u8 align(1),
    vmg_pos_code: u64 align(1),
    zero_4: [24]u8 align(1),
    vmgi_last_byte: u32 align(1),
    first_play_pgc: u32 align(1),
    zero_5: [56]u8 align(1),
    vmgm_vobs: u32 align(1),
    tt_srpt: u32 align(1),
    vmgm_pgci_ut: u32 align(1),
    ptl_mait: u32 align(1),
    vts_atrt: u32 align(1),
    txtdt_mgi: u32 align(1),
    vmgm_c_adt: u32 align(1),
    vmgm_vobu_admap: u32 align(1),
    zero_6: [32]u8 align(1),
    vmgm_video_attr: video_attr_t align(1),
    zero_7: u8 align(1),
    nr_of_vmgm_audio_streams: u8 align(1),
    vmgm_audio_attr: audio_attr_t align(1),
    zero_8: [7]audio_attr_t align(1),
    zero_9: [17]u8 align(1),
    nr_of_vmgm_subp_streams: u8 align(1),
    vmgm_subp_attr: subp_attr_t align(1),
    zero_10: [27]subp_attr_t align(1),
};

pub const playback_type_t = packed struct {
    a: u8,
};

pub const title_info_t = extern struct {
    pb_ty: playback_type_t align(1),
    nr_of_angles: u8 align(1),
    nr_of_ptts: u16 align(1),
    parental_id: u16 align(1),
    title_set_nr: u8 align(1),
    vts_ttn: u8 align(1),
    title_set_sector: u32 align(1),
};
pub const tt_srpt_t = extern struct {
    nr_of_srpts: u16 align(1),
    zero_1: u16 align(1),
    last_byte: u32 align(1),
    title: ?*title_info_t align(1),
};
pub const pf_level_t = [8]u16;
pub const ptl_mait_country_t = extern struct {
    country_code: u16 align(1),
    zero_1: u16 align(1),
    pf_ptl_mai_start_byte: u16 align(1),
    zero_2: u16 align(1),
    pf_ptl_mai: [*c]pf_level_t align(1),
};
pub const ptl_mait_t = extern struct {
    nr_of_countries: u16 align(1),
    nr_of_vtss: u16 align(1),
    last_byte: u32 align(1),
    countries: [*c]ptl_mait_country_t align(1),
};
pub const vts_attributes_t = extern struct {
    last_byte: u32 align(1),
    vts_cat: u32 align(1),
    vtsm_vobs_attr: video_attr_t align(1),
    zero_1: u8 align(1),
    nr_of_vtsm_audio_streams: u8 align(1),
    vtsm_audio_attr: audio_attr_t align(1),
    zero_2: [7]audio_attr_t align(1),
    zero_3: [16]u8 align(1),
    zero_4: u8 align(1),
    nr_of_vtsm_subp_streams: u8 align(1),
    vtsm_subp_attr: subp_attr_t align(1),
    zero_5: [27]subp_attr_t align(1),
    zero_6: [2]u8 align(1),
    vtstt_vobs_video_attr: video_attr_t align(1),
    zero_7: u8 align(1),
    nr_of_vtstt_audio_streams: u8 align(1),
    vtstt_audio_attr: [8]audio_attr_t align(1),
    zero_8: [16]u8 align(1),
    zero_9: u8 align(1),
    nr_of_vtstt_subp_streams: u8 align(1),
    vtstt_subp_attr: [32]subp_attr_t align(1),
};
pub const vts_atrt_t = extern struct {
    nr_of_vtss: u16 align(1),
    zero_1: u16 align(1),
    last_byte: u32 align(1),
    vts: ?*vts_attributes_t align(1),
    vts_atrt_offsets: [*c]u32 align(1),
};
pub const txtdt_t = extern struct {
    last_byte: u32 align(1),
    offsets: [100]u16 align(1),
};
pub const txtdt_lu_t = extern struct {
    lang_code: u16 align(1),
    zero_1: u8 align(1),
    char_set: u8 align(1),
    txtdt_start_byte: u32 align(1),
    txtdt: [*c]txtdt_t align(1),
};
pub const txtdt_mgi_t = extern struct {
    disc_name: [12]u8 align(1),
    unknown1: u16 align(1),
    nr_of_language_units: u16 align(1),
    last_byte: u32 align(1),
    lu: [*c]txtdt_lu_t align(1),
};
pub const vtsi_mat_t = extern struct {
    vts_identifier: [12]u8 align(1),
    vts_last_sector: u32 align(1),
    zero_1: [12]u8 align(1),
    vtsi_last_sector: u32 align(1),
    zero_2: u8 align(1),
    specification_version: u8 align(1),
    vts_category: u32 align(1),
    zero_3: u16 align(1),
    zero_4: u16 align(1),
    zero_5: u8 align(1),
    zero_6: [19]u8 align(1),
    zero_7: u16 align(1),
    zero_8: [32]u8 align(1),
    zero_9: u64 align(1),
    zero_10: [24]u8 align(1),
    vtsi_last_byte: u32 align(1),
    zero_11: u32 align(1),
    zero_12: [56]u8 align(1),
    vtsm_vobs: u32 align(1),
    vtstt_vobs: u32 align(1),
    vts_ptt_srpt: u32 align(1),
    vts_pgcit: u32 align(1),
    vtsm_pgci_ut: u32 align(1),
    vts_tmapt: u32 align(1),
    vtsm_c_adt: u32 align(1),
    vtsm_vobu_admap: u32 align(1),
    vts_c_adt: u32 align(1),
    vts_vobu_admap: u32 align(1),
    zero_13: [24]u8 align(1),
    vtsm_video_attr: video_attr_t align(1),
    zero_14: u8 align(1),
    nr_of_vtsm_audio_streams: u8 align(1),
    vtsm_audio_attr: audio_attr_t align(1),
    zero_15: [7]audio_attr_t align(1),
    zero_16: [17]u8 align(1),
    nr_of_vtsm_subp_streams: u8 align(1),
    vtsm_subp_attr: subp_attr_t align(1),
    zero_17: [27]subp_attr_t align(1),
    zero_18: [2]u8 align(1),
    vts_video_attr: video_attr_t align(1),
    zero_19: u8 align(1),
    nr_of_vts_audio_streams: u8 align(1),
    vts_audio_attr: [8]audio_attr_t align(1),
    zero_20: [17]u8 align(1),
    nr_of_vts_subp_streams: u8 align(1),
    vts_subp_attr: [32]subp_attr_t align(1),
    zero_21: u16 align(1),
    vts_mu_audio_attr: [8]multichannel_ext_t align(1),
};
pub const ptt_info_t = extern struct {
    pgcn: u16 align(1),
    pgn: u16 align(1),
};
pub const ttu_t = extern struct {
    nr_of_ptts: u16 align(1),
    ptt: [*c]ptt_info_t align(1),
};
pub const vts_ptt_srpt_t = extern struct {
    nr_of_srpts: u16 align(1),
    zero_1: u16 align(1),
    last_byte: u32 align(1),
    title: [*c]ttu_t align(1),
    ttu_offset: [*c]u32 align(1),
};
pub const map_ent_t = u32;

pub const vts_tmap_t = extern struct {
    tmu: u8 align(1),
    zero_1: u8 align(1),
    nr_of_entries: u16 align(1),
    map_ent: [*c]map_ent_t align(1),
};

pub const vts_tmapt_t = extern struct {
    nr_of_tmaps: u16 align(1),
    zero_1: u16 align(1),
    last_byte: u32 align(1),
    tmap: [*c]vts_tmap_t align(1),
    tmap_offset: [*c]u32 align(1),
};

pub const ifo_handle_t = extern struct {
    vmgi_mat: ?*vmgi_mat_t,
    tt_srpt: [*c]tt_srpt_t,
    first_play_pgc: ?*pgc_t,
    ptl_mait: [*c]ptl_mait_t,
    vts_atrt: [*c]vts_atrt_t,
    txtdt_mgi: [*c]txtdt_mgi_t,
    pgci_ut: [*c]pgci_ut_t,
    menu_c_adt: [*c]c_adt_t,
    menu_vobu_admap: [*c]vobu_admap_t,
    vtsi_mat: ?*vtsi_mat_t,
    vts_ptt_srpt: [*c]vts_ptt_srpt_t,
    vts_pgcit: [*c]pgcit_t,
    vts_tmapt: [*c]vts_tmapt_t,
    vts_c_adt: [*c]c_adt_t,
    vts_vobu_admap: [*c]vobu_admap_t,
};

pub extern fn ifoOpen(?*dvd_reader_t, c_int) [*c]ifo_handle_t;
pub extern fn ifoOpenVMGI(?*dvd_reader_t) [*c]ifo_handle_t;
pub extern fn ifoOpenVTSI(?*dvd_reader_t, c_int) [*c]ifo_handle_t;
pub extern fn ifoClose([*c]ifo_handle_t) void;

pub extern fn ifoRead_PTL_MAIT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_VTS_ATRT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_TT_SRPT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_VTS_PTT_SRPT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_FP_PGC([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_PGCIT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_PGCI_UT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_VTS_TMAPT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_C_ADT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_TITLE_C_ADT([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_VOBU_ADMAP([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_TITLE_VOBU_ADMAP([*c]ifo_handle_t) c_int;
pub extern fn ifoRead_TXTDT_MGI([*c]ifo_handle_t) c_int;
pub extern fn ifoFree_PTL_MAIT([*c]ifo_handle_t) void;
pub extern fn ifoFree_VTS_ATRT([*c]ifo_handle_t) void;
pub extern fn ifoFree_TT_SRPT([*c]ifo_handle_t) void;
pub extern fn ifoFree_VTS_PTT_SRPT([*c]ifo_handle_t) void;
pub extern fn ifoFree_FP_PGC([*c]ifo_handle_t) void;
pub extern fn ifoFree_PGCIT([*c]ifo_handle_t) void;
pub extern fn ifoFree_PGCI_UT([*c]ifo_handle_t) void;
pub extern fn ifoFree_VTS_TMAPT([*c]ifo_handle_t) void;
pub extern fn ifoFree_C_ADT([*c]ifo_handle_t) void;
pub extern fn ifoFree_TITLE_C_ADT([*c]ifo_handle_t) void;
pub extern fn ifoFree_VOBU_ADMAP([*c]ifo_handle_t) void;
pub extern fn ifoFree_TITLE_VOBU_ADMAP([*c]ifo_handle_t) void;
pub extern fn ifoFree_TXTDT_MGI([*c]ifo_handle_t) void;

pub extern fn ifo_print(dvd: ?*dvd_reader_t, title: c_int) void;
pub extern fn dvdread_print_time(dtime: [*c]dvd_time_t) void;

pub const DVDREAD_VERSION_H_ = "";
pub inline fn DVDREAD_VERSION_CODE(major: anytype, minor: anytype, micro: anytype) @TypeOf(((major * @as(c_int, 10000)) + (minor * @as(c_int, 100))) + (micro * @as(c_int, 1))) {
    return ((major * @as(c_int, 10000)) + (minor * @as(c_int, 100))) + (micro * @as(c_int, 1));
}
pub const DVDREAD_VERSION_MAJOR = @as(c_int, 6);
pub const DVDREAD_VERSION_MINOR = @as(c_int, 1);
pub const DVDREAD_VERSION_MICRO = @as(c_int, 3);
pub const DVDREAD_VERSION_STRING = "6.1.3";
pub const DVDREAD_VERSION = DVDREAD_VERSION_CODE(DVDREAD_VERSION_MAJOR, DVDREAD_VERSION_MINOR, DVDREAD_VERSION_MICRO);
pub const DVD_VIDEO_LB_LEN = @as(c_int, 2048);
pub const MAX_UDF_FILE_NAME_LEN = @as(c_int, 2048);
pub const LIBDVDREAD_IFO_READ_H = "";
pub const LIBDVDREAD_IFO_TYPES_H = "";
pub const PRAGMA_PACK = @as(c_int, 0);
pub const COMMAND_DATA_SIZE = @as(c_uint, 8);
pub const PGC_COMMAND_TBL_SIZE = @as(c_uint, 8);
pub const BLOCK_TYPE_NONE = @as(c_int, 0x0);
pub const BLOCK_TYPE_ANGLE_BLOCK = @as(c_int, 0x1);
pub const BLOCK_MODE_NOT_IN_BLOCK = @as(c_int, 0x0);
pub const BLOCK_MODE_FIRST_CELL = @as(c_int, 0x1);
pub const BLOCK_MODE_IN_BLOCK = @as(c_int, 0x2);
pub const BLOCK_MODE_LAST_CELL = @as(c_int, 0x3);
pub const PGC_SIZE = @as(c_uint, 236);
pub const PGCI_SRP_SIZE = @as(c_uint, 8);
pub const PGCIT_SIZE = @as(c_uint, 8);
pub const PGCI_LU_SIZE = @as(c_uint, 8);
pub const PGCI_UT_SIZE = @as(c_uint, 8);
pub const C_ADT_SIZE = @as(c_uint, 8);
pub const VOBU_ADMAP_SIZE = @as(c_uint, 4);
pub const TT_SRPT_SIZE = @as(c_uint, 8);
pub const PTL_MAIT_NUM_LEVEL = @as(c_int, 8);
pub const PTL_MAIT_COUNTRY_SIZE = @as(c_uint, 8);
pub const PTL_MAIT_SIZE = @as(c_uint, 8);
pub const VTS_ATTRIBUTES_SIZE = @as(c_uint, 542);
pub const VTS_ATTRIBUTES_MIN_SIZE = @as(c_uint, 356);
pub const VTS_ATRT_SIZE = @as(c_uint, 8);
pub const TXTDT_LU_SIZE = @as(c_uint, 8);
pub const TXTDT_MGI_SIZE = @as(c_uint, 20);
pub const VTS_PTT_SRPT_SIZE = @as(c_uint, 8);
pub const VTS_TMAP_SIZE = @as(c_uint, 4);
pub const VTS_TMAPT_SIZE = @as(c_uint, 8);
pub const LIBDVDREAD_IFO_PRINT_H = "";

pub const dvd_reader_s = struct_dvd_reader_s;
pub const dvd_reader_device_s = struct_dvd_reader_device_s;
pub const dvd_file_s = struct_dvd_file_s;
