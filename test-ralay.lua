IO_RELAY_RASPI_POWER_SUPPLY = 1 --控制继电器1，树莓派电源
IO_RELAY_RASPI_OFF_SIGNAL = 2 --控制继电器2，从而树莓派GPIO的通断，进而控制树莓派执行shutdown now命令
gpio.mode(IO_RELAY_RASPI_POWER_SUPPLY, gpio.OUTPUT)
gpio.mode(IO_RELAY_RASPI_OFF_SIGNAL, gpio.OUTPUT)
gpio.write(IO_RELAY_RASPI_POWER_SUPPLY, gpio.LOW)
gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.LOW)
tmr.alarm(1, 2000, tmr.ALARM_AUTO, function()
	gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.HIGH)
	
	tmr.alarm(2, 1000, tmr.ALARM_SINGLE, function()
		gpio.write(IO_RELAY_RASPI_OFF_SIGNAL, gpio.LOW)
	end)

end)
