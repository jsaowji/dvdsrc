from typing import List, Tuple
import vstools
import functools
from vstools import vs,core
import os
import json
from enum import Enum
from pydvdsrc import *
from dataclasses import dataclass

@dataclass
class Extract:
    video: vs.VideoNode
    audios: List[vs.AudioNode]
    chapter_points: List[int]

    def filter_video(self,x):
        self.video = x(self.video)

    def set_output(self,base:int = 0):
        vv = self.video

        #vv = core.vivtc.VFM(vv,order=True)
        #vv = vv.resize.Bicubic(width=vstools.get_w(480,4/3),height=480)

        vv.set_output(base)

        for ii,a in enumerate(self.audios):
            a.set_output(base+1+ii)
        
        core.std.BlankClip(width=720,height=480,format=vs.YUV420P8).std.SetFrameProp("chapter_points",data=str(json.dumps(self.chapter_points))).set_output(1337)


def print_eps(eps: dict):
    for e in eps.items():
        print("{}: {}".format(e[0],e[1]))


def check_audio_offset(ctx,eps):
    for a in eps.keys():
        exa: Extract = eps[a](ctx)
        assert len(exa.audios) == 1
        vt = exa.video.num_frames / (exa.video.fps)
        at = exa.audios[0].num_samples / exa.audios[0].sample_rate
        print(vt - at)

def print_eps_totaltime(ctx,eps):
    import time
    for a in eps.keys():
        exa: Extract = eps[a](ctx)
        total_s = len(exa.video) / exa.video.fps
        totaltime = time.strftime("%H:%M:%S", time.gmtime(float(total_s)))
        totaltime += ".{:02}".format( int(10*(total_s % 1)))

        print(f"{a} {totaltime}")

class PgcChapterMode(Enum):
    NONE = 0
    CELL = 1
    #PROGRAM = 2

#st
#s = simple ie. no support for weird stuff like reusing cells or interleaved stuff
#t = title domain
def st_pgc_cellsplit(dvd: DVD, vts: int, pgc_nr: int, cell_nrs: List[int], chapter_mode: PgcChapterMode = PgcChapterMode.CELL) -> Extract:
    vts = dvd.vts[vts]
    pgcjson = vts.json["vts_pgcit"][pgc_nr-1]
    
    is_all_cells_inorder = True
    if len(cell_nrs) != pgcjson["nr_of_cells"]:
        is_all_cells_inorder = False
    else:
        for a in range(len(cell_nrs)):
            if cell_nrs[a] != a+1:
                is_all_cells_inorder = False
                break

    sl = get_sectors_for_full_pgc_simple(vts.json,pgcjson)
    ovideo = vts.title.m2v(sl) 
    compa =  DVDSRCM2vInfoExtracter(ovideo)
    video = apply_rff_video(ovideo,compa.rff,compa.tff)
    vobid = apply_rff_array(compa.rff,compa.vobid)
    #assert no vobid cell pair twice


    oa = pgc_open_audios(sl,vts,pgc_get_availible_audio_idxs(pgcjson))

    vobidfram = create_vobid_frame_dict(vobid)
    framesget = []
    chpts = []
    crnt = 0

    for i,c in enumerate(cell_nrs):
        pos = pgcjson["cell_position"][c-1]
        vobcellpair = (pos["vob_id_nr"], pos["cell_nr"])
        off = vobidfram[vobcellpair]
        framesget += off
        chpts += [ crnt ]
        crnt += len(off)
    
    cut_ranges = vstools.normalize_list_to_ranges(framesget)
    tpl   = [ (a[0] / video.fps,a[1] / video.fps) for a in cut_ranges]
    #audio_cuts = [ [(int(a[0] * audio.sample_rate), int(a[1] * audio.sample_rate)) for a in tpl] for audio in oa ]
    audio_cuts = [ [(  min(int(a[0] * audio.sample_rate),audio.num_samples-1), min(int(a[1] * audio.sample_rate),audio.num_samples-1)) for a in tpl] for audio in oa ]

    aoss = [ cut_audio_node_on_ranges(oa[i],audio_cuts[i]) for i in range(len(oa))]


    if is_all_cells_inorder:
        assert cut_ranges == [(0,len(video)-1)]
        #TODO: some sanity checking on audio


    return Extract(cut_node(video,framesget),aoss,chpts)

def st_pgc_vobids(dvd: DVD,vts: int,pgc_nr: int,vobids: List[int] | int, chapter_mode: PgcChapterMode = PgcChapterMode.CELL) -> Extract:
    if isinstance(vobids,int):
        vobids = [vobids]
    vts1 = dvd.vts[vts]
    pgcjson = vts1.json["vts_pgcit"][pgc_nr-1]

    #assert vobid only happens once
    #assert all continous

    cells = []
    for ii,a in enumerate(pgcjson["cell_position"]):
        if a["vob_id_nr"] in vobids:
            cells += [ii+1]
    return st_pgc_cellsplit(dvd,vts,pgc_nr,cells,chapter_mode)

def st_pgc_full(dvd: DVD,vts: int,pgc_nr: int,chapter_mode: PgcChapterMode = PgcChapterMode.CELL) -> Extract:
    return st_pgc_cellsplit(dvd,vts,pgc_nr,range(1,dvd.vts[vts].json["vts_pgcit"][pgc_nr-1]["nr_of_cells"]+1))
#</>

def cut_audio_node_on_ranges(a,b: List[Tuple[int,int]]):
    trimmed  = [ core.std.AudioTrim(a,xx[0],xx[1]) for xx in b ]
    return core.std.AudioSplice(trimmed)        

@dataclass
class TitlePgcCellSplit:
    dvdsrc: str
    vts: int
    pgc_nr: int
    cell_nrs: List[int]
    chapter_mode: PgcChapterMode = PgcChapterMode.CELL

    def make_lambda(self):
        return lambda ctx: st_pgc_cellsplit(DVD(ctx.dvds[self.dvdsrc]), self.vts, self.pgc_nr, self.cell_nrs, self.chapter_mode)

#gets put over into cellsplit
@dataclass
class TitlePgcFull:
    dvdsrc: str
    vts: str
    pgc_nr: int
    chapter_mode: PgcChapterMode = PgcChapterMode.CELL

    def make_lambda(self):
        return lambda ctx: st_pgc_full(DVD(ctx.dvds[self.dvdsrc]), self.vts, self.pgc_nr, self.chapter_mode)

@dataclass
class TitlePgcVobID:
    dvdsrc: str
    vts: int
    pgc_nr: int
    vobids: List[int] | int
    chapter_mode: PgcChapterMode = PgcChapterMode.CELL

    def make_lambda(self):
        return lambda ctx: st_pgc_vobids(DVD(ctx.dvds[self.dvdsrc]), self.vts, self.pgc_nr, self.vobids, self.chapter_mode)


class Ctx:
    def __init__(self,dvds: dict = {}):
        self.dvds = dvds

    def load_dvdstxt_folder(self,file: str,dvdpath: str = "dvds.txt"):
        self.dvds |= load_dvds_from_txt(os.path.join(os.path.dirname(os.path.realpath(file)), dvdpath))

    def lambdify_eps(self, eps: dict,filter_callback = None) -> dict:
        leps = dict()
        for k in eps.keys():
            if callable(eps[k]):
                leps[k] = eps[k]
            else:
                if callable(filter_callback):
                    leps[k] = functools.partial(filter_callback,inner_fn=eps[k].make_lambda())
                else:
                    leps[k] = eps[k].make_lambda()

        return leps

def load_dvds_from_txt(path: str) -> dict:
    m = dict()
    for l in open(path,"rt").readlines():
        p = l.partition("=")
        name, path = p[0],p[2].strip()
        m[name] = path
    return m

def mpv_play_pgc_cell(dvdpath: str,vts: int,pgc_nr: int,cell_nr: List[int]):
    dvd = DVD(dvdpath)
    vts = dvd.vts[vts]
    cl = []
    for a in cell_nr:
        cp = vts.json["vts_pgcit"][pgc_nr-1]["cell_position"][a-1]
        cl += vts.vts_adt.get_sector_list_vobidcellid(cp["vob_id_nr"],cp["cell_nr"])
    asd = vts.title.cutout(cl)
    mpv_send_to_raw(asd)

#bytes only use for example vob inside gray clip
def mpv_send_to_raw(asd: vs.VideoNode):
    i = 404
    import socket

    import threading
    import subprocess

    TCP_IP = '127.0.0.1'
    

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind((TCP_IP, 0))
    s.listen(1)

    port = s.getsockname()[1]
    subprocess.Popen(["mpv",f"tcp://{TCP_IP}:{port}","--cache=yes","--keep-open","--force-seekable=no", "--demuxer-max-back-bytes=10GiB"])
    conn, addr = s.accept()
    n = 0
    try:
        while True:
            if n >= len(asd):
                break
            bytez = asd.get_frame(n)[0]
            n += 1

            data = conn.send(bytez)
    except:
        pass
    conn.close()
    print("CLOSED")
