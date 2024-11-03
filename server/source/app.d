import beangle.task.server;

int main(string[] args){
  if (args.length<2){
    import std.stdio;
    writeln("Usage: " ~ args[0] ~ " path/to/sas.xml");
    return -1;
  }
  start(args);
  return 0;
}
