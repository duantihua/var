module beangle.util;
import std.stdio;

void removeFromArray(T)(ref T[] datas, T data){
  auto idx = -1;
  auto len = datas.length;
  for (auto i = 0; i < len; i++){
    if (data == datas[i]) {
      idx = i;
      break;
    }
  }
  if (idx >=0){
    for (auto i = idx; i < len-1; i++){
      datas[i] = datas[i+1];
    }
    datas.length = datas.length -1;
  }
}

import std.datetime;
DateTime now(){
  auto st  = Clock.currTime();
  return DateTime(st.year, st.month, st.day, st.hour, st.minute, st.second);
}
unittest{
  int [] ints;
  ints ~= 1;
  ints ~= 3;
  ints ~= 4;
  ints ~= 5;
  removeFromArray!int(ints, 3);
  assert(ints == [1, 4, 5]);
}

