# simple script to generate a map file from an image
# requires PIL
from PIL import Image;
import sys;
img = Image.open("map.png");
w,h = img.size;
map = [];
map += [6, 0] # data start
map += [w&0xFF, (w>>8)]; # width (little endian)
map += [h&0xFF, (h>>8)]; # height (little endian)
dict = {
  # color: province id
  (255, 255, 255, 255): 0,
  (0, 0, 255, 255): 1,
  (255, 255, 0, 255): 2,
  (255, 0, 0, 255): 3,
  (64, 64, 64, 255): 4,
  (0, 255, 0, 255): 5,
  (255, 127, 0, 255): 6,
  (0, 127, 0, 255): 7,
  (127, 0, 0, 255): 8,
  (0, 0, 127, 255): 9,
  (0, 255, 255, 255): 10,
  (87, 0, 127, 255): 11,
  (178, 0, 255, 255): 12,
  (0, 148, 255, 255): 13,
  (255, 0, 110, 255): 14,
  (127, 51, 0, 255): 15,
  (252, 205, 229, 255): 16,
  (128, 128, 128, 255): 17,
  (204, 204, 204, 255): 18
}
for y in range(h):
  for x in range(w):
    color = img.getpixel((x,y));
    if color in dict:
      id = dict[color];
      map += [id&0xFF, (id>>8)];
    else:
      map += [0, 0]; # assume province ID 0
map = bytes(map);
with open("map.bin", "wb") as f:
  f.write(map);