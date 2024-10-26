import vibe.core.net;
import vibe.core.core;
import vibe.core.log;
import vibe.http.client;
import vibe.http.websockets : WebSocket, connectWebSocket;
import std.stdio;
import std.file;
import std.path;
import std.string;
import std.algorithm;
import std.array;
import core.time;
import beangle.task.config;
import beangle.util;

int main (string[] args) {
  if (args.length<2){
    writeln("Usage: " ~ args[0] ~ " path/to/agent.xml");
    return -1;
  }
  auto agent = Agent.parse(cast(string) read(expandTilde(args[1])));
  if (agent.serverURL !is null){
    runTask({
      try{
        connectToWS(agent);
      } catch (Exception e) {

        assert(false, e.msg);
      }
    });
  }
  if (agent.tasks.length>0){
    runTask({
      try{
        runLocalTask(agent);
      } catch (Exception e) {
        assert(false, e.msg);
      }
    });
  }
  scope (exit) exitEventLoop(true);
  return runApplication(&args);
}

void runLocalTask(Agent agent) @system {
  while(true){
    sleep(1.seconds);
    auto current = now();
    auto interval = 1.seconds;
    beangle.task.config.Task[] finished;
    foreach (name, task; agent.tasks){
      auto next = task.nextExecuteAt();
      if (next < current){
        logInfo("finished task: %s", task.name);
        finished ~= task;
      }else if ((next-current) <= interval){
        logInfo("execute task: %s", task.name);
        task.execute();
      }
    }
    agent.removeTasks(finished);
  }
}

void connectToWS (Agent agent)  {
  if (agent.serverURL is null){
    logInfo("Ignore remote server connection");
  }else {
    while(true){
      try{
        auto ws = connectWebSocket(URL(agent.serverURL));
        serveSocket(agent, ws);
      } catch (Exception e) {
        logInfo(e.msg);
        sleep(10.seconds);
      }
    }
  }
}

void serveSocket(Agent agent, WebSocket ws){
  ws.send("/login " ~ agent.name ~ " changeit");
  while (ws.waitForData()) {
    auto txt = ws.receiveText().strip();
    switch (txt){
      case "tasks" :
        auto names = agent.tasks.keys.join(",");
        ws.send(names);
        break;
      case "clean" :
        agent.tasks.clear();
        ws.send("all tasks were removed.");
        break;
        default:
        if (txt.startsWith("<task")){
          auto task = parseTask(txt);
          if (task.repeatable){
            agent.addTask(task);
            ws.send("New task " ~ task.name ~ " was mounted.");
            logInfo("new task %s was mounted.", task.name);
          }else {
            auto res = task.execute();
            string[] outputs;
            auto f = File(task.stdout, "r");
            foreach (string l; lines(f)){
              outputs ~= l;
            }
            ws.send(outputs.join());
            if (res ==0 ){
              std.file.remove(task.stdout);
            }
          }
        }else {
          logInfo("%s", txt);
        }
    }
  }
  logFatal("Connection lost!");
}