from typing import Tuple
import vstools
import functools
from vstools import vs

import json

class DvdCompanion:
    def __init__(self,node: vs.VideoNode):
        self.frame0 = node.get_frame(0)
        self.json_str = DvdCompanion.extract_json(self.frame0.props)
        self.json = json.loads(self.json_str)
        self.framezz = DvdCompanion.extract_framezz(self.frame0.props)
        self.vobid = DvdCompanion.extract_vobid(self.frame0.props)
        self.angle = DvdCompanion.extract_angle(self.frame0.props)

        self.vobidframedict = create_vobids_framedict(self.vobid)

    def __extract_binary_from_prps(prps,nam:str,datatype: str):
        framezz = None
        if nam in prps:
            for c in prps[nam].readchunks():
                import struct
                data = bytes(c)
                sz = struct.unpack("<Q" ,data[0:8])[0]
                ss = 8
                if datatype == "B":
                    ss = 1
                if datatype == "H":
                    ss = 2
                cnt = sz // ss

                framezz = struct.unpack(f"<{cnt}{datatype}",data[8:8 + sz])
        return framezz

    def extract_framezz(prps):
        return DvdCompanion.__extract_binary_from_prps(prps,"_FileFramePositionFrame","Q")

    def extract_angle(prps):
        return DvdCompanion.__extract_binary_from_prps(prps,"_AngleFrame","B")

    def extract_vobid(prps):
        return DvdCompanion.__extract_binary_from_prps(prps,"_VobIdFrame","H")

    def extract_json(prps):
        jdata = None
        if "_JsonFrame" in prps:
            for c in prps["_JsonFrame"].readchunks():
                import struct
                data = bytes(c)
                sz = struct.unpack("<Q",data[0:8])[0]
                jdata = data[8:8+sz].decode("utf-8")
        return jdata

    def vobids_print(self):
        if self.vobidframedict is None:
            self.vobidframedict = create_vobids_framedict(self.vobid)
        for i,a in enumerate(self.vobidframedict.keys()):
            l = len(self.vobidframedict[a])
            print(f"vobid {a} len {l}")

def create_vobids_framedict(vobids: list[int]):
    frmvobids = dict()
    for i,a in enumerate(vobids):
        if frmvobids.get(a) is None:
            frmvobids[a] = []
        frmvobids[a].append(i)
    return frmvobids


#https://stackoverflow.com/questions/23681948/get-index-of-closest-value-with-binary-search
def binarySearch(data, val):
    lo, hi = 0, len(data) - 1
    best_ind = lo
    while lo <= hi:
        mid = lo + (hi - lo) // 2
        if data[mid] < val:
            lo = mid + 1
        elif data[mid] > val:
            hi = mid - 1
        else:
            best_ind = mid
            break
        # check if data[mid] is closer to val than data[best_ind]
        if abs(data[mid] - val) < abs(data[best_ind] - val):
            best_ind = mid
    return best_ind

class Ranger:
    def __init__(self):
        self.ranges = []
        self.original_chapters = []
        self.chapters = []
        self.original_ranges = []
        self.sectors = []

        self.total_s = 0.0
        self.current_chapter_offset = 0

    def add_sectors(self,sector_pair):
        self.sectors += [sector_pair]
    
    #start inclusive end inclusive
    def add_range(self,start,end,should_add_chapter):
        self.ranges += [ [start,end] ]
        if should_add_chapter:
            self.original_chapters += [ start ]
            self.chapters += [ self.current_chapter_offset ]
        self.current_chapter_offset += end - start + 1

    def merge(self):
        import copy
        self.original_ranges = copy.deepcopy(self.ranges)
        ranges = copy.deepcopy(self.ranges)
        ranges.sort(key=lambda elem: elem[0])

        didsomething = True
        while didsomething:
            didsomething = False
            for r in range(len(ranges)-1):
                first = ranges[r]
                next  = ranges[r+1]
                if next[0] == first[1]+1:
                    ranges[r][1] = next[1]
                    del ranges[r+1]

                    didsomething = True
                    break
        self.ranges = ranges

def get_frames_for_interleaved_cell(framezz, vobiddict, playback, position) -> list[int]:
    first,last = get_range_for_normal_cell(framezz,playback)
    frames = vobiddict[position["vob_id_nr"]]
    filtered = list(filter(lambda f: f >= first and f <= last, frames))
    if len(filtered) != len(frames) or len(filtered) != len(frames):
        print("mismatch between filtered and frames")
        print("this breaks a assumption the a single angle cell is a single vobid")

        
        print("FILTERED")
        print(filtered)
        print("FRAMES")
        print(frames)
    return filtered


def get_frame_range_between_first_last_sector(framezz: list[int],first_sector: int,last_sector: int) -> Tuple[int,int]:
    first = None
    last = None

    fs = first_sector * 2048
    ls = (last_sector+1) * 2048

    roughfirst = binarySearch(framezz,fs)
    roughlast = binarySearch(framezz,ls)

    for i in range(max(roughfirst-5,0),len(framezz)):
        if framezz[i] > fs:
            first = i
            break

    for i in range(max(roughlast-5,0),len(framezz)):
        if framezz[i] < ls:
            last = i
        else:
            assert first is not None
            assert last is not None
            break

    return (first,last)

def get_range_for_normal_cell(framezz,playback) -> Tuple[int,int]:
    return get_frame_range_between_first_last_sector(framezz,playback["first_sector"],playback["last_sector"])


def cut_node(node: vs.VideoNode,frames: list[int]) -> vs.VideoNode:
    ranges = vstools.normalize_list_to_ranges(frames)
    return cut_node_on_ranges(node,ranges)


def cut_node_on_ranges(node: vs.VideoNode,ranges) -> vs.VideoNode:
    remap_frames = tuple[int, ...]([
        x for y in [
            range(rrange[0], rrange[1] + 1) for rrange in ranges
        ] for x in y
    ])

    blank = node.std.BlankClip(length=len(remap_frames))

    def ele(n,leldvd,lelremap_frames):
        return leldvd[lelremap_frames[n]]

    return blank.std.FrameEval(functools.partial(ele,leldvd=node,lelremap_frames=remap_frames))

def open_dvd_somehow(path):
    new_node = None
    try:
        new_node = vs.core.dvdsrc.Full(path,vts=0,domain=0)
    except:
        try:
            new_node = vs.core.dvdsrc.Full(path,vts=0,domain=1)
        except:
            try:
                new_node = vs.core.dvdsrc.Full(path,vts=1,domain=0)
            except:
                try:
                    new_node = vs.core.dvdsrc.Full(path,vts=1,domain=1)
                except:
                    assert False
    return new_node

#lel = {k: vstools.normalize_list_to_ranges(v) for k, v in frmvobids.items()}
#nodes = {k: pydvdcompanion.cut_node(aa,v) for k, v in frmvobids.items()}


def get_sectorranges_for_vobcellpair(current_vts:dict,cell_id:int,vob_id: int):
    ranges = []

    #todo binary search for vobid
    #assumes vts_c_adt is sorted
    for e in current_vts["vts_c_adt"]:
        if e["cell_id"] == cell_id and e["vob_id"] == vob_id:
            ranges +=  [ (e["start_sector"],e["last_sector"])]
        #if e["vob_id"] > vob_id:
        #    break
    return ranges


# saves frame an sector range
def calculate_frame_range_for_title(framezz,current_vts:dict,current_title: dict,angle_index: int = 0):
    rang = Ranger()

    pgc0 = current_title[0]["pgcn"]
    entry_pgn = current_title[0]["pgn"]
    #exit_pgn = current_title[-1]["pgn"]

    #this assumes there is one pgc and and just takes what spans petween the first program and the last cell
    #and also takes cells that aren't programs and marks program ones as chapter
    #this should be correct but no idea because no access to spec so only guess

    crnpgc = current_vts["pgcs"][(current_title[0]["pgcn"]) - 1]
        
    #this seems to only be used fo chapters but for playback everything from the entry up untill ends needs to be considered ??
    entry_cell = crnpgc["program_map"][entry_pgn - 1] - 1
    #exit_cell  = crnpgc["program_map"][exit_pgn - 1] - 1
    exit_cell = len(crnpgc["cell_position"]) - 1

    cell_that_have_a_program = []
    for ptt in current_title:
        if ptt["pgcn"] != pgc0:
            print("multi pgc title not supported yet (don't know any dvd but they do exist)")
            return rang
        cell_that_have_a_program += [ crnpgc["program_map"][ptt["pgn"]-1] ]


    #this assumes angles always appear in the chronologically order as cells
    angle_i = 0

    for cell_index in range(entry_cell, exit_cell+1):
        current_cell_playback = crnpgc["cell_playback"][cell_index]
        current_cell_position = crnpgc["cell_position"][cell_index]

        sector_ranges = get_sectorranges_for_vobcellpair(current_vts,current_cell_position["cell_nr"],current_cell_position["vob_id_nr"])
        
        inleaved = current_cell_playback["interleaved"]

        if not inleaved:
            angle_i = 0
        
        if angle_i == angle_index or (not inleaved):
            for ii,rangey in enumerate(sector_ranges):
                start,end = get_frame_range_between_first_last_sector(framezz,rangey[0],rangey[1])
                rang.add_range(start,end,(cell_index in cell_that_have_a_program) and (ii == 0))
                rang.add_sectors(rangey)

        if inleaved:
            angle_i += 1

        rang.total_s += dvdtime_to_s(current_cell_playback["playback_time"])
        
    rang.merge()

    return rang


def bcd_to_int(bcd: int) -> int:
    return ((0xFF & (bcd >> 4)) * 10) + (bcd & 0x0F)

def dvdtime_to_s(dt: dict):
    fpslookup = [0, 25.00, 0, 30000.0 / 1001.0]
    fps = fpslookup[dt["frame_u"] >> 6]

    ms  = bcd_to_int(dt["hour"])    * 3600
    ms += bcd_to_int(dt["minute"])  * 60
    ms +=  bcd_to_int(dt["second"])

    frames = bcd_to_int(dt["frame_u"] & 0x3F)


    if fps > 0:
        ms += frames / fps

    return ms