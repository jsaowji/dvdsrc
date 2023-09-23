import vstools
import functools
from vstools import vs,core
from typing import List, Tuple
import json

class ADT:
    def __init__(self,adt: dict):
        ctlct = dict()
        for a in adt:
            vi = a["vob_id"] 
            ci = a["cell_id"]

            if vi not in ctlct:
                ctlct[vi] = dict()
            
            if ci not in ctlct[vi]:
                (ctlct[vi])[ci] = list()
            
            ctlct[vi][ci] += [ (a["start_sector"], a["last_sector"])]
        self.inner = ctlct
    
    def get_sector_list_vobid(self,vobid: int) -> List[int]:
        cells = self.inner[vobid]
        ret = []
        for sectors in cells:
            ret += self.get_sector_list_vobidcellid(sectors)
        return ret
    
    def get_sector_list_vobidcellid(self,vobid: int,cellid: int) -> List[int]:
        cells = self.inner[vobid]
        sectors = cells[cellid]

        ret = []
        for c in sectors:
            ret += list(range(c[0],c[1] + 1))
        return ret


class DVD:
    def __init__(self, path: str):
        self.path = path
        self.json = json.loads(core.dvdsrc.Json(path))
        self.vts: List[VTS] = []
        for a in range(len(self.json["ifos"])):
            self.vts += [VTS(self,a)]


    def dump_json(self,path:str):
        json.dump(self.json,open(path,"wt"))

    def __str__(self) -> str:
        sta = ""
        ifos = len(self.json["ifos"])
        
        for a in range(ifos):
            sta += VTS(self,a).__str__()

        return sta

class VTSDomain:
    def __init__(self, vts,domain: int):
        self.vts = vts
        self.domain = domain

    def cutout(self,lst: List[int]) -> vs.VideoNode:
        return core.dvdsrc.CutVob(self.vts.dvd.path, vts=self.vts.i, domain=self.domain,sectors=lst)

    def writecutout(self,lst: List[int],out: str):
        ct = self.cutout(lst)
        fl = open(out,"wb")
        for a in ct.frames():
            fl.write(bytes(a[0]))

    def m2v(self,lst: List[int]) -> vs.VideoNode:
        return core.dvdsrc.FullM2V(self.vts.dvd.path, vts=self.vts.i, domain=self.domain,sectors=lst)

    def ac3(self,lst: List[int],audioidx: int) -> vs.AudioNode:
        return core.dvdsrc.FullAC3(self.vts.dvd.path, vts=self.vts.i, domain=self.domain,sectors=lst,audioidx=audioidx)

    def lpcm(self,lst: List[int],audioidx: int) -> vs.AudioNode:
        return core.dvdsrc.FullLPCM(self.vts.dvd.path, vts=self.vts.i, domain=self.domain,sectors=lst,audioidx=audioidx)


class VTS:
    def __init__(self, main: DVD, i: int):
        self.dvd = main
        self.i = i
        self.json = self.dvd.json["ifos"][i]
        if self.i != 0:
            self.vts_adt = ADT(self.json["vts_c_adt"])

        self.title = VTSDomain(self,1)
        self.menu =  VTSDomain(self,0)



class DVDSRCM2vInfoExtracter:
    def __init__(self,node: vs.VideoNode):
        self.node = node
        self.frame0 = node.get_frame(0)
        
        self.json_str = DVDSRCM2vInfoExtracter.__extract_json(self.frame0.props)
        self.json = json.loads(self.json_str)

        self.vobid_raw = DVDSRCM2vInfoExtracter.__extract_vobid(self.frame0.props)
        self.vobid = [ ((x & 0xFFFF00)>>8,x & 0xFF) for x in self.vobid_raw ]
        self.rff = DVDSRCM2vInfoExtracter.__extract_binary_from_prps(self.frame0.props,"_RffFrame","B")
        self.tff = DVDSRCM2vInfoExtracter.__extract_binary_from_prps(self.frame0.props,"_TffFrame","B")

#        if len(self.framezz) > len(node):
#            self.framezz = self.framezz[0:len(node)]
#            print("Slicing down framezz, this could be an indecation that the sourcefilter failed somehow")
#        
        #self.framezz = DvdCompanion.__extract_framezz(self.frame0.props)
        #self.angle = DvdCompanion.__extract_angle(self.frame0.props)

        assert len(self.tff) == len(self.rff)
        assert len(self.tff) == len(self.rff)
        
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
                if datatype == "I":
                    ss = 4
                assert (sz % ss) == 0
                cnt = sz // ss

                framezz = struct.unpack(f"<{cnt}{datatype}",data[8:8 + sz])
        return framezz

    def __extract_framezz(prps):
        return DVDSRCM2vInfoExtracter.__extract_binary_from_prps(prps,"_FileFramePositionFrame","Q")

    def __extract_angle(prps):
        return DVDSRCM2vInfoExtracter.__extract_binary_from_prps(prps,"_AngleFrame","B")

    def __extract_vobid(prps):
        return DVDSRCM2vInfoExtracter.__extract_binary_from_prps(prps,"_VobIdCellIdFrame","I")

    def __extract_json(prps):
        jdata = None
        if "_JsonFrame" in prps:
            for c in prps["_JsonFrame"].readchunks():
                import struct
                data = bytes(c)
                sz = struct.unpack("<Q",data[0:8])[0]
                jdata = data[8:8+sz].decode("utf-8")
        return jdata

### sector stuff


def create_vobid_frame_dict(vobid: List[Tuple[int,int]]):
    a = dict()
    for ii,aa in enumerate(vobid):
        if aa not in a:
            a[aa] = []
        a[aa] += [ii]
    return a


def pgc_open_audios(sector_list: List[int], vts: VTS, audios: List[int]) -> List[vs.AudioNode]:
    oa = []
    for a in audios:
        af =  vts.json["vtsi_mat"]["vts_audio_attr"][a]["audio_format"]
        if af == 0:
            oa += [ vts.title.ac3(sector_list, a) ]
        elif af == 4:
            oa += [ vts.title.lpcm(sector_list, a) ]
        else:
            assert False
    return oa

def pgc_get_availible_audio_idxs(pgcjson: dict) -> List[int]:
    audios = []
    for ii,a in enumerate(pgcjson["audio_control"]):
        if a["available"]:
            num = a["number"]
            assert num == ii
            audios += [ num ]
    return audios

#TODO: get sectors for full pgc multi angle
def get_sectors_for_full_pgc_simple(current_vts: dict, pgcjson: dict) -> List[int]:
    assert_no_interleave(pgcjson["cell_playback"])

    sectors = []
    for pos in pgcjson["cell_position"]:
        sector_ranges = get_sectorranges_for_vobcellpair_2(current_vts, pos["cell_nr"], pos["vob_id_nr"])
        assert len(sector_ranges) == 1

        sector_ranges = sector_ranges[0]

        sectors += list(range(sector_ranges[0], sector_ranges[1]+1))

    return sectors

def get_sectorranges_for_vobcellpair_2(current_vts: dict, cell_id: int, vob_id: int):
    ranges = []

    #todo binary search for vobid
    #assumes vts_c_adt is sorted
    for e in current_vts["vts_c_adt"]:
        if e["cell_id"] == cell_id and e["vob_id"] == vob_id:
            ranges +=  [ (e["start_sector"], e["last_sector"])]
        #if e["vob_id"] > vob_id:
        #    break
    return ranges


def assert_no_interleave(cell_playbacks):
    for a in cell_playbacks:
        if a["interleaved"]:
            print("Interleaved stuff is not supported in this function")
            assert False

def cut_node(node: vs.VideoNode,frames: list[int]) -> vs.VideoNode:
    ranges = normalize_list_to_ranges(frames)
    return cut_node_on_ranges(node,ranges)



#WARNING used in pydvdsrcs

def get_sectors_from_vobids(target_vts: dict, vobidcellids_to_take: List[Tuple[int, int]]) -> List[int]:
    sectors = []
    for a in vobidcellids_to_take:
        for srange in get_sectorranges_for_vobcellpair(target_vts, a):
            sectors += list(range(srange[0], srange[1] + 1))
    return sectors

def get_sectorranges_for_vobcellpair(current_vts: dict, pair_id: Tuple[int, int]) -> List[Tuple[int,int]]:
    ranges = []
    for e in current_vts["vts_c_adt"]:
        if e["cell_id"] == pair_id[1] and e["vob_id"] == pair_id[0]:
            ranges += [(e["start_sector"], e["last_sector"])]
    return ranges




##THIS IS IN VSsource
from vstools import vs, core, SPath, normalize_list_to_ranges, FrameRange
from typing import List, Any
from functools import partial

def apply_rff_array(rff: List[int], old_array: List[any]) -> List[any]:
    array_double_rate = []
        
    for a in range(len(rff)):
        if rff[a] == 1:
            array_double_rate += [ old_array[a], old_array[a], old_array[a] ]
        else:
            array_double_rate += [ old_array[a], old_array[a] ]
    
    assert (len(array_double_rate) % 2) == 0
    
    array_return = []
    for i in range(len(array_double_rate) // 2):
        f1 = array_double_rate[i * 2 + 0]
        f2 = array_double_rate[i * 2 + 1]
        if f1 != f2:
            print("Warning ambigious pattern due to rff {} {}".format(f1, f2))
        array_return += [ f1 ]

    return array_return

def apply_rff_video(node: vs.VideoNode, rff: List[int], tff: List[int]) -> vs.VideoNode:
    assert len(node) == len(rff)
    assert len(rff) == len(tff)

    fields = []
    tfffs = core.std.SeparateFields(core.std.RemoveFrameProps(node, props=["_FieldBased","_Field"]), tff=True)

    for i in range(len(rff)):
        current_tff = tff[i]
        current_bff = int(not current_tff)

        if current_tff == 1:
            first_field  = 2 * i
            second_field = 2 * i + 1
        else:
            first_field  = 2 * i + 1
            second_field = 2 * i

        fields += [ {"n":first_field, "tf": current_tff}, {"n":second_field, "tf": current_bff} ]
        if rff[i] == 1:
            fields += [ fields[-2] ]

    assert (len(fields) % 2) == 0

    for a in range(len(fields) // 2):
        tf = fields[a * 2] 
        bf = fields[a * 2 + 1]
    
        #should this assert?
        #assert tf["tf"] != bf["tf"]
        if tf["tf"] == bf["tf"]:
            print("invalid field transition @{}".format(a))

    fields = [ x["n"] for x in fields ]

    final = clip_remap_frames(tfffs,fields)

    final = core.std.RemoveFrameProps(final,props=["_FieldBased","_Field"])
    woven = core.std.DoubleWeave(final, tff=True)
    woven = core.std.SelectEvery(woven, 2, 0)
    woven = core.std.SetFieldBased(woven, 2)

    return woven

def cut_array_on_ranges(array: List[Any], ranges: List[FrameRange]) -> List[Any]:
    remap_frames = tuple[int, ...]([
        x for y in [
            range(rrange[0], rrange[1] + 1) for rrange in ranges
        ] for x in y
    ])
    newarray = []
    for i in remap_frames:
        newarray += [ array[i] ]
    return newarray 

def cut_node_on_ranges(node: vs.VideoNode, ranges: List[FrameRange]) -> vs.VideoNode:
    remap_frames = tuple[int, ...]([
        x for y in [
            range(rrange[0], rrange[1] + 1) for rrange in ranges
        ] for x in y
    ])
    return clip_remap_frames(node,remap_frames)

def clip_remap_frames(node: vs.VideoNode, remap_frames) -> vs.VideoNode: #remap_frames: List[int]
    blank = node.std.BlankClip(length=len(remap_frames))

    def noname(n, target_node, targetremap_frames):
        return target_node[targetremap_frames[n]]

    return blank.std.FrameEval(partial(noname,target_node=node, targetremap_frames=remap_frames))
