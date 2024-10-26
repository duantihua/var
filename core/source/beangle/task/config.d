module beangle.task.config;

import std.string;
import dxml.dom;
import std.stdio;
import std.conv;
import std.file;
import std.path;
import std.datetime;
import std.algorithm;
import std.array;
import core.time;
import beangle.util;

class Agent{
  immutable string name;
  immutable string secret;
  immutable string serverURL;
  Task[string] tasks;

  this(string name, string secret, string serverURL){
    this.name = name;
    this.secret = secret;
    this.serverURL = serverURL;
  }
  void addTask(Task task){
    this.tasks[task.name] = task;
  }

  void removeTasks(Task[] removed){
    foreach (t; removed){
      this.tasks.remove(t.name);
    }
  }

  public static Agent parse(string content){
    auto dom = parseDOM!simpleXML(content).children[0];
    auto attrs = getAttrs(dom);
    auto name = attrs.get("name", "agent");
    auto secret = attrs.get("secret", name);
    string serverURL=null;
    foreach (se; children(dom, "server")) {
      attrs = getAttrs(se);
      if ("url" in attrs){
        serverURL = attrs["url"];
      }
    }
    auto agent = new Agent(name, secret, serverURL);
    auto tasksEntry = children(dom, "task");
    foreach (t; tasksEntry) {
      auto task = parseTask(t);
      agent.addTask(task);
    }
    return agent;
  }
}

unittest {
  auto content = `<?xml version="1.0" encoding="UTF-8"?>
<agent name="agent" secret="secret">
  <server url="ws://somehost.com/ws">
  </server>
  <task name="check_disk" workdir="~/tmp" host="localhost" repeat="5 seconds" stdout="${task_name}.out">
    <commands>
      df -h;
    </commands>
  </task>
</agent>
`;
  auto agent = Agent.parse(content);

  assert(agent.name == "agent");
  assert(agent.serverURL == "ws://somehost.com/ws");

  assert(agent.tasks.length == 1);
  assert("check_disk" in agent.tasks);
  auto task = agent.tasks["check_disk"];
}

class Profile {
  Task[string] tasks;

  void addTask(Task task){
    tasks[task.name] = task;
  }

  public static Profile parse(string content) {
    Profile profile = new Profile();
    auto dom = parseDOM!simpleXML(content).children[0];
    auto tasksEntry = children(dom, "task");
    foreach (t; tasksEntry) {
      auto task = parseTask(t);
      profile.addTask(task);
    }
    return profile;
  }
}

class Task {
  immutable string name;
  immutable string workdir;
  immutable string host;

  immutable string[string] envs;

  immutable string stdout;

  immutable string[] commands;
  immutable DateTime beginAt;
  immutable DateTime endAt;
  immutable Duration repeat;
  string lastExecuteAt;

  this(string name, string workdir, string host, string[string] envs, string commands, DateTime beginAt,
    DateTime endAt, Duration repeat, string stdout) {
    this.name = name;
    auto dir = workdir.replace("${task_name}", name);
    if (dir.endsWith("/")) {
      this.workdir = dir[0 .. $ - 1];
    } else {
      this.workdir = dir;
    }
    this.host = host;
    this.envs = to!(immutable(string[string]))(envs);
    auto cmd = commands.strip();
    foreach (k, v; envs){
      cmd = cmd.replace("${" ~ k ~ "}", v);
    }
    this.commands = to!(immutable(string[])) (splitLines(cmd).map!(x=> strip(x)).filter!(x=> !x.empty && !startsWith(x, "#")).array());
    this.beginAt = beginAt;
    this.endAt = endAt;
    this.repeat = repeat;
    this.stdout = stdout;
  }

  int execute(){
    lastExecuteAt = now().toISOString();
    import std.process;
    import std.file;
    mkdirRecurse(this.workdir);
    foreach (command; commands){
      auto cmd = executeShell(command, this.envs, std.process.Config.none, size_t.max, this.workdir);
      if (cmd.status != 0) {
        writeln("Failed to execute commands");
        return cmd.status;
      } else {
        if (this.stdout is null){
          writeln(cmd.output);
        }else {
          auto f = File(this.stdout, "w");
          f.write(cmd.output);
        }
      }
    }
    return 0;
  }

  int execute(string command){
    import std.process;
    import std.file;
    auto cmd = executeShell(command, this.envs, std.process.Config.none, size_t.max, this.workdir);
    writeln(cmd.output);
    return cmd.status;
  }

  bool repeatable(){
    return this.repeat.total!"seconds">0;
  }

  DateTime nextExecuteAt(){
    auto current = now();
    if ( lastExecuteAt is null){
      if (repeatable){
        DateTime startAt = beginAt;
        while(startAt < current ){
          startAt = startAt + repeat;
        }
        return startAt;
      }else {
        auto last = current + 2.seconds;
        lastExecuteAt = current.toISOString();
        return last;
      }
    }else {
      auto last = DateTime.fromISOString(lastExecuteAt);
      if (repeatable){
        auto startAt = last;
        while(startAt < current ){
          startAt = startAt + repeat;
        }
        return startAt;
      }else {
        return last;
      }
    }
  }

}

public static Task parseTask(string contents){
  auto dom = parseDOM!simpleXML(`<?xml version="1.0" encoding="UTF-8"?>` ~ contents).children[0];
  return parseTask(dom);
}

unittest{
  auto a  = parseTask(`<task name="ls" workdir="~/tmp" host="localhost" repeat="3 seconds" stdout="${task_name}.out"><commands>ls -alh;</commands></task>`);
  assert(a.stdout == "${task_name}.out");
}

public static Task parseTask(T)(ref DOMEntity!T t){
  auto attrs = getAttrs(t);
  string name = attrs["name"];
  string workdir = expandTilde(attrs.get("workdir", "~"));
  string host = attrs.get("host", "127.0.0.1");

  auto beginAt = ("begin_at" in attrs)? DateTime.fromISOString(attrs["begin_at"]) : now();
  DateTime endAt = DateTime.fromISOString(attrs.get("end_at", "99991231T115959"));
  Duration repeat = 0.seconds;
  if ( "repeat" in attrs){
    auto interval = attrs["repeat"];
    import std.uni : isWhite;
    auto parts = interval.split!isWhite;
    assert(parts.length == 2);
    switch (parts[1]){
      case "days":
        repeat = (parts[0].to!int).days;
        break;
      case "weeks":
        repeat = (parts[0].to!int).weeks;
        break;
      case "hours":
        repeat = (parts[0].to!int).hours;
        break;
      case "minutes":
        repeat = (parts[0].to!int).minutes;
        break;
      case "seconds":
        repeat = (parts[0].to!int).seconds;
        break;
        default:
        throw new Exception("cannot support "~parts[1]~" as duration units");
    }
  }

  string stdout = attrs.get("stdout", workdir ~ "/" ~ name ~ ".out");
  stdout = expandTilde(replace(stdout,"${task_name}",name));
  auto envElems = children(t, "env");
  string[string] envs;
  envs["task_name"] = name;
  envs["begin_at"] = beginAt.toISOString;
  foreach (e; envElems) {
    auto a = getAttrs(e);
    auto value = a["value"];
    if (value.indexOf("${") > -1 ){
      foreach (k, v; envs){
        value = value.replace("${" ~ k ~ "}", v);
      }
    }
    envs[a["name"]] = value;
  }
  auto cmdElems = children(t, "commands");
  string command = null;
  if (!cmdElems.empty){
    command = cmdElems.front.children[0].text;
  }
  return new Task(name, workdir, host, envs, command, beginAt, endAt, repeat, stdout);
}

string[string] getAttrs(T)(ref DOMEntity!T dom) {
  string[string] a;
  foreach (at; dom.attributes) {
    a[at.name] = at.value;
  }
  return a;
}

auto children(T)(ref DOMEntity!T dom, string path) {
  return dom.children.filter!(c => c.name == path);
}

unittest {
  auto content = `<?xml version="1.0" encoding="UTF-8"?>
<profile>
  <task name="openurp" workdir="~/tmp" host="localhost" begin_at="20221231T160000" stdout="${task_name}.out">
    <env name="database" value="sues"/>
    <env name="target_file" value="${task_name}_${begin_at}.dmp"/>
    <commands k="v">
      echo ${target_file} ${database}
      #list dir
      ls -al
    </commands>
  </task>
</profile>
`;
  auto profile = Profile.parse(content);

  assert(profile.tasks.length == 1);
  assert("openurp" in profile.tasks);
  writeln(profile.tasks["openurp"].commands);
  //config.tasks["openurp"].execute();
}
