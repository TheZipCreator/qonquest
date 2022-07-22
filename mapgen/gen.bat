@echo off
python mapgen.py
cat map.bin > ../data/map.bin
echo Done!