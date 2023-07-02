#include <dvdread/dvd_reader.h>
#include <dvdread/ifo_read.h>

#include <dvdread/ifo_types.h>
#include <iostream>
#include <ranges>

#include <iostream>
#include <sstream>

#include "bindings/json.hpp"
using json = nlohmann::json;

json dvdtime_to_json(dvd_time_t *time) {
  json j;
  j["hour"] = time->hour;
  j["minute"] = time->minute;
  j["second"] = time->second;
  j["frame_u"] = time->frame_u;
  return j;
}

json process_pgcit(pgcit_t *pgcit) {
  json pgcs = json::array();
  for (auto j = 0; j < pgcit->nr_of_pgci_srp; j++) {
    auto pgci = pgcit->pgci_srp[j];
    auto pgc = pgci.pgc;
    json jpgc;

    jpgc["nr_of_cells"] = pgc->nr_of_cells;
    jpgc["nr_of_programs"] = pgc->nr_of_programs;

    {
      json program_map = json::array();

      for (auto i = 0; i < pgc->nr_of_programs; i++) {
        program_map.push_back(pgc->program_map[i]);
      }
      jpgc["program_map"] = program_map;
    }

    {
      json cell_playback = json::array();
      for (unsigned int i = 0; i < pgc->nr_of_cells; i++) {
        auto pb = pgc->cell_playback[i];

        json current;
        current["interleaved"] = (bool)pb.interleaved;
        current["seamless_play"] = (bool)pb.seamless_play;
        current["seamless_angle"] = (bool)pb.seamless_angle;
        current["first_sector"] = (uint32_t)pb.first_sector;
        current["last_sector"] = (uint32_t)pb.last_sector;
        current["block_mode"] = (uint32_t)pb.block_mode;
        current["block_type"] = (uint32_t)pb.block_type;
        current["first_ilvu_end_sector"] = (uint32_t)pb.first_ilvu_end_sector;
        current["last_vobu_start_sector"] = (uint32_t)pb.last_vobu_start_sector;
        current["playback_time"] = dvdtime_to_json(&pb.playback_time);
        cell_playback.push_back(current);
      }
      jpgc["cell_playback"] = cell_playback;
    }

    {
      json cell_position = json::array();
      for (unsigned int i = 0; i < pgc->nr_of_cells; i++) {
        json current;
        current["cell_nr"] = (uint32_t)pgc->cell_position[i].cell_nr;
        current["vob_id_nr"] = (uint32_t)pgc->cell_position[i].vob_id_nr;
        cell_position.push_back(current);
      }
      jpgc["cell_position"] = cell_position;
    }

    pgcs.push_back(jpgc);
  }
  return pgcs;
}

extern "C" char *getstring(char *bigbuffer, dvd_reader_t *dvd,
                           const char *dvdpath, uint32_t current_vts) {
  auto ifo = ifoOpen(dvd, 0);

  json a;

  auto nr = ifo->vts_atrt->nr_of_vtss;
  json ifos = json::array();

  if (dvdpath) {
    a["dvdpath"] = std::string(dvdpath);
    a["current_vts"] = current_vts;
  }

  for (auto i = 0; i < nr + 1; i++) {
    auto ifo2 = ifoOpen(dvd, i);
    json vts;

    // VMG AND VTS, Menu PGCI Unit Table
    if (ifo2->pgci_ut) {
      json lus = json::array();
      for (auto j = 0; j < ifo2->pgci_ut->nr_of_lus; j++) {
        auto pgci = ifo2->pgci_ut->lu[j];
        auto jpgc = process_pgcit(pgci.pgcit);
        json lu;
        lu["pgcs"] = jpgc;
        lus.push_back(lu);
      }
      vts["pgci_ut"] = lus;
    } else {
      vts["pgci_ut"] = json::array();
    }

    if (ifo2->tt_srpt) {
      auto tt_srpt = ifo2->tt_srpt;
      json jj = json::array();
      for (auto i = 0; i < tt_srpt->nr_of_srpts; i++) {
        auto title = tt_srpt->title[i];
        json ll;

        ll["title_set_nr"] = title.title_set_nr;
        ll["title_set_sector"] = title.title_set_sector;
        ll["nr_of_angles"] = title.nr_of_angles;
        ll["nr_of_ptts"] = title.nr_of_ptts;
        ll["vts_ttn"] = title.vts_ttn;

        jj.push_back(ll);
      }
      vts["tt_srpt"] = jj;
    }

    if (ifo2->vts_pgcit) {
      auto jpgc = process_pgcit(ifo2->vts_pgcit);
      vts["pgcs"] = jpgc;
    } else {
      vts["pgcs"] = json::array();
    }

    if (ifo2->vts_ptt_srpt) {
      auto titles = json::array();

      for (int i = 0; i < ifo2->vts_ptt_srpt->nr_of_srpts; i++) {
        json tt = json::array();
        auto lel = ifo2->vts_ptt_srpt->title[i];
        for (int j = 0; j < lel.nr_of_ptts; j++) {
          json jj;
          jj["pgcn"] = lel.ptt[j].pgcn;
          jj["pgn"] = lel.ptt[j].pgn;
          tt.push_back(jj);
        }

        titles.push_back(tt);
      }
      vts["vts_ptt_srpt"] = titles;
    } else {
      vts["vts_ptt_srpt"] = json::array();
    }

    ifos.push_back(vts);

    ifoClose(ifo2);
  }
  a["ifos"] = ifos;

  std::stringstream ss;
  ss << a;
  auto string = ss.str();
  strcpy(bigbuffer, string.c_str());

  ifoClose(ifo);
  return bigbuffer;
}
