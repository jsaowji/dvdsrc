# problematics streams found in the wild

## higher timeref than framecnt

""fixed"" in fixGop

PIC+SLICE I time_ref 0
PIC+SLICE P time_ref 3
PIC+SLICE B time_ref 1
PIC+SLICE B time_ref 2
PIC+SLICE P time_ref 6


# decodes garbage
first gop not closed and has 2 B frames
bestsource drops frames lsmas and d2v somehow display black


# last gop has picture slice picture slice picture

missing a slice at the end and we going back to buffering and crash