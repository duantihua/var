module beangle.task;

import std.uuid;
import beangle.util;

import std.stdio;
import std.datetime;

string nextChannelId(string name){
  auto st  = Clock.currTime();
  return sha1UUID(name~st.toISOString()).toString();
}

unittest{
  writeln(nextChannelId("dd"));
}
