# -*- coding: utf-8 -*-  
import RPi.GPIO
import time, os, sys
from os import path
''' 由于不是同一个项目中的两个文件夹 ，需要把路径加载到 sys.path，import的时候才会搜索到'''
sys.path.append(path.join(path.dirname(path.abspath(__file__)), "../py_daemon"))
#包名.模块名，函数/类
from PyDaemon import Daemon

class nodeMcuShutdown(Daemon):
    def __init__(self, name, pidfile, stdin=os.devnull, stdout=os.devnull, stderr=os.devnull):
        Daemon.__init__(self, pidfile, stdin, stdout, stderr)
        self.name = name #派生守护进程类的名称
    def main(self):
        RPi.GPIO.setwarnings(False)
        RPi.GPIO.setmode(RPi.GPIO.BCM)
        self.shutdown(18)
    def shutdown(self,pin): 
        ''' The GPIO.BOARD option specifies that you are referring to the pins by the number of the pin the the plug - i.e the numbers printed on the board (e.g. P1) and in the middle of the diagrams below. '''
        ''' The GPIO.BCM option means that you are referring to the pins by the "Broadcom SOC channel" number, these are the numbers after "GPIO" in the green rectangles around the outside of the below diagrams '''
        # 按钮连接的GPIO针脚的模式设置为信号输入模式，同时默认拉高GPIO口电平，
        # 当GND没有被接通时，GPIO口处于高电平状态，取的的值为1
        # 注意到这是一个可选项，如果不在程序里面设置，通常的做法是通过一个上拉电阻连接到VCC上使之默认保持高电平
        RPi.GPIO.setup(pin, RPi.GPIO.IN, pull_up_down=RPi.GPIO.PUD_UP)
        while(True):
            time.sleep(5)
            if (RPi.GPIO.input(pin) == 0):
                time.sleep(5)
                if (RPi.GPIO.input(pin) == 0):
                    os.popen('shutdown now')        
            else:
                pass
    def run(self):
        self.main()
if __name__ == '__main__':  
    help_msg = 'Usage: python %s <start|stop|restart|status>' % sys.argv[0]  
    if len(sys.argv) != 2:  
        print(help_msg) 
        sys.exit(1)  
    daemon_name = 'nodeMcuShutdown' #守护进程名称
    pid_file = '/tmp/nodeMcuShutdown.pid' #守护进程pid文件的绝对路径
    stdin_file = '/tmp/nodeMcuShutdown.in'
    stdout_file = '/tmp/nodeMcuShutdown.out' #守护进程日志文件的绝对路径
    stderr_file = '/tmp/nodeMcuShutdown.err' #守护进程启动过程中的错误日志,内部出错能从这里看到
    nodeMcuShutdown_instance = nodeMcuShutdown(daemon_name, pidfile=pid_file, stdin=stdin_file, stdout=stdout_file, stderr=stderr_file)
    
    if sys.argv[1] == 'start':  
        nodeMcuShutdown_instance.start()  
    elif sys.argv[1] == 'stop':  
        nodeMcuShutdown_instance.stop()  
    elif sys.argv[1] == 'restart':  
        nodeMcuShutdown_instance.restart()  
    elif sys.argv[1] == 'status':  
        alive = nodeMcuShutdown_instance.is_running()  
        if alive:  
            print('process [%s] is running ......' % nodeMcuShutdown_instance.get_pid())
        else:  
            print('daemon process [%s] stopped' %nodeMcuShutdown_instance.name)
    else:  
        print('invalid argument!')  
        print(help_msg) 
