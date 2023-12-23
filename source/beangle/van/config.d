module beangle.van.config;

import std.string;
import dxml.dom;
import std.stdio;
import std.conv;

class Config {
  Task[string] tasks;
  
  public void addTask(Task task){
    tasks[task.name] = task;
  }
}

class Task{
  const string name;
  const string workdir;
  const string host;
  
  immutable string[string] envs;
  
  const string stdout;
  
  const string command;
  const string executeAt;
  
  this(string name, string workdir, string[string] envs, string command, string executeAt,string stdout) {
    this.name = name;
    auto dir = workdir.replace("${task_name}",name);
    if (dir.endsWith("/")) {
      this.workdir = dir[0 .. $ - 1];
    } else {
      this.workdir = dir;
    }
    this.envs = to!(immutable(string[string]))(envs);
    auto cmd = command;
    foreach(k,v;envs){
      cmd = cmd.replace("${" ~ k ~ "}",v);
    }
    this.command = cmd;
    this.executeAt = executeAt;
    this.stdout = stdout;
  }
  
  public static Config parse(string content) {
    Config config;
    auto dom = parseDOM!simpleXML(content).children[0];
    auto tasksEntry = children(dom, "task");
    if (!tasksEntry.empty) {
      foreach (t; tasksEntry) {
        auto attrs = getAttrs(t);
        string name = attrs.get("name");
        string workdir = expandTilde(attrs.get("workdir", "~"));
        string host = attrs.get("host", "127.0.0.1");
        string execuateAt = attrs.get("execuate_at");
        string stdout = attrs.get("stdout");
        
        auto envElems = children(t, "env");
        string[string] envs;
        foreach (e; envElems) {
          auto a = getAttrs(e);
          envs[ars["name"]] = a["value"];
        }
        auto cmdElems = children(t, "command");
        string command = null;
        if(!cmdElems.empty){
          command = cmdElems[0].text;
        }
        auto task = new Task(name,workdir,envs,command,executeAt,stdout);
        config.addTask(task);
      }
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
  import std.algorithm;
  
  return dom.children.filter!(c => c.name == path);
}

`
<xml>
<profile>
	<task name="sues_openurp" workdir="~/db" host="localhost" execute_at="2022-12-31 16:00：00" stdout="${task_name}.out">
	  <env name="database" value="sues"/>
	  <env name="target_file" value="${task_name}_${execute_time}.dmp"/>
	  <command>
	    pg_dump --format=c -v --file=${target_file} $database
	  </command>
	</task>
</profile>
`