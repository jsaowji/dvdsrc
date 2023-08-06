from typing import List, Tuple
import vstools
import functools
from vstools import vs,core
import os
import json



#def pydvd.LoadT(path:str)
# Loads first angle of first title (entry in VMG TT_SRPT)

#def pydvd.LoadT(path:str, title: int, angle:int = 1)
# title=2 Loads first angle of second title
# title=2 angle=2 Loads second angle of second title

#def pydvd.LoadP(path:str, vts: int, pgc:int, angle:int = 1)
#vts=1 pgc=1 Loads first PGC in VTS_01_*.VOB

#def pydvd.Load(path:str, vts: int, cells: List[Tuple[int,int]]})
#vts=1 cells=[(1, 1), (1, 2), (1, 3)] Loads specific (Vob, Cell)s from VTS_01_*.VOB

#def pydvd.Load(path:str, vts: int, pgc: int, cells: List[int]
#vts = 1, pgc=1,cells=[1,2] Loads the first and 2nd cell from pgc 1 from VTS_01_1..x.VOB

#TODO: what should these return 
# vs.VideoNode ?
# object like ExtractPgc, with chaptermarks, audiohelper functions 

class ExtractPgc:
    def __init__(self, dvdpath: str, vts: int, pgc_n: int, angle_n: int = 0, cells_n: List[int] = None) -> dict:
        node = core.dvdsrc.Full(dvdpath,vts,1)
        compa = DvdCompanion(node)
        current_ifo = compa.json["ifos"][vts]

        pgc = current_ifo["pgcs"][pgc_n - 1]
        cell_position = pgc["cell_position"]

        cells_sectors = map(lambda c: get_sectorranges_for_vobcellpair(current_ifo,c["cell_nr"],c["vob_id_nr"]),cell_position)
        cells_sectors = list(cells_sectors)


        frame_ranges = []
        chapter_marks = []
        sector_ranges = []
        
        angle_i = 0

        nama =  enumerate(pgc["cell_playback"])
        if cells_n is not None:
            nama = [ ]
            for i,a in enumerate(pgc["cell_playback"]):
                if (i+1) in cells_n:
                    nama += [ (i,a) ]

        for i,c in nama:
            inleaved = c["interleaved"]

            if not inleaved:
                angle_i = 0
            else:
                angle_i += 1        
            if angle_i == angle_n or (not inleaved):
                for rangey in cells_sectors[i]:
                    start,end = get_frame_range_between_first_last_sector(compa.framezz,rangey[0],rangey[1])
                    frame_ranges  += [ (start,end) ]
                if (i+1) in pgc["program_map"]:
                    chapter_marks += [ start ]
                sector_ranges += cells_sectors[i]

        self.dvdpath = dvdpath
        self.vts = vts
        self.node = node
        self.frame_ranges = frame_ranges
        self.chapter_marks = chapter_marks
        self.sector_ranges = sector_ranges
        self.compa = compa

        #print(len(self.node), len(compa.framezz) )
        assert len(self.node) == len(compa.framezz) 
    
    def muxtools_chapters(self):
        from vsmuxtools import Chapters
        return Chapters(list(map(lambda x: (x,None), self.chapter_marks)),fps=self.node.fps)
    
    def muxtools_audio(self,audio_index: int = 0):
        from vsmuxtools import do_audio
        from tempfile import TemporaryDirectory
        
        with TemporaryDirectory() as temp_dir:
            tmpvob = os.path.join(temp_dir,"vob.vob")

            self.dump_to_file(tmpvob)
            epaudio = do_audio(tmpvob, audio_index)
        
        return epaudio
    
    def muxtools_audios(self,audio_indexs: List[int]):
        from vsmuxtools import do_audio
        from tempfile import TemporaryDirectory
        
        with TemporaryDirectory() as temp_dir:
            tmpvob = os.path.join(temp_dir,"vob.vob")
            self.dump_to_file(tmpvob)
            
            epaudios = list(map(lambda x: do_audio(tmpvob, x),audio_indexs))
        
        return epaudios

    def final_video_node(self) -> vs.VideoNode:
        return cut_node_on_ranges(self.node,self.frame_ranges)
    
    def final_video_node_rff(self) -> vs.VideoNode:
        rff = cut_array_on_ranges(self.compa.rff,self.frame_ranges)
        tff = cut_array_on_ranges(self.compa.tff,self.frame_ranges)
        
        node = cut_node_on_ranges(self.node,self.frame_ranges)
        
        return apply_rff(node,rff,tff)

    def dump_to_file(self, outfile: str):
        secstors = []
        for a in self.sector_ranges:
            for b in range(a[0],a[1]+1):
                secstors += [ b ]
        
        core.dvdsrc.VobToFile(self.dvdpath,self.vts,1,secstors,outfile)

class DvdCompanion:
    def __init__(self,node: vs.VideoNode):
        self.node = node
        self.frame0 = node.get_frame(0)
        self.json_str = DvdCompanion.extract_json(self.frame0.props)
        self.json = json.loads(self.json_str)
        self.framezz = DvdCompanion.extract_framezz(self.frame0.props)
        self.vobid = DvdCompanion.extract_vobid(self.frame0.props)
        self.angle = DvdCompanion.extract_angle(self.frame0.props)
        self.rff = DvdCompanion.__extract_binary_from_prps(self.frame0.props,"_RffFrame","B")
        self.tff = DvdCompanion.__extract_binary_from_prps(self.frame0.props,"_TffFrame","B")

        self.vobidframedict = create_vobids_framedict(self.vobid)

        if len(self.framezz) > len(node):
            self.framezz = self.framezz[0:len(node)]
            print("Slicing down framezz, this could be an indecation that the sourcefilter failed somehow")

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
                assert (sz % ss) == 0
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

##def get_frames_for_interleaved_cell(framezz, vobiddict, playback, position) -> list[int]:
##    first,last = get_range_for_normal_cell(framezz,playback)
##    frames = vobiddict[position["vob_id_nr"]]
##    filtered = list(filter(lambda f: f >= first and f <= last, frames))
##    if len(filtered) != len(frames) or len(filtered) != len(frames):
##        print("mismatch between filtered and frames")
##        print("this breaks a assumption the a single angle cell is a single vobid")
##
##        
##        print("FILTERED")
##        print(filtered)
##        print("FRAMES")
##        print(frames)
##    return filtered

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


def cut_node_on_ranges(node: vs.VideoNode, ranges) -> vs.VideoNode:
    remap_frames = tuple[int, ...]([
        x for y in [
            range(rrange[0], rrange[1] + 1) for rrange in ranges
        ] for x in y
    ])

    blank = node.std.BlankClip(length=len(remap_frames))

    def ele(n,leldvd,lelremap_frames):
        return leldvd[lelremap_frames[n]]

    return blank.std.FrameEval(functools.partial(ele,leldvd=node,lelremap_frames=remap_frames))

def cut_array_on_ranges(array: List[int], ranges) -> vs.VideoNode:
    remap_frames = tuple[int, ...]([
        x for y in [
            range(rrange[0], rrange[1] + 1) for rrange in ranges
        ] for x in y
    ])
    newarray = []
    for i in remap_frames:
        newarray += [ array[i] ]
    return newarray 

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

def get_frameranges_for_vobcellpair(current_vts:dict,cell_id:int,vob_id: int,framezz: List[int]):
    secs = get_sectorranges_for_vobcellpair(current_vts,cell_id,vob_id)
    framez = []
    for rangey in secs:
        start,end = get_frame_range_between_first_last_sector(framezz,rangey[0],rangey[1])
        framez += [ (start,end) ]
    return framez

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



#this assumes progressive_sequence 0
def apply_rff(node: vs.VideoNode, rff: List[int], tff: List[int]):
    assert len(node) == len(rff)
    assert len(rff) == len(tff)

    fields = []
    tfffs = core.std.SeparateFields(core.std.RemoveFrameProps(node,props=["_FieldBased","_Field"]),tff=True)

    for i in range(len(rff)):
        current_tff = tff[i]

        if current_tff:
            current_bff = 0
        else:
            current_bff = 1

        if current_tff == 1:
            first_field  = 2*i
            second_field = 2*i+1
        else:#bff
            first_field  = 2*i+1
            second_field = 2*i

        fields += [ {"n":first_field,"tf": current_tff}, {"n":second_field,"tf": current_bff} ]
        if rff[i] == 1:
            fields += [ fields[-2] ]

    assert (len(fields) % 2) == 0
    for a in range(len(fields) // 2):
        tf = fields[a*2] 
        bf = fields[a*2+1]
        assert tf["tf"] != bf["tf"]

    fields = [x["n"] for x in fields]


    remap_frames = fields
    node = tfffs

    blank = node.std.BlankClip(length=len(remap_frames))

    def ele(n,leldvd,lelremap_frames):
        return leldvd[lelremap_frames[n]]

    final = blank.std.FrameEval(functools.partial(ele,leldvd=node,lelremap_frames=remap_frames))

    final = core.std.RemoveFrameProps(final,props=["_FieldBased","_Field"])
    woven = core.std.DoubleWeave(final, tff=True)
    woven = core.std.SelectEvery(woven, 2, 0)
    woven = core.std.SetFieldBased(woven, 2)

    return woven