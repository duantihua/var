module beangle.van;

import std.string;
import dxml.dom;
import std.stdio;
import std.conv;
import std.file;
import std.path;
import std.datetime;
import std.algorithm;
import std.array;

class Config {
  Task[string] tasks;

  void addTask(Task task){
    tasks[task.name] = task;
  }

  public static Config parse(string content) {
    Config config = new Config();
    auto dom = parseDOM!simpleXML(content).children[0];
    auto tasksEntry = children(dom, "task");
    foreach (t; tasksEntry) {
      auto attrs = getAttrs(t);
      string name = attrs["name"];
      string workdir = expandTilde(attrs.get("workdir", "~"));
      string host = attrs.get("host", "127.0.0.1");
      auto execuateAt = DateTime.fromISOString(attrs["execute_at"]);
      string stdout = attrs.get("stdout", null);

      auto envElems = children(t, "env");
      string[string] envs;
      envs["task_name"] = name;
      envs["execute_at"] = execuateAt.toISOString;
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
      auto task = new Task(name, workdir, host, envs, command, execuateAt, stdout);
      config.addTask(task);
    }
    return config;
  }
}

class Task {
  immutable string name;
  immutable string workdir;
  immutable string host;

  immutable string[string] envs;

  immutable string stdout;

  immutable string[] commands;
  immutable DateTime executeAt;

  this(string name, string workdir, string host, string[string] envs, string commands, DateTime executeAt, string stdout) {
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
    this.commands = to!(immutable(string[])) (splitLines(cmd).map!(x=> strip(x)).filter!(x=> !x.empty && !startsWith(x,"#")).array());
    this.executeAt = executeAt;
    this.stdout = stdout;
  }

  void execute(){
    import std.process;
    import std.file;
    mkdirRecurse(this.workdir);
    foreach (command; commands){
      auto cmd = executeShell(command, this.envs, std.process.Config.none, size_t.max, this.workdir);
      if (cmd.status != 0) {
        writeln("Failed to execute command1111s");
        break;
      } else writeln(cmd.output);
    }
  }
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
	<task name="openurp" workdir="~/tmp" host="localhost" execute_at="20221231T160000" stdout="${task_name}.out">
	  <env name="database" value="sues"/>
	  <env name="target_file" value="${task_name}_${execute_at}.dmp"/>
	  <commands k="v">
	    echo ${target_file} ${database}
	    #list dir
	    ls -al
	  </commands>
	</task>
</profile>
`;
  auto config = Config.parse(content);

  assert(config.tasks.length == 1);
  assert("openurp" in config.tasks);
  writeln(config.tasks["openurp"].commands);
  config.tasks["openurp"].execute();
}
