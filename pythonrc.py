import sys,os,re,json
K = 1024
M = 1024 ** 2
G = 1024 ** 3
T = 1024 ** 4
import sqlite3
#sqldb = sqlite3.connect("/home/hubt/python/sqldb")
#sql = sqldb.cursor()

r = range(1,20)


class C(object):
  attr1 = "hello attr1"
  def f1():
    print("Starting C.f1()")

  @staticmethod
  def s1():
    print("Starting C.s1()")

import readline
import rlcompleter

if 'libedit' in readline.__doc__:
  readline.parse_and_bind("bind ^I rl_complete")
else:
  readline.parse_and_bind("tab: complete")


import calendar
import datetime
def c(year=None):
  if year == None:
    year = datetime.date.today().year
  print(calendar.TextCalendar().formatyear(year))


#h = [None]
class History(list):
    def __str__(self):
        i = 0
        hist = ""
        for x in self:
          #print "History item: " + str(x)
          hist = hist + "{0}: {1}\n".format(i,x)
          i += 1
        #hist = "\n".join([ "{0}: {1}".format(i,x) for x in self])
        #print "History: " + hist
        return hist
    def grep(self,regex):
        hist = ""
        i = 0
        for x in self:
            print("Grep item: " + str(x) + " " + str(regex))
            if x and re.search(regex,x) != None :
                hist = hist + "{0}: {1}\n".format(i,x)
            i += 1
        print(hist)
            
h = History()

class Prompt1:
    def __init__(self, str='h[%d] >>> '):
        self.str = str;

    def __str__(self):
        global h
        h = History()
        for x in range(0,readline.get_current_history_length()-1):
          #print "length %d %s" % (x,readline.get_history_item(x))
          h.append(readline.get_history_item(x))
        return self.str % readline.get_current_history_length()

    def __radd__(self, other):
        return str(other) + str(self)

class Prompt:
    def __init__(self, str='h[%d] >>> '):
        self.str = str;

    def __str__(self):
        try:
            _ = readline.get_history_item(readline.get_current_history_length())
            if _ not in [h[-1], None, h]: h.append(_);
        except NameError:
           pass
        return self.str % len(h);

    def __radd__(self, other):
        return str(other) + str(self)

class Prompt2(Prompt1):
    def __init__(self, str='h[%d] ... '):
        self.str = str;
    

if os.environ.get('TERM') in [ 'xterm', 'vt100' ]:
    # sys.ps1 = Prompt('\001\033[0:1;31m\002h[%d] >>> \001\033[0m\002')
    #sys.ps1 = Prompt('h[%d] >>> ')
    sys.ps1 = Prompt1()
else:
    sys.ps1 = Prompt1()
sys.ps2 = Prompt2()

