module beangle.task.channel;
import vibe.http.websockets : WebSocket;
import beangle.task;
import beangle.util;


//name -> channel
private AgentChannel[string] agents;
//id -> channel
private AdminChannel[string] admins;

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

  override string toString(){
    return name ~ "@" ~ id;
  }
}

class AdminChannel : Channel{

  AgentChannel agent;

  static AdminChannel create(string name, WebSocket socket){
    return new AdminChannel(nextChannelId(name), name, socket);
  }

  this(string id, string name, WebSocket socket){
    super(id, name, socket);
  }

  void setAgent(AgentChannel agent){
    this.agent = agent;
  }

  void purge(){
    if (this.agent !is null && !this.agent.socket.connected){
      this.agent = null;
    }
  }

}

class AgentChannel : Channel {
  //caller name -> caller
  Caller[string] callers;

  void invoke(Caller caller, string cmds){
    callers[caller.getId()] = caller;
    import std.json;
    JSONValue jj = ["id":caller.getId()];
    jj.object["commands"]=cmds;
    send(jj.toString());
  }

  void reply(string text){
    import std.json;
    JSONValue js = parseJSON(text);
    auto callId = js["id"].str;
    auto data = js["data"].str;
    auto caller = callId in callers;
    if (caller !is null){
      callers.remove(callId);
      caller.callback(data);
    }
  }

  this(string id, string name, WebSocket socket){
    super(id, name, socket);
  }

  static AgentChannel create(string name, WebSocket socket){
    return new AgentChannel(nextChannelId(name), name, socket);
  }
}

interface Caller{
  void callback(string result);
  string getId();
}

class SocketCaller : Caller{
  WebSocket socket;
  const string id;

  this(string id, WebSocket socket){
    this.id = id;
    this.socket = socket;
  }

  string getId(){
    return id;
  }
  static SocketCaller create(AdminChannel channel){
    import std.datetime;
    auto id = Clock.currTime().toISOString() ~ "@" ~ channel.name;
    return new SocketCaller(id, channel.socket);
  }

  override void callback(string result){
    if (this.socket.connected) {
      this.socket.send(result);
    }
  }
}

class WebCaller : Caller{
  import vibe.core.sync;
  string id;
  InterruptibleTaskMutex m_readMutex;
  InterruptibleTaskCondition m_readCondition;
  string result;

  this(){
    import std.datetime;
    this.id = Clock.currTime().toISOString() ~ "@web";
  }

  string getId(){
    return id;
  }

  import core.time;

  string invoke(AgentChannel agent, string commands, Duration timeout = 20.seconds){
    m_readMutex = new InterruptibleTaskMutex;
    m_readCondition = new InterruptibleTaskCondition(m_readMutex);

    agent.invoke(this,commands);
    m_readMutex.performLocked!({
      m_readCondition.wait(timeout);
    });
    return result;
  }

  override void callback(string result){
    import std.stdio;
    if (result is null){
      this.result = "null";
    }else {
      this.result = result;
    }
    m_readCondition.notify();
  }
}

