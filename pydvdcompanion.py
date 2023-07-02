import vstools
import functools
from vstools import vs

class DvdCompanion:
    def __init__(self,node: vs.VideoNode):
        self.frame0 = node.get_frame(0)
        self.json = DvdCompanion.extract_json(self.frame0.props)
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
        self.total_s = 0.0
        self.current_chapter_offset = 0

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

#only usable on non interleaved cells
def get_range_for_normal_cell(framezz,playback):
    first = None
    last = None

    fs = playback["first_sector"] * 2048
    ls = (playback["last_sector"]+1) * 2048

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