module map; /// handles map loading, drawing, and holds map-related classes

import script, app, action;
import std.file, std.typecons, std.stdio, std.string, std.traits, std.typecons, std.random;
import arsd.terminal;

ushort mapWidth;
ushort mapHeight;

/// Represents a single province in the map.
struct Province {
  Tuple!(ushort, ushort)[] tiles; /// Every tile in the province.
  bool ocean = false; /// Whether the province is ocean or not.
  string name = ""; /// The name of the province.
  Country* owner; /// Pointer to the country that owns the province.
  ubyte color = 0; /// The color of the province. (see: qonquest.app.color)
  Tuple!(ushort, ushort) city; /// Location of the city of the province.
  int[string] vars; /// Variables for the province. (currently unused)
  int troops = 0; /// The number of troops in the province.
  ushort[] adjacencies; /// The provinces that are adjacent to this one.
  char ch = ' '; /// The character to draw for the province.
}
Province[ushort] provinces; /// List of all provinces in the map.
/// Finds a province by name
Tuple!(Province*, ushort) findProvince(string name) {
  foreach(ushort i, ref Province p; provinces) {
    if(p.name == name) return tuple(&p, i);
  }
  return Tuple!(Province*, ushort)(null, 0);
}

/// Represents a single country in the map.
class Country {
  string name; /// The name of the country.
  ubyte color; /// The color of the country. (see: qonquest.app.color)
  ushort capital; /// The province that is the capital of the country.
  int[string] vars; /// Variables for the country. (currently unused)
  char ch = ' '; /// The character to draw for the country.
  this() {}

  Province[] getAllProvinces() {
    /// Returns all provinces that are owned by the country.
    Province[] res;
    foreach(Province p; provinces)
      if(p.owner != null && *(p.owner) == this)
        res ~= p;
    return res;
  }

  /// Returns the IDs of all provinces that are owned by the country.
  ushort[] getAllProvinceIDs() {
    ushort[] res;
    foreach(ushort i, Province p; provinces)
      if(p.owner != null && *(p.owner) == this)
        res ~= i;
    return res;
  }

  /// Returns the amount of troops gained per turn
  int troopsPerTurn() {
    return cast(int)(getAllProvinces().length*2);
  }

  /**
    Returns all provinces on the border of this country as a tuple of
    [0] = province from (owned by this country)
    [1] = province to (owned by other country)
  */
  Tuple!(Province*, Province*)[] frontiers() {
    Tuple!(Province*, Province*)[] res;
    foreach(ref Province p; provinces) {
      foreach(ushort j; p.adjacencies) {
        if(p.owner != null && *(p.owner) == this && provinces[j].owner != null && *(provinces[j].owner) != this) {
          res ~= tuple(&p, &(provinces[j]));
        }
      }
    }
    return res;
  }

  /// Runs the AI for the country.
  void ai(Terminal* t) {
    t.write("Running AI for ");
    t.color(colors[color], Color.black);
    t.writefln("%s", name);
    t.color(Color.white, Color.black);

    int troopsRemaining = troopsPerTurn();
    auto frontiers = frontiers();
    auto rnd = Random(unpredictableSeed);
    // distribute troops
    while(troopsRemaining > 0 && frontiers.length > 0) {
      int idx = rnd.front%cast(int)(frontiers.length);
      rnd.popFront();
      frontiers[idx][0].troops++;
      troopsRemaining--;
    }
    if(turn > 1) {
      Action[] actions;
      foreach(f; frontiers) {
        if(f[0].troops != 0) { // if we have troops to move
          if(f[0].troops >= f[1].troops) { // if we have more troops than the other country
            actions ~= new MoveAction(f[0], f[1]); // attack
          }
        }
      }
      commitAll(actions, t);
    }
  }

  /// Updates the country.
  void update(Terminal* t) {
    ushort[] provs = getAllProvinceIDs();
    auto rnd = Random(unpredictableSeed);
    if(*(provinces[capital].owner) != this && provs.length > 0) {
      // capital has been conquered
      // set new capital to random owned province
      ushort newCap = provs[rnd.front%cast(int)(provs.length)];
      capital = newCap;
    }
  }
}
Country[string] countries; /// List of all countries in the map.
/// Finds a country by name
Country* findCountry(string name) {
  foreach(ref Country c; countries) {
    if(c.name == name) return &c;
  }
  return null;
}
/// Returns a tag of a country, given a pointer to the country. Returns "" if the country can not be found.
string tagOf(Country* c) {
  foreach(string tag, ref Country c2; countries) {
    if(c == &c2) return tag;
  }
  return "";
}
/// Represents a strait on the map
struct Strait {
  Tuple!(ushort, ushort) from;
  Tuple!(ushort, ushort) to;
}
Strait[] straits; /// List of all straits in the map.

/// Loads provinces from a map file (generated by mapgen.py)
void loadMap(string file, Terminal* t) {
  Province[ushort] empty;
  provinces = empty; // reset provinces. idk if this is how you're supposed to do it, but it works
  ubyte[] data = cast(ubyte[])std.file.read(file);
  int dataStart = data[0] | (data[1] << 8); // where the map data starts
  mapWidth = data[2] | (data[3] << 8); // width of the map
  mapHeight = data[4] | (data[5] << 8); // height of the map
  for(ushort i = 0; i < mapWidth*mapHeight; i++) {
    ushort x = i%mapWidth;
    ushort y = i/mapWidth;
    ushort id = data[dataStart+i*2] | (data[dataStart+i*2+1] << 8);
    if(id in provinces) {
      // add tile to province
      provinces[id].tiles ~= tuple(x, y);
    } else {
      // create new province and run province setup
      provinces[id] = Province([tuple(x, y)]);
      runScript(format("./data/scripts/provinces/%d.qsc", id), new ProvinceScope(&(provinces[id])), t);
    }
  }
}

// for some reason I need 2 different methods for creating a 2d array
// the first acts on primitives (ints, floats, etc)
// the second acts on everything else
T[][] create2dArrayPrim(T)(int width, int height) {
  T[][] arr;
  for(int i = 0; i < width; i++) {
    T[] row;
    for(int j = 0; j < height; j++) {
      row ~= *(new T());
    }
    arr ~= row;
  }
  return arr;
}
T[][] create2dArray(T)(int width, int height) {
  T[][] arr;
  for(int i = 0; i < width; i++) {
    T[] row;
    for(int j = 0; j < height; j++) {
      row ~= new T();
    }
    arr ~= row;
  }
  return arr;
}

/// returns a 2D array of ushorts, where each element is the ID of the province at that location
ushort[][] constructMap() {
  ushort[][] map = create2dArrayPrim!ushort(mapWidth, mapHeight);
  foreach(ushort id, Province p; provinces) {
    foreach(Tuple!(int, int) t; p.tiles) {
      map[t[0]][t[1]] = id;
    }
  }
  return map;
}

enum MapRenderType {
  PROVINCE, COUNTRY
}

class Tile {
  Tuple!(int, int) col;
  dchar c;
  this() {
    c = ' ';
    col = tuple(Color.white, Color.black);
  }
  this(dchar c, Tuple!(int, int) col) {
    this.c = c;
    this.col = col;
  }
}

void renderTiles(Tile[][] tiles, int w, int h, Terminal* t) {
  for(int i = 0; i < h; i++) {
    for(int j = 0; j < w; j++) {
      Tile tile = tiles[j][i];
      t.color(tile.col[0], tile.col[1]);
      t.write(tile.c);
    }
    t.writeln();
  }
  t.color(Color.white, Color.black);
}

/// Renders the map
void renderMap(MapRenderType mrt, Terminal* t) {
  ushort[][] provs = constructMap();
  Tile[][] tiles = create2dArray!Tile(mapWidth, mapHeight);
  void tileWriteColor(int x, int y, string s, Tuple!(int, int) col) {
    for(int i = 0; i < s.length; i++) {
      tiles[x+i][y].c = s[i];
      tiles[x+i][y].col = col;
    }
  }
  void tileWrite(int x, int y, string s, int fg) {
    for(int i = 0; i < s.length; i++) {
      if(x+i >= mapWidth) continue;
      tiles[x+i][y].c = s[i];
      tiles[x+i][y].col[0] = fg;
    }
  }
  final switch(mrt) {
    case MapRenderType.PROVINCE:
      for(int y = 0; y < mapHeight; y++) {
        for(int x = 0; x < mapWidth; x++) {
          Province p = provinces[provs[x][y]];
          if(p.ocean) {
            tiles[x][y] = new Tile('~', tuple(colors[p.color], cast(int)(Color.black)));
          } else {
            tiles[x][y] = new Tile(p.ch, tuple(cast(int)(Color.white), colors[p.color]));
          }
          
        }
      }
      foreach(Province p; provinces) {
        if(p.ocean) continue;
        tileWriteColor(p.city[0], p.city[1], "@", tuple(cast(int)(Color.white), colors[p.color]));
        string s = format("%s, %s", p.name, p.owner.name);
        int x = cast(int)(p.city[0]-(s.length/2));
        tileWrite(x, p.city[1]+1, s, cast(int)Color.white);
        s = format("%d", p.troops);
        x = cast(int)(p.city[0]-(s.length/2));
        tileWrite(x, p.city[1], s, cast(int)Color.white);
      }
      break;
    case MapRenderType.COUNTRY:
      for(int y = 0; y < mapHeight; y++) {
        for(int x = 0; x < mapWidth; x++) {
          Province p = provinces[provs[x][y]];
          if(p.ocean) {
            tiles[x][y] = new Tile('~', tuple(colors[p.color], cast(int)(Color.black)));
          } else {
            if(p.owner != null) tiles[x][y] = new Tile(p.owner.ch, tuple(cast(int)(Color.white), colors[p.owner.color]));     
          }
        }
      }
      foreach(Country c; countries) {
        if(c.getAllProvinces().length > 0) { // make sure country exists
          Province capital = provinces[c.capital];
          int x = cast(int)(capital.city[0]-(c.name.length/2));
          tileWrite(x, capital.city[1], c.name, cast(int)(Color.white));
        }
      }
      break;
  }
  // add straits
  foreach(Strait s; straits) {
    ushort x0 = s.from[0];
    ushort y0 = s.from[1];
    ushort x1 = s.to[0];
    ushort y1 = s.to[1];
    void d() {
      if(tiles[x0][y0].c == '~')
        tiles[x0][y0] = new Tile('#', tuple(cast(int)(Color.red | Bright), cast(int)(Color.black)));
    }
    d();
    while(x0 != x1 || y0 != y1) {
      if(x0 < x1) x0++;
      if(x0 > x1) x0--;
      if(y0 < y1) y0++;
      if(y0 > y1) y0--;
      d();
    }
  }
  renderTiles(tiles, mapWidth, mapHeight, t);
  t.color(Color.white, Color.black);
}

/// Registers a country with the game (triggered by the qsc command "registerCountry")
void registerCountry(string tag, Terminal* t) {
  countries[tag] = new Country();
  runScript(format("./data/scripts/countries/%s.qsc", tag), new CountryScope(&(countries[tag])), t);
}