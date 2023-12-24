import std.stdio;

void main(string[] args){
  if (args.length<2){
    writeln("Usage: " ~ args[0] ~ " path/to/config.xml");
    return;
  }
}
