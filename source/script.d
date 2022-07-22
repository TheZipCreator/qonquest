module qonquest.script;

import qonquest.map;
import std.string, std.file, std.array, std.conv, std.typecons;
import arsd.terminal;

class Node {
  int line;
  override string toString() {
    return "";
  }
  string name() {
    return "";
  }
  string getType() {
    return "";
  }
}

string nodeArrayToString(Node[] nodes) {
  string s = "";
  for(int i = 0; i < nodes.length; i++) {
    if(i > 0) s ~= " ";
    s ~= nodes[i].toString();
  }
  return s;
}

class Lexeme : Node {
  enum LexemeType {
    SYMBOL, INT, STRING,
    SEMICOLON, LBRACE, RBRACE,
    EOF
  }
  LexemeType type;
  string value;
  this(int line, string value, LexemeType type) {
    this.line = line;
    this.value = value;
    this.type = type;
  }
  override string toString() {
    return value;
  }
  override string name() {
    return format("\"%s\"", value);
  }
}

alias LType = Lexeme.LexemeType;
const Lexeme EOF = new Lexeme(-1, "", LType.EOF);

class Block : Node {
  Node[] contents;
  this(int line, Node[] contents) {
    this.line = line;
    this.contents = contents;
  }
  override string toString() {
    return format("BLOCK { %s }", nodeArrayToString(contents));
  }
  override string name() {
    return "BLOCK";
  }
}

class ScriptException : Exception {
  int line;
  this(int line, string message) {
    super(message);
    this.line = line;
  }
}

enum Error {
  INVALID_ESCAPE_SEQUENCE = "Invalid escape sequence: %s",
  UNMATCHED = "Unmatched %s",
  UNEXPECTED = "Unexpected %s",
  EXPECTED = "Expected %s, got %s",
  INCORRECT_SCOPE = "Incorrect scope: %s",
  UNKNOWN_TAG = "Unknown country tag \"%s\"",
}

Block[string] scripts;

void loadScripts(string dir, Terminal* t) {
  void loadScript(string script) {
    string code = std.file.readText(script);
    // 1. lex
    Lexeme[] lexemes;
    {
      string value = "";
      int line = 1;
      enum State {
        START, STRING, COMMENT
      }
      State state = State.START;
      void add() {
        if(value != "") {
          if(isNumeric(value)) {
            lexemes ~= new Lexeme(line, value, LType.INT);
          } else {
            lexemes ~= new Lexeme(line, value, LType.SYMBOL);
          }
          value = "";
        }
      }
      void op(string o, LType t) {
        add();
        lexemes ~= new Lexeme(line, o, t);
      }
      for(int i = 0; i < code.length; i++) {
        char c = code[i];
        char next = i+1 < code.length ? code[i+1] : '\0';
        final switch(state) {
          case State.START:
            switch(c) {
              case ' ':
              case '\t':
                add();
                break;
              case '\n':
                add();
                line++;
                break;
              case '\r':
                break; // every single time I make a lexer I ALWAYS forget to add this. thanks windows.
              case '"':
                state = State.STRING;
                break;
              case ';':
                op(";", LType.SEMICOLON);
                break;
              case '{':
                op("{", LType.LBRACE);
                break;
              case '}':
                op("}", LType.RBRACE);
                break;
              case '#':
                state = State.COMMENT;
                break;
              default:
                value ~= c;
                break;
            }
            break;
          case State.STRING:
            switch(c) {
              case '"':
                lexemes ~= new Lexeme(line, value, LType.STRING);
                value = "";
                state = State.START;
                break;
              case '\\':
                switch(next) {
                  case 'n':
                    value ~= '\n';
                    i++;
                    break;
                  case 't':
                    value ~= '\t';
                    i++;
                    break;
                  case '"':
                    value ~= '"';
                    i++;
                    break;
                  case '\\':
                    value ~= '\\';
                    i++;
                    break;
                  default:
                    throw new ScriptException(line, format(Error.INVALID_ESCAPE_SEQUENCE, next));
                }
                break;
              default:
                value ~= c;
                break;
            }
            break;
          case State.COMMENT:
            switch(c) {
              case '\n':
                state = State.START;
                line++;
                break;
              default:
                break;
            }
            break;
        }
      }
      op("", LType.EOF);
    }
    // 2. parse
    Node[] stack;
    bool isLexeme(Node n, LType t) {
      if(cast(Lexeme)n) return (cast(Lexeme)n).type == t;
      return false;
    }
    for(int i = 0; i < lexemes.length; i++) {
      Lexeme l = lexemes[i];
      switch(l.type) {
        case LType.RBRACE: {
          int j;
          for(j = cast(int)(stack.length)-1; j >= 0 && !isLexeme(stack[j], LType.LBRACE); j--) {}
          if(j < 0) throw new ScriptException(l.line, format(Error.UNMATCHED, "}"));
          int line = lexemes[j].line;
          Node[] contents = stack[j+1..$];
          stack = stack[0..j];
          stack ~= new Block(line, contents);
          break;
        }
        default:
          stack ~= l;
      }
    }
    // 3. store
    scripts[script] = new Block(0, stack);
  }
  foreach(string file; dirEntries(dir, SpanMode.breadth)) {
    file = file.replace("\\", "/"); // make sure slashes are consistent
    if(isFile(file) && file.endsWith(".qsc")) {
      if(file in scripts) continue; // already loaded
      try {
        loadScript(file);
        t.writefln("Loaded script: %s", file);
      } catch(ScriptException e) {
        t.color(Color.red, Color.black);
        t.writef("Error loading script %s: ", file);
        t.color(Color.white, Color.black);
        t.writeln(e.message);
      }
    }
  }
}

int[string] globalVars;

interface Scope {
  // represents the current scope of a script
  
  void setVar(string name, int value);
  int getVar(string name);
}

class GlobalScope : Scope {
  void setVar(string name, int value) {
    globalVars[name] = value;
  }
  int getVar(string name) {
    return globalVars[name];
  }
  override string toString() {
    return "Global";
  }
}

class CountryScope : Scope {
  Country* c;
  this(Country* c) {
    this.c = c;
  }
  void setVar(string name, int value) {
    c.vars[name] = value;
  }
  int getVar(string name) {
    return c.vars[name];
  }
  override string toString() {
    return format("Country %s", c.name);
  }
}

class ProvinceScope : Scope {
  Province* p;
  this(Province* p) {
    this.p = p;
  }
  void setVar(string name, int value) {
    p.vars[name] = value;
  }
  int getVar(string name) {
    return p.vars[name];
  }
  override string toString() {
    return format("Province %s", p.name);
  }
}

void interpret(Node[] nodes, Scope s, Terminal* t) {
  int lastLine = 0;
  bool isLexeme(Node n, LType t) {
    if(cast(Lexeme)n) return (cast(Lexeme)n).type == t;
    return false;
  }
  Node next() {
    Node n = nodes[0];
    nodes = nodes[1..$];
    return n;
  }
  Node peek() {
    return nodes[0];
  }

  Lexeme expect(LType lt) {
    Node n = next();
    if(!isLexeme(n, lt)) {
      throw new ScriptException(n.line, format(Error.EXPECTED, lt, n.name()));
    }
    return cast(Lexeme)n;
  }
  Lexeme[] expectListOf(LType lt) {
    Lexeme[] list;
    while(isLexeme(peek(), lt)) {
      list ~= expect(lt);
    }
    return list;
  }
  Block expectBlock() {
    Node n = next();
    if(cast(Block)n) return cast(Block)n;
    throw new ScriptException(n.line, format(Error.EXPECTED, "BLOCK", n.name()));
  }
  void incorrectScope(int line) {
    throw new ScriptException(line, format(Error.INCORRECT_SCOPE, s));
  }

  while(true) {
    Node n = next();
    if(Lexeme l = cast(Lexeme)n) {
      switch(l.type) {
        default:
          throw new ScriptException(l.line, format(Error.UNEXPECTED, l.name()));
        case LType.EOF:
          return;
        case LType.SYMBOL:
          switch(l.value) {
            case "ocean": 
              if(ProvinceScope ps = cast(ProvinceScope)s) ps.p.ocean = true;
              else incorrectScope(l.line);
              expect(LType.SEMICOLON);
              break;
            case "name":
              if(ProvinceScope ps = cast(ProvinceScope)s) {
                ps.p.name = expect(LType.STRING).value;
                expect(LType.SEMICOLON);
              } else if(CountryScope cs = cast(CountryScope)s) {
                cs.c.name = expect(LType.STRING).value;
                expect(LType.SEMICOLON);
              } else incorrectScope(l.line);
              break;
            case "color":
              if(ProvinceScope ps = cast(ProvinceScope)s) {
                ps.p.color = to!ubyte(expect(LType.INT).value);
                expect(LType.SEMICOLON);
              } else if(CountryScope cs = cast(CountryScope)s) {
                cs.c.color = to!ubyte(expect(LType.INT).value);
                expect(LType.SEMICOLON);
              } else incorrectScope(l.line);            
              break;
            case "city":
              if(ProvinceScope ps = cast(ProvinceScope)s) {
                ps.p.city = tuple(to!ushort(expect(LType.INT).value), to!ushort(expect(LType.INT).value));
                expect(LType.SEMICOLON);
              } else incorrectScope(l.line);
              break;
            case "owner":
              if(ProvinceScope ps = cast(ProvinceScope)s) {
                string tag = expect(LType.STRING).value;
                if(tag in countries) {
                  ps.p.owner = &(countries[tag]);
                  expect(LType.SEMICOLON);
                } else {
                  throw new ScriptException(l.line, format(Error.UNKNOWN_TAG, tag));
                }
              } else incorrectScope(l.line);
              break;
            case "capital":
              if(CountryScope cs = cast(CountryScope)s) {
                cs.c.capital = to!ushort(expect(LType.INT).value);
                expect(LType.SEMICOLON);
              } else incorrectScope(l.line);
              break;
            case "adjacent":
              if(ProvinceScope ps = cast(ProvinceScope)s) {
                Lexeme[] adj = expectListOf(LType.INT);
                for(int i = 0; i < adj.length; i++) {
                  ps.p.adjacencies ~= to!ushort(adj[i].value);
                }
                expect(LType.SEMICOLON);
              } else incorrectScope(l.line);
              break;
            case "print":
              t.writeln(expect(LType.STRING).value);
              expect(LType.SEMICOLON);
              break;
            case "registerCountry": {
              Lexeme[] countries = expectListOf(LType.STRING);
              foreach(Lexeme c; countries) {
                registerCountry(c.value, t);
              }
              expect(LType.SEMICOLON);
              break;
            }
            case "global":
              interpret(expectBlock().contents, new GlobalScope(), t);
              break;
            case "province": {
              ushort id = to!ushort(expect(LType.INT).value);
              interpret(expectBlock().contents, new ProvinceScope(&(provinces[id])), t);
              break;
            }
            case "country": {
              string tag = expect(LType.STRING).value;
              interpret(expectBlock().contents, new CountryScope(&(countries[tag])), t);
              break;
            }
            default:
              throw new ScriptException(l.line, format(Error.UNEXPECTED, l.name()));
          }
          break;
      }
    } else if(Block b = cast(Block)n) {
      interpret(b.contents, s, t);
    }
  }
}

void runScript(string script, Scope s, Terminal* t) {
  void err(string msg) {
    t.color(Color.red, Color.black);
    t.writef("Error running script %s: ", script);
    t.color(Color.white, Color.black);
    t.writeln(msg);
  }
  if(script in scripts) {
    try {
      interpret(scripts[script].contents, s, t);
    } catch(ScriptException e) {
      err(format("Line %d: %s", e.line, e.message));
    }
  } else {
    err("Script not found");
  }
}