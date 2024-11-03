module beangle.xml;

static auto getAttrs(T)(ref DOMEntity!T dom) {
  string[string] a;
  foreach (at; dom.attributes) {
    a[at.name] = at.value;
  }
  return a;
}

static auto children(T)(ref DOMEntity!T dom, string path) {
  import std.algorithm;

  return dom.children.filter!(c => c.name == path);
}

import std.file;
import std.path;
string readXml(string xmlfile) {
  auto fullPath = expandTilde(xmlfile);
  if (exists(fullPath)) {
    return cast(string) read(fullPath);
  } else {
    throw new Exception(xmlfile ~ " is not exists!");
  }
}
