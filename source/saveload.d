module saveload;

import std.conv, std.zlib, std.file, std.string;
import app, map, script;

/// Converts a string to an array of bytes.
ubyte[] toArray(string s) {
  ubyte[] res;
  foreach(char c; s) res ~= cast(ubyte)c;
  return res;
}

/// Converts an array of bytes to a string.
string fromArray(ubyte[] a) {
  string res;
  foreach(ubyte b; a) res ~= cast(char)b;
  return res;
}

/// Saves the current game given a version number.
ubyte[] save(ushort ver) {
  ubyte[] file;
  file ~= [ver & 0xFF, ver >> 8]; // format (little endian)
  final switch(ver) {
    case 0: {
      file ~= [0, 0]; // data start, (reserving for later)
      file ~= tagOf(player).toArray()~0; // player tag
      ushort data = to!ushort(file.length);
      // store data position
      file[2] = data&0xFF;
      file[3] = (data>>8)&0xFF;
      string script = "";
      script ~= format("turn %d;", turn);
      foreach(ushort id, Province p; provinces) {
        if(p.ocean) continue;
        script ~= format("province %d {", id);
        script ~= format(`owner "%s";`, tagOf(p.owner));
        script ~= format(`troops %d;`, p.troops);
        script ~= "}";
      }
      foreach(string tag, Country c; countries) {
        script ~= format(`country "%s" {`, tag);
        script ~= format(`capital %d;`, c.capital);
        script ~= "}";
      }
      file ~= script.toArray().compress();
    }
  }
  return file;
}

/// Loads a game from a save file.
void load(ubyte[] save) {
  int ptr = 0;
  ubyte next() {
    return save[ptr++];
  }
  ushort nexts() {
    return next | (next<<8);
  }
  ubyte curr() {
    return save[ptr];
  }
  ushort ver = nexts;
  final switch(ver) {
    case 0: {
      ushort start = nexts;
      string tag = "";
      while(curr != 0) tag ~= cast(char)next;
      string script = (cast(ubyte[])save[start..$].uncompress()).fromArray();
      interpret(parseScript(script), new GlobalScope(), null);
      gameMode = GameMode.GAME;
      player = &(countries[tag]);
      firstTurn = true;
    }
  }
}

/// Lists all saved games.
string saveList() {
  string s = "";
  foreach(string file; dirEntries("./data/saves/", SpanMode.shallow)) {
    if(file.endsWith(".qsf")) {
      string saveName = file[file.lastIndexOf("/")+1..$-4];
      s ~= format("%s\n", saveName);
    }
  }
  return s;
}