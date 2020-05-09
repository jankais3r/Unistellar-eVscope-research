#!/bin/bash
for f in ~/Desktop/evscope/media_rw/files/*
do
	echo "Processing $(basename $f) file..."
	file_size_kb=`du -k "$f" | cut -f1`
	if [ $file_size_kb -gt 2000 ]; then
		cat "$f" | tail -c +263 > ~/Desktop/tmp.fbo
		bayer2rgb --input ~/Desktop/tmp.fbo --output $f.tiff --width 1304 --height 976 -t --bpp 16 --first RGGB --method BILINEAR
	else
		bayer2rgb --input $f --output $f.tiff --width 992 --height 976 -t --bpp 16 --first RGGB --method BILINEAR
	fi
done
rm ~/Desktop/tmp.fbo