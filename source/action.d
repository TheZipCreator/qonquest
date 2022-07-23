module qonquest.action;

import qonquest.map, qonquest.app;
import arsd.terminal;
import std.string, std.random, std.algorithm;
import core.thread;

interface Action {
  void commit(Terminal* t);
  void display(Terminal* t);
}

class MoveAction : Action {
  Province* source; // source tile
  Province* dest; // destination tile
  this(Province* source, Province* dest) {
    this.source = source;
    this.dest = dest;
  }
  void commit(Terminal* t) {
    if(source.troops == 0) return;
    if(source.owner == dest.owner) {
      // just move troops if the owner is the same
      dest.troops += source.troops;
      source.troops = 0;
    } else {
      // do battle
      bool display = source.owner == player || dest.owner == player || toggles["seeAllBattles"];
      if(display) {
        t.writefln("Battle of %s", dest.name);
        t.color(colors[source.owner.color], Color.black);
        t.write(source.owner.name);
        t.color(Color.white, Color.black);
        t.write(" vs ");
        t.color(colors[dest.owner.color], Color.black);
        t.writeln(dest.owner.name);
        t.color(Color.white, Color.black);
      }
      for(int round = 1; source.troops > 0 && dest.troops > 0; round++) {
        auto rnd = Random(unpredictableSeed);
        ubyte die() {
          ubyte res = (rnd.front()%6)+1;
          rnd.popFront();
          return res;
        }
        ubyte[] attackerRolls = [die, die].sort!("a > b").release();
        ubyte[] defenderRolls = [die, die, die].sort!("a > b").release();
        int attackerLost = 0;
        int defenderLost = 0;
        if(attackerRolls[0] > defenderRolls[0]) defenderLost++;
        else attackerLost++;
        if(attackerRolls[1] > defenderRolls[1]) defenderLost++;
        else attackerLost++;
        if(display) {
          t.writefln("Round %d:", round);
          t.color(colors[source.owner.color], Color.black);
          t.writef("%d ", source.troops);
          t.color(Color.white, Color.black);
          t.writef("/ ");
          t.color(colors[dest.owner.color], Color.black);
          t.writefln("%d", dest.troops);
          t.color(Color.white, Color.black);
          t.writefln("Attacker rolls: %d, %d", attackerRolls[0], attackerRolls[1]);
          t.writefln("Defender rolls: %d, %d, %d", defenderRolls[0], defenderRolls[1], defenderRolls[2]);
          t.writefln("Attacker lost %d troops, defender lost %d troops", attackerLost, defenderLost);
          t.writeln();
          if(toggles["waitBattleRounds"]) Thread.sleep(dur!("msecs")(500));
        }
        source.troops -= attackerLost;
        dest.troops -= defenderLost;
      }
      if(source.troops > 0) {
        // attacker won, give the province to the attacker
        dest.owner = source.owner;
        dest.troops = source.troops;
        source.troops = 0;
        if(display) {
          t.write("Result: ");
          t.color(colors[source.owner.color], Color.black);
          t.write(source.owner.name);
          t.color(Color.white, Color.black);
          t.writefln(" conquered %s", dest.name);
        }
      } else if(display) {
        t.write("Result: ");
        t.color(colors[source.owner.color], Color.black);
        t.write(source.owner.name);
        t.color(Color.white, Color.black);
        t.writefln(" lost the battle");
      }
      // make sure none are negative
      if(source.troops < 0) source.troops = 0;
      if(dest.troops < 0) dest.troops = 0;
    }
  }
  void display(Terminal* t) {
    t.write("Move troops from ");
    t.color(colors[source.owner.color], Color.black);
    t.writef("%s (%s)", source.name, source.owner.name);
    t.color(Color.white, Color.black);
    t.writef(" to ");
    t.color(colors[dest.owner.color], Color.black);
    t.writef("%s (%s)", dest.name, dest.owner.name);
    t.writeln();
    t.color(Color.white, Color.black);
  }
}

void commitAll(Action[] actions, Terminal* t) {
  foreach(Action a; actions) {
    a.commit(t);
  }
}