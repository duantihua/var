import beangle.task.agent;

int main(string[] args){
  if (args.length<2){
    import std.stdio;
    writeln("Usage: " ~ args[0] ~ " path/to/sas.xml");
    return -1;
  }
  return start(args);
}