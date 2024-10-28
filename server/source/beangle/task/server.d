module beangle.task.server;

import vibe.core.core;
import vibe.core.log;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.http.websockets : WebSocket, handleWebSockets;

import core.time;
import std.conv : to;
import std.algorithm;
import std.string;
import std.array;
import beangle.util : removeFromArray;
import beangle.task.channel;

private AgentChannel[string] agents;
private AdminChannel[string] admins;

import std.getopt;

void start(string[] args){
  ushort port = 8989;
  string contextPath="/sas";
  string host="127.0.0.1";
  bool help=false;

  getopt(args, std.getopt.config.passThrough, "port|p", &port, "path", &contextPath, "host", &host, "help|h",&help);

  if(help){
    import std.stdio;
    writeln("Usage: " ~ args[0] ~ " --port=8989 --path=/sas");
    return;
  }
  auto router = new URLRouter(contextPath);
  router.get("/", staticRedirect("/index.html"));
  router.get("/ws", handleWebSockets(&handleWebSocketConnection));
  router.get("*", serveStaticFiles("public/"));

  auto settings = new HTTPServerSettings(":8080");
  settings.port = port;
  if(host != "127.0.0.1"){
    settings.bindAddresses = ["127.0.0.1", host];
  }else{
    settings.bindAddresses = ["127.0.0.1" ];
  }

  auto listener = listenHTTP(settings, router);
  runApplication(&args);
}

void handleWebSocketConnection(scope WebSocket socket){
  socket.waitForData(1.seconds);
  string loginText = socket.receiveText;
  // Server-side validation of results
  Channel channel=null;
  bool isAdmin=false;
  if (loginText !is null && loginText.startsWith("/login ")) {
    string[] credentials = loginText["/login ".length .. $].split(" ");
    string name = credentials[0].strip();
    string password = (credentials.length==1)? name : credentials[1].strip();
    if (password != "changeit"){
      socket.send("invalid password");
      return;
    }else {
      if (name == "admin"){
        auto newc = AdminChannel.create(name, socket);
        admins[newc.id] = newc;
        channel = newc;
        isAdmin=true;
      }else {
        auto newc = AgentChannel.create(name, socket);
        agents[newc.id] = newc;
        channel = newc;
      }
      socket.send(name ~ " is connected.");
      auto r = cast(HTTPServerRequest)socket.request;
      logInfo("%s connected @ %s.", name, r.peer());
    }
  }else {
    socket.send("Invalid name,using /login username password");
    socket.close();
    return;
  }
  // message loop
  while (socket.waitForData) {
    if (!socket.connected) break;
    auto text = socket.receiveText;
    if (text == "/close") {
      break;
    }
    if (isAdmin){
      if (text =="/sessions"){
        auto s = agents.values.map!(x=> x.toString()).join(",");
        channel.send(s);
      }if (text.startsWith("/connect")){
        if (text.length > "/connect ".length){
          auto agentName = text["/connect ".length .. $];
          auto result = agents.values.find!(x=> x.name == agentName && x.socket.connected);
          if (result.length>0){
            AdminChannel admin = cast(AdminChannel)channel;
            admin.purge();
            result[0].addAdmin(admin);
            admin.addAgent(result[0]);
            channel.send(result[0].id);
          }else {
            channel.send("offline");
          }
        }else {
          channel.send("using /connect user_name");
        }
      }else {
        channel.broadcast(text);
      }
    }else {
      channel.broadcast(text);
    }
  }
  close(channel);
}

void close(Channel channel){
  agents.remove(channel.id);
  admins.remove(channel.id);
  if(channel.socket.connected){
    channel.send("disconneted.");
    channel.socket.close();
  }
  logInfo("%s disconnected", channel.name);
}

