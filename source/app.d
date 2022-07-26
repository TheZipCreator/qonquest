module app;

import map, script, action, saveload;
import std.stdio, std.string, std.file, std.conv, std.algorithm, std.typecons;
import core.stdc.stdlib : exit;
import arsd.terminal;

int[] colors = [Color.black, Color.red, Color.green, Color.yellow, Color.blue, Color.magenta, Color.cyan, Color.white, Color.black | Bright, Color.red | Bright, Color.green | Bright, Color.yellow | Bright, Color.blue | Bright, Color.magenta | Bright, Color.cyan | Bright, Color.white | Bright];
/*
For convinience:
0 - black
1 - red
2 - green
3 - yellow
4 - blue
5 - magenta
6 - cyan
7 - white
8 - black | Bright
9 - red | Bright
10 - green | Bright
11 - yellow | Bright
12 - blue | Bright
13 - magenta | Bright
14 - cyan | Bright
15 - white | Bright
*/

enum GameMode {
  /**
    GameMode is used to represent what state the game currently is in.
  **/
  MAIN_MENU, /// Main Menu
  GAME /// Mid-game
}

GameMode gameMode;

/**
  Error contains the string representation of errors that can occur in the game. 
  These are formatted using D's format() function.
**/
enum Error {
  COMMAND_REQUIRES_ARGS = "Command \"%s\" requires exactly %d arguments.",
  COMMAND_REQUIRES_AT_LEAST_ARGS = "Command \"%s\" requires at least %d arguments.",
  NO_COMMAND = "No command \"%s\" found.",
  INVALID_SUBCOMMAND = "Invalid subcommand \"%s\".",
  COUNTRY_DOESNT_EXIST = "Country \"%s\" doesn't exist.",
  PROVINCE_DOESNT_EXIST = "Province \"%s\" doesn't exist.",
  NOT_ENOUGH_TROOPS = "You have %d troops, but are attempting to deploy %d troops.",
  NOT_NUMBER = "\"%s\" is not a number.",
  NOT_DEPLOYED_ALL_TROOPS = "You must deploy all your troops before ending your turn.",
  CANT_MOVE_TURN_1 = "You cannot move troops on turn 1.",
  PROVINCE_NOT_OWNED = "You do not own %s.",
  NOT_ADJACENT = "%s is not adjacent to %s.",
  NO_TOGGLE = "Toggle \"%s\" does not exist.",
  INVALID_AMOUNT = "Invalid amount %s.",
}

/// CommandException is used to represent errors that occur when a command is executed.
class CommandException : Exception {
  this(string message) {
    super(message);
  }
}

Country* player; /// Pointer to the country the player is playing as
Action[] actions; /// List of actions that have been performed by the player this turn
int turn = 0; /// The turn number
int troopsToDeploy = 0; /// The number of troops the player has to deploy this turn
bool[string] toggles; /// List of toggles that may be enabled or disabled
bool firstTurn = true; /// Whether or not the player is on the first turn (this may seem redundant, but it's important when saves are loaded)

void main() {
  auto t = Terminal(ConsoleOutputType.linear);
  t.color(Color.white, Color.black);
  t.clear();
  try {
    loadScripts("./data/scripts", &t);
    runScript("./data/scripts/launch.qsc", new GlobalScope(), &t);
    loadMap("./data/map.bin", &t);
    changeMode(GameMode.MAIN_MENU, &t);
    toggles["waitBattleRounds"] = false;
    toggles["seeAllBattles"] = false;
    toggles["cheats"] = false;
    void expectArgs(string cmd, string[] args, int n) {
      if(args.length != n) {
        throw new CommandException(format(Error.COMMAND_REQUIRES_ARGS, cmd, n));
      }
    }
    void expectAtLeastArgs(string cmd, string[] args, int n) {
      if(args.length < n) {
        throw new CommandException(format(Error.COMMAND_REQUIRES_AT_LEAST_ARGS, cmd, n));
      }
    }
    while(true) {
      try {
        final switch(gameMode) {
          case GameMode.MAIN_MENU: {
            t.write("$ ");
            string[] command = nextCommand(&t);
            if(command.length > 0) {
              string cmd = command[0];
              string[] args = command[1..$];
              switch(cmd) {
                case "help":
                  expectArgs(cmd, args, 0);
                  t.writeln("Main menu commands:");
                  t.writeln("  help\n\tdisplays this help message");
                  t.writeln("  map <province/country>\n\tdisplays the map");
                  t.writeln("  play <country>\n\tstarts a game as <country>");
                  t.writeln("  changelog\n\tdisplays the changelog");
                  t.writeln("  load <name>\n\tloads a saved game");
                  t.writeln("  saves\n\tdisplays a list of saved games");
                  t.writeln("  quit\n\tquits the game");
                  break;
                case "map":
                  expectArgs(cmd, args, 1);
                  switch(args[0]) {
                    case "province":
                      renderMap(MapRenderType.PROVINCE, &t);
                      break;
                    case "country":
                      renderMap(MapRenderType.COUNTRY, &t);
                      break;
                    default:
                      throw new CommandException(format(Error.INVALID_SUBCOMMAND, args[0]));
                  }
                  break;
                case "play": {
                  expectArgs(cmd, args, 1);
                  Country* c = findCountry(args[0]);
                  if(c is null) throw new CommandException(format(Error.COUNTRY_DOESNT_EXIST, args[0]));
                  player = c;
                  changeMode(GameMode.GAME, &t);
                  break;
                }
                case "changelog": {
                  expectArgs(cmd, args, 0);
                  t.writeln("Changelog:");
                  string[] changelog = readText("./data/changelog.txt").splitLines();
                  foreach(string s; changelog) {
                    if(s.indexOf("+") != -1) {
                      t.color(Color.green | Bright, Color.black);
                    } else if(s.indexOf("-") != -1) {
                      t.color(Color.red | Bright, Color.black);
                    } else if(s.indexOf("~") != -1) {
                      t.color(Color.yellow | Bright, Color.black);
                    } else {
                      t.color(Color.white, Color.black);
                    }
                    t.writeln(s);
                  }
                  t.color(Color.white, Color.black);
                  break;
                }
                case "load":
                  expectArgs(cmd, args, 1);
                  try {
                    load(cast(ubyte[])read(format("./data/saves/%s.qsf", args[0])));
                    nextTurn(&t);
                  } catch(FileException e) {
                    writefln("\nError loading save: %s", e.message);
                  }
                  break;
                case "saves":
                  expectArgs(cmd, args, 0);
                  t.writeln(saveList());
                  break;
                case "quit":
                  expectArgs(cmd, args, 0);
                  return;
                default:
                  throw new CommandException(format(Error.NO_COMMAND, cmd));
              }
            }
            break;
          }
          case GameMode.GAME: {
            t.writef("%s$ ", player.name);
            string[] command = nextCommand(&t);
            if(command.length > 0) {
              string cmd = command[0];
              string[] args = command[1..$];
              switch(cmd) {
                case "help":
                  expectArgs(cmd, args, 0);
                  t.writeln("Game commands:");
                  t.writeln("  help\n\tdisplays this help message");
                  t.writeln("  map <province/country>\n\tdisplays the map");
                  t.writeln("  quit\n\tgoes back to the main menu");
                  t.writeln("  actions\n\tdisplays all actions taken in this turn");
                  t.writeln("  move <source> <dest>\n\tMove all units from <source> to <dest>. The provinces must be adjacent.");
                  t.writeln("  deploy <amt> <province>\n\tDeploy <amt> troops to <province>");
                  t.writeln("  end\n\tends the turn");
                  t.writeln("  toggle\n\ttoggles a toggle");
                  t.writeln("  toggles\n\tdisplays all toggles");
                  t.writeln("  save <name>\n\tsaves the game to file <name>");
                  if(toggles["cheats"]) {
                    t.writeln("Cheat commands:");
                    t.writeln("  script <script>\n\texecutes a script");
                    t.writeln("  run <command>\n\truns the input as a script");
                  }
                  break;
                case "map":
                  expectArgs(cmd, args, 1);
                  switch(args[0]) {
                    case "province":
                      renderMap(MapRenderType.PROVINCE, &t);
                      break;
                    case "country":
                      renderMap(MapRenderType.COUNTRY, &t);
                      break;
                    default:
                      throw new CommandException(format(Error.INVALID_SUBCOMMAND, args[0]));
                  }
                  break;
                case "quit":
                  expectArgs(cmd, args, 0);
                  changeMode(GameMode.MAIN_MENU, &t);
                  break;
                case "actions":
                  expectArgs(cmd, args, 0);
                  foreach(Action a; actions) a.display(&t);
                  break;
                case "move": {
                  if(turn == 1) throw new CommandException(Error.CANT_MOVE_TURN_1);
                  expectArgs(cmd, args, 2);
                  Tuple!(Province*, ushort) p0 = findProvince(args[0]);
                  Tuple!(Province*, ushort) p1 = findProvince(args[1]);
                  Province* source = p0[0];
                  Province* dest = p1[0];
                  ushort destId = p1[1];
                  if(source is null) throw new CommandException(format(Error.PROVINCE_DOESNT_EXIST, args[0]));
                  if(source.owner != player) throw new CommandException(format(Error.PROVINCE_NOT_OWNED, args[0]));
                  if(dest is null) throw new CommandException(format(Error.PROVINCE_DOESNT_EXIST, args[1]));
                  if(!source.adjacencies.canFind(destId))
                    throw new CommandException(format(Error.NOT_ADJACENT, args[0], args[1]));
                  Action a = new MoveAction(source, dest);
                  t.write("Action added: ");
                  a.display(&t);
                  actions ~= a;
                  break;
                }
                case "deploy": {
                  expectArgs(cmd, args, 2);
                  try {
                    int amt = to!int(args[0]);
                    if(amt == -25) writeln("shoutouts to ibrokqr");
                    if(amt < 0) throw new CommandException(format(Error.INVALID_AMOUNT, args[0]));
                    Province* p = findProvince(args[1])[0];
                    if(p is null) throw new CommandException(format(Error.PROVINCE_DOESNT_EXIST, args[1]));
                    if(amt > troopsToDeploy) 
                      throw new CommandException(format(Error.NOT_ENOUGH_TROOPS, troopsToDeploy, amt));
                    if(p.owner != player) throw new CommandException(format(Error.PROVINCE_NOT_OWNED, p.name));
                    p.troops += amt;
                    troopsToDeploy -= amt;
                    t.writefln("Deployed %d troops to %s", amt, p.name);
                    t.writefln("You have %d troops remaining", troopsToDeploy);
                  } catch(ConvException e) {
                    throw new CommandException(format(Error.NOT_NUMBER, args[0]));
                  }
                  break;
                }
                case "end":
                  if(troopsToDeploy > 0) 
                    throw new CommandException(format(Error.NOT_DEPLOYED_ALL_TROOPS));
                  expectArgs(cmd, args, 0);
                  nextTurn(&t);
                  break;
                case "toggle": {
                  expectArgs(cmd, args, 1);
                  string toggle = args[0];
                  if(toggle in toggles) {
                    toggles[toggle] = !toggles[toggle];
                    t.writefln("%s is now %s", toggle, toggles[toggle]);
                  } else {
                    throw new CommandException(format(Error.NO_TOGGLE, toggle));
                  }
                  break;
                }
                case "toggles": {
                  expectArgs(cmd, args, 0);
                  t.writeln("Toggles: ");
                  t.writefln("waitBattleRounds: %s\n\tWaits 500ms for every round of a visible battle", toggles["waitBattleRounds"]);
                  t.writefln("seeAllBattles: %s\n\tDisplays all battles", toggles["seeAllBattles"]);
                  break;
                }
                case "save":
                  expectArgs(cmd, args, 1);
                  std.file.write(format("./data/saves/%s.qsf", args[0]), save(0));
                  t.writeln("Save complete");
                  break;
                case "script":
                  expectArgs(cmd, args, 1);
                  if(!toggles["cheats"]) throw new CommandException(format(Error.NO_COMMAND, cmd));
                  runScript(args[0], new GlobalScope(), &t);
                  break;
                case "run": {
                  expectAtLeastArgs(cmd, args, 1);
                  if(!toggles["cheats"]) throw new CommandException(format(Error.NO_COMMAND, cmd));
                  string script = args.join(" ");
                  try {
                    interpret(parseScript(script), new GlobalScope(), &t);
                  } catch(ScriptException e) {
                    throw new CommandException(to!string(e.message));
                  }
                  break;
                }
                default:
                  throw new CommandException(format(Error.NO_COMMAND, cmd));
              }
            }
            break;
          }
        }
      } catch(UserInterruptionException e) {
        return;
      } catch(CommandException e) {
        t.color(Color.red, Color.black);
        t.writeln(e.message);
        t.color(Color.white, Color.black);
      }
    }
  } catch(Throwable e) {
    // this exists so that program doesn't immediately close when an error occurs
    t.color(Color.white, Color.black);
    t.writeln("Error handler triggered.\n");
    t.color(Color.red, Color.black);
    t.writeln(e.toString());
    t.color(Color.white, Color.black);
    t.writeln("\nPress any key to exit.");
    auto input = RealTimeConsoleInput(&t, ConsoleInputFlags.raw);
    input.getch();
    return;
  }
}

/// Reads a command from the user and returns it as an array of strings.
string[] nextCommand(Terminal* t) {
  return t.getline().split(" ");
}

/// Advances the game by one turn.
void nextTurn(Terminal* t) {
  if(!firstTurn) {
    commitAll(actions, t);
    actions = [];
    // run AI
    foreach(ref Country c; countries) {
      if(&c != player && c.getAllProvinces().length > 0) c.ai(t);
    }
    // update
    foreach(ref Country c; countries) {
      c.update(t);
    }
    auto input = RealTimeConsoleInput(t, ConsoleInputFlags.raw);
    bool won = true;
    bool lost = true;
    foreach(Province p; provinces) {
      if(p.owner == player) lost = false;
      if(!p.ocean && p.owner != player) won = false;
    }
    if(lost) {
      t.writeln("You have been defeated!");
      renderMap(MapRenderType.COUNTRY, t);
      t.flush();
      input.getch();
      exit(0);
    } else if(won) {
      t.writeln("You have achieved world domination!");
      renderMap(MapRenderType.COUNTRY, t);
      t.flush();
      input.getch();
      exit(0);
    }
  }
  firstTurn = false;
  turn++;
  troopsToDeploy = player.troopsPerTurn();
  t.writefln("Turn %d", turn);
  t.writefln("You can deploy %d troops", troopsToDeploy);
}

/// Changes the game mode to a desired mode.
void changeMode(GameMode newMode, Terminal* t) {
  gameMode = newMode;
  final switch(gameMode) {
    case GameMode.MAIN_MENU:
      t.writeln(readText("./data/logo.txt"));
      t.writeln(readText("./data/version.txt"));
      t.writeln("Type 'help' in any mode for help");
      break;
    case GameMode.GAME:
      t.writefln("Playing as %s", player.name);
      turn = 0;
      nextTurn(t);
      break;
  } 
}