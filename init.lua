--Lua 中的变量全是全局变量，那怕是语句块或是函数里，除非用 local 显式声明为局部变量。

-------------
-- define
-------------
IO_RELAY_RASPI_POWER_SUPPLY = 1 --控制继电器1，树莓派电源
IO_RELAY_RASPI_OFF_SIGNAL = 2 --控制继电器2，从而树莓派GPIO的通断，进而控制树莓派执行shutdown now命令
IO_BTN_CFG = 3 --按钮
--在NodeMCU上有一个LED可用。可以用它来显示当前的连接状态。经测试，控制该LED的引脚为D4。
IO_BLINK = 4 --NodeMCU上自带的状态灯。

--tmr id 0- 6 
TMR_RELAY = 1
TMR_CHECK_NETWORK = 2
TMR_RESTART = 3
TMR_WIFI = 4
TMR_BLINK = 5
TMR_BTN = 6

gpio.mode(IO_RELAY_RASPI_POWER_SUPPLY, gpio.OUTPUT)
gpio.mode(IO_RELAY_RASPI_OFF_SIGNAL, gpio.OUTPUT)
gpio.mode(IO_BTN_CFG, gpio.INT) --中断模式
gpio.mode(IO_BLINK, gpio.OUTPUT)

--初始化输出
--继电器连接normally open，在输出Low的时候，断开
gpio.write(IO_RELAY_RASPI_POWER_SUPPLY, gpio.LOW)
gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.LOW)
gpio.mode(IO_BLINK, gpio.LOW) --LOW是点亮，HIGH是熄灭

-------------
-- button
-------------
function onBtnEvent()
    --防止抖动，先取消注册的出发函数，500ms后再注册。
    gpio.trig(IO_BTN_CFG)
    tmr.alarm(TMR_BTN, 500, tmr.ALARM_SINGLE, function()
        gpio.trig(IO_BTN_CFG, 'up', onBtnEvent)
    end)

    switchCfg()
end
gpio.trig(IO_BTN_CFG, 'up', onBtnEvent)



function switchCfg()
    if wifi.getmode() == wifi.STATION then
		--停止任务。
		tmr.stop(TMR_CHECK_NETWORK)	
        wifi.setmode(wifi.STATIONAP)
        wifi.ap.config({ssid='NodeMCUConfig'})--设置ap的名字
        httpServer:listen(80)
        blinking({1000, 1000})
    else
	    --配好网络后，开始任务。
		tmr.start(TMR_CONNECT)	
        wifi.setmode(wifi.STATION)
        httpServer:close()
        blinking()
    end
end

-------------
-- blink
-------------
blink = nil
tmr.register(TMR_BLINK, 100, tmr.ALARM_AUTO, function()
    gpio.write(IO_BLINK, blink.i % 2)
    tmr.interval(TMR_BLINK, blink[blink.i + 1])
    blink.i = (blink.i + 1) % #blink
end)

function blinking(param)
    if type(param) == 'table' then
        blink = param
        blink.i = 0
        tmr.interval(TMR_BLINK, 1)
        running, _ = tmr.state(TMR_BLINK)
        if running ~= true then
            tmr.start(TMR_BLINK)
        end
    else
        tmr.stop(TMR_BLINK)
        gpio.write(IO_BLINK, param or gpio.LOW)
    end
end

-------------
-- wifi
-------------
print('Setting up WIFI...')
wifi.setmode(wifi.STATION)
--使用无线配网，不要声明。
--wifi.sta.config({ssid='wifi1', pwd='12345678'})
wifi.sta.sethostname("NodeMCU-raspi2") --设置设备的名字
wifi.sta.autoconnect(1)

status = nil

wifi.eventmon.register(wifi.eventmon.STA_CONNECTED, function(T)
    blinking()
    status = 'STA_CONNECTED'
    print(status)
end)

wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, function(T)
    blinking({1000, 1000})
    status = 'STA_DISCONNECTED'
    print(status)
end)

wifi.eventmon.register(wifi.STA_GOTIP, function()
    blinking()
    status = 'STA_GOTIP'
    print(status, wifi.sta.getip())
end)

-------------
-- http
-------------
dofile('httpServer.lua')

httpServer:use('/config', function(req, res)
    if req.query.ssid ~= nil and req.query.pwd ~= nil then
        wifi.sta.config(req.query.ssid, req.query.pwd)

        status = 'STA_CONNECTING'
        tmr.alarm(TMR_WIFI, 1000, tmr.ALARM_AUTO, function()
            if status ~= 'STA_CONNECTING' then
                res:type('application/json')
                res:send('{"status":"' .. status .. '"}')
                tmr.stop(TMR_WIFI)
            end
        end)
    end
end)

httpServer:use('/scanap', function(req, res)
    wifi.sta.getap(function(table)
        local aptable = {}
        for ssid,v in pairs(table) do
            local authmode, rssi, bssid, channel = string.match(v, "([^,]+),([^,]+),([^,]+),([^,]+)")
            aptable[ssid] = {
                authmode = authmode,
                rssi = rssi,
                bssid = bssid,
                channel = channel
            }
        end
        res:type('application/json')
        res:send(sjson.encode(aptable))
    end)
end)

-------------
-- 逻辑开关
-------------
function isConnect()
    ip, _, _ = wifi.sta.getip()
    if ip ~= nil then
        print(ip)
        return true
    else
        print("without ip")
        return false
    end
end

function forceShutdownRaspi()
    --树莓派接到信号后，开始执行shutdown now命令
    gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.HIGH)
    --等待二分钟，关闭树莓派电源
    tmr.alarm(TMR_RELAY, 120000, tmr.ALARM_SINGLE, function()
        gpio.write(IO_RELAY_RASPI_POWER_SUPPLY, gpio.LOW)
		--一定等到关机完成后，才设置标志位。否则可能再执行过程中，nodemcu重新启动，判断为关机状态，直接重启了，损坏树莓派。
        is_raspi_on = false
        --开始检查网络
        tmr.start(TMR_CHECK_NETWORK)
    end)
end

function closeRaspi()
    is_raspi_on = false
    --关闭继电器电源
    gpio.write(IO_RELAY_RASPI_POWER_SUPPLY, gpio.LOW)
    --关闭树莓派信号
    gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.HIGH)
end

function openRaspi()
    is_raspi_on = true
    --打开继电器电源
    gpio.write(IO_RELAY_RASPI_POWER_SUPPLY, gpio.HIGH)
    --关闭树莓派信号
    gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.LOW)
end

function bootRaspi()
    --重启继电器电源
    gpio.write(IO_RELAY_RASPI_POWER_SUPPLY, gpio.LOW)
    --先关闭树莓派GPIO关机信号
    gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.LOW)
    tmr.alarm(TMR_RELAY, 5000, tmr.ALARM_SINGLE, function()
        gpio.write(IO_RELAY_RASPI_POWER_SUPPLY, gpio.HIGH)
        --一定等到开机完成后，才设置标志位。否则可能再执行过程中，nodemcu重新启动，判断为开机状态，执行forceshutdown函数，浪费时间。
        is_raspi_on = true
    end)
end


--初始化标识
fail_count = 0
--树莓派是否开机
is_raspi_on = false

tmr.alarm(TMR_CHECK_NETWORK, 60000, tmr.ALARM_AUTO, function() 
    --if isConnect() == true then
        http.get("http://manager.xxx.com/public/raspi2/get-switch-status.do", nil, function(code, data)
            if is_raspi_on==false then --树莓派处于关机状态
                if (code ~= 200) then --断电
                  print("HTTP request failed") 
                else                  --来电
                  --网络通畅，判断远程控制是否要打开树莓派。
                  fail_count = 0
                  local result = sjson.decode(data)
                  print(result["switch"])
                  if (result["switch"]) then
                    bootRaspi()
                  else
                    closeRaspi()
                  end
                    
                end 
            else                      --树莓派处于开机状态
                if (code ~= 200) then --断电
                  fail_count = fail_count + 1
                  print(fail_count)
                  -- 连续五分钟都失败，认为网络不通，或者断电。这时关闭继电器。
                  if(fail_count >= 5) then
                    --重置计数
                    fail_count = 0
                    --停止检查网络
                    tmr.stop(TMR_CHECK_NETWORK)
                    --关闭树莓派
                    forceShutdownRaspi()                
                  end
                  print("HTTP request failed") 
                else                   --来电
                  fail_count = 0
                  local result = sjson.decode(data)
                  print(result["switch"])
                  if (result["switch"]) then
                    openRaspi()
                  else
                    --没有执行断电关机，树莓派还在运行，需要先关树莓派，再关继电器。
                    --停止检查网络
                    tmr.stop(TMR_CHECK_NETWORK)
                    --关闭树莓派
                    forceShutdownRaspi()
                  end
                    
                end 
            end
            
        end)   
        
    --end
end)

---为什么能保证这样重启一定安全？
---可能出问题的地方就是forceShutdownRaspi()中定时函数还没执行完，就重置标志位is_raspi_on=false，造成树莓派运行过程中重启。
---上来取消所有定时，forceShutdownRaspi()中定时函数没执行，就不重置标志位is_raspi_on=false。这样就可以准确的知道树莓派的运行状态。

--interval_ms timer interval in milliseconds. Maximum value is 6870947 (1:54:30.947).
--每一个半小时计数一次
time_count = 0
tmr.alarm(TMR_RESTART, 5400000, tmr.ALARM_AUTO, function()
	time_count = time_count + 1
	--每三个小时重启一次
	if(time_count >= 2) then
		--取消所有定时
		tmr.stop(TMR_RELAY)
		tmr.stop(TMR_CHECK_NETWORK)
		tmr.stop(TMR_RESTART)
		tmr.stop(TMR_WIFI)
		tmr.stop(TMR_BLINK)
		tmr.stop(TMR_BTN)
		if is_raspi_on==false then --树莓派处于关机状态
			 node.restart()
		else
			forceShutdownRaspi() --先安全关机，再重启nodemcu。它有一个二分钟的定时。
			--130秒才重启
			tmr.alarm(TMR_RESTART, 130000, tmr.ALARM_SINGLE, function()
				node.restart()
			end)
		end	  
    end  
end)
    
