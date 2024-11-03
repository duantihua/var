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
import beangle.task.config;
import beangle.xml;

//name -> channel
private AgentChannel[string] agents;
//id -> channel
private AdminChannel[string] admins;
private ServerSetting setting;

void start(string[] args){
  import std.file;
  import std.path;
  auto xmlContents = readXml(args[1]);
  setting = ServerSetting.parse(xmlContents);
  auto router = new URLRouter(setting.path);
  router.get("/", staticRedirect(setting.path ~ "/index.html"));
  router.get("/ws", handleWebSockets(&handleWebSocketConnection));
  router.get("/call/:agent", &callAgent);
  router.get("*", serveStaticFiles("public/"));

  auto hs = new HTTPServerSettings();
  hs.port = setting.port;
  hs.bindAddresses = setting.ips;

  auto listener = listenHTTP(hs, router);
  runApplication(&args);
}

/**
 * Call agent directly
 */
void callAgent(HTTPServerRequest req, HTTPServerResponse res){
  string agentName = req.params.get("agent");
  string commands = req.query.get("commands", "").strip();
  if (commands.length==0){
    res.writeBody("commands needed,using ?commands=some commands in query string");
  } else {
    auto caller = new WebCaller();
    if (agentName in agents){
      res.writeBody(caller.invoke(agents[agentName], commands));
    }else {
      res.writeBody("Cannot find agent named " ~ agentName);
    }
  }
}

bool verify(string name,string secret){
  if(name == "admin"){
    return secret == setting.secret;
  }else{
    if(name in setting.agentSecrets){
      return secret == setting.agentSecrets.get(name,"changeit");
    }else{
      return false;
    }
  }
}

/**
  Handle Websocket messages,do message broking and login.
 */
void handleWebSocketConnection(scope WebSocket socket){
  socket.waitForData(1.seconds);
  string loginText = socket.receiveText;
  // Server-side validation of results
  Channel channel = null;
  bool isAdmin = false;
  if (loginText !is null && loginText.startsWith("/login ")) {
    string[] credentials = loginText["/login ".length .. $].split(" ");
    string name = credentials[0].strip();
    string password = (credentials.length==1)? name : credentials[1].strip();
    if (!verify(name,password)){
      socket.send("invalid secret");
      return;
    }else {
      if (name == "admin"){
        auto newc = AdminChannel.create(name, socket);
        admins[newc.id] = newc;
        channel = newc;
        isAdmin = true;
      }else {
        auto newc = AgentChannel.create(name, socket);
        if (name in agents){
          close(agents[name]);
        }
        agents[name] = newc;
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
    auto text = socket.receiveText.strip();
    if (text == "/close") {
      break;
    }
    if (isAdmin){
      if (text == "/sessions"){
        auto s = agents.values.map!(x=> x.toString()).join(",");
        channel.send(s);
      }else if (text.startsWith("/connect")){
        if (text.length > "/connect ".length){
          auto agentName = text["/connect ".length .. $];
          auto result = agents.get(agentName, null);
          if (result !is null && result.socket.connected){
            AdminChannel admin = cast(AdminChannel)channel;
            admin.setAgent(result);
            channel.send(result.id);
          }else {
            channel.send(agentName ~" is offline");
          }
        }else {
          channel.send("using /connect user_name");
        }
      } else {
        auto admin = cast(AdminChannel)channel;
        if (text.startsWith("@")){
          auto spaceIdx = text.indexOf(' ');
          if (spaceIdx == -1){
            admin.send("using @agentname commands ...");
          }else {
            auto agentName = text[0..spaceIdx].strip();
            auto agent = agents[agentName];
            if (agent !is null && agent.socket.connected){
              agent.invoke(SocketCaller.create(admin), text[spaceIdx..$].strip());
            }else {
              channel.send("offline");
            }
          }
        }else {
          if (admin.agent !is null){
            admin.agent.invoke(SocketCaller.create(admin), text);
          }else {
            admin.send("using @agentname commands ... or connect a exist agent using /connect ");
          }
        }
      }
    }else {
        (cast(AgentChannel)channel).reply(text);
    }
  }
  close(channel);
}

/** Close channel and socket.
 */
void close(Channel channel){
  agents.remove(channel.name);
  admins.remove(channel.id);
  if (channel.socket.connected){
    channel.send("disconneted.");
    channel.socket.close();
  }
  logInfo("%s disconnected", channel.name);
}

