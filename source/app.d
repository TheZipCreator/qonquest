module qonquest.app;

import qonquest.map, qonquest.script, qonquest.action;
import std.stdio, std.string, std.file, std.conv, std.algorithm, std.typecons;
import core.stdc.stdlib : exit;
import arsd.terminal;

int[] colors = [Color.black, Color.red, Color.green, Color.yellow, Color.blue, Color.magenta, Color.cyan, Color.white, Color.black | Bright, Color.red | Bright, Color.green | Bright, Color.yellow | Bright, Color.blue | Bright, Color.magenta | Bright, Color.cyan | Bright, Color.white | Bright];
/*
For convinience:
1 - black
2 - red
3 - green
4 - yellow
5 - blue
6 - magenta
7 - cyan
8 - black | bright
9 - red | bright
10 - green | bright
11 - yellow | bright
12 - blue | bright
13 - magenta | bright
14 - cyan | bright
15 - white | bright
*/

enum GameMode {
  MAIN_MENU,
  GAME
}

GameMode gameMode;

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
}

class CommandException : Exception {
  this(string message) {
    super(message);
  }
}

Country* player;
Action[] actions;
int turn = 0;
int troopsToDeploy = 0;

void main() {
  auto t = Terminal(ConsoleOutputType.linear);
  loadScripts("data/scripts", &t);
  runScript("data/scripts/launch.qsc", new GlobalScope(), &t);
  loadMap("data/map.bin", &t);
  changeMode(GameMode.MAIN_MENU, &t);
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
                try {
                  int amt = to!int(args[0]);
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
}

string[] nextCommand(Terminal* t) {
  return t.getline().split(" ");
}

void nextTurn(Terminal* t) {
  if(turn != 0) {
    commitAll(actions, t);
    actions = [];
    // run AI
    foreach(ref Country c; countries) {
      if(&c != player) c.ai(t);
    }
    // update
    foreach(ref Country c; countries) {
      c.update(t);
    }
    if(player.getAllProvinces().length == 0) {
      t.writeln("You have been defeated!");
      t.flush();
      exit(0);
    }
    bool won = true;
    foreach(Province p; provinces) {
      if(!p.ocean && p.owner != player) {
        won = false;
        break;
      }
    }
    if(won) {
      t.writeln("You have achieved world domination!");
      t.flush();
      exit(0);
    }
  }
  turn++;
  troopsToDeploy = player.troopsPerTurn();
  t.writefln("Turn %d", turn);
  t.writefln("You can deploy %d troops", troopsToDeploy);
}

void changeMode(GameMode newMode, Terminal* t) {
  gameMode = newMode;
  final switch(gameMode) {
    case GameMode.MAIN_MENU:
      t.writeln(readText("data/logo.txt"));
      t.writeln("Type 'help' in any mode for help");
      break;
    case GameMode.GAME:
      t.writefln("Playing as %s", player.name);
      turn = 0;
      nextTurn(t);
      break;
  } 
}