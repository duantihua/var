module beangle.task.channel;
import vibe.http.websockets : WebSocket;
import beangle.task;
import beangle.util;

abstract class Channel{

  immutable string id;

  immutable string name;

  //socket to client
  WebSocket socket;

  this(string id, string name, WebSocket socket){
    this.id = id;
    this.name = name;
    this.socket = socket;
  }

  void send(string text){
    if (this.socket.connected) {
      this.socket.send(text);
    }
  }

  abstract void broadcast(string text);

  override string toString(){
    return name ~ "@" ~ id;
  }
}

class AdminChannel : Channel{

  AgentChannel[] agents;

  static AdminChannel create(string name, WebSocket socket){
    return new AdminChannel(nextChannelId(name), name, socket);
  }

  this(string id, string name, WebSocket socket){
    super(id,name,socket);
  }

  void addAgent(AgentChannel agent){
    agents ~= agent;
  }

  void removeAgent(AgentChannel agent){
    removeFromArray(agents, agent);
  }

  void purge(){
    import std.algorithm;
    import std.array;
    auto offlines = this.agents.filter!(x=> !x.socket.connected).array();
    if(offlines.length>0){
      this.agents = this.agents.filter!(x=> x.socket.connected).array();
    }
  }

  override void broadcast(string text){
    foreach (cl; this.agents) {
      if (cl.socket.connected) {
        cl.socket.send(text);
      }
    }
  }
}

class AgentChannel : Channel {

  AdminChannel[] admins;

  this(string id, string name, WebSocket socket){
    super(id,name,socket);
  }

  static AgentChannel create(string name, WebSocket socket){
    return new AgentChannel(nextChannelId(name), name, socket);
  }

  void addAdmin(AdminChannel admin){
    admins ~= admin;
  }

  void removeAdmin(AdminChannel admin){
    removeFromArray(admins, admin);
  }

  override void broadcast(string text){
    foreach (cl; this.admins) {
      if (cl.socket.connected) {
        cl.socket.send(text);
      }
    }
  }

}