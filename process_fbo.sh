#!/bin/bash
for f in ~/Desktop/evscope/media_rw/files/*
do
	echo "Processing $f file..."
	cat "$f" | tail -c +263 | magick -size 1304x976 -depth 16 "GRAY:-" $f.png || cat "$f" | magick -size 992x976 -depth 16 "GRAY:-" $f.png
done