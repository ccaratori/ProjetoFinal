--[[ 
	PUC-Rio, 2013
	
	* Author: 
		Carlo Caratori (carlocaratori@gmail.com)
		
	* Description: 
		Small application for maximizing solar panel energy generation. System is controled by sms
]]--

require('gsm')
local disp = lm3s.disp

system_on = false
debugdef = true
terminate = false

right_sensor_id = 0
center_sensor_id = 1
left_sensor_id = 2

left_maxval = adc.maxval(left_sensor_id)
center_maxval = adc.maxval(center_sensor_id)
right_maxval = adc.maxval(right_sensor_id)

if(debugdef) then
	disp.init(1000000)
	disp.print('System OFF', 20, 10, 0)
end

adc.setblocking(left_sensor_id, 1)
adc.setblocking(center_sensor_id, 1)
adc.setblocking(right_sensor_id, 1)
adc.setsmoothing(left_sensor_id, 4)
adc.setsmoothing(center_sensor_id, 4)
adc.setsmoothing(right_sensor_id, 4)

----------------------------------------------------------------------------------------------------------------------------------------
--	Callbacks
---------------------------------------
function system_on_off(m, n, s)
	
	system_on = not system_on
	
	if(debugdef) then
		if(system_on) then disp.print('System OFF', 20, 10, 0) disp.print('System ON', 20, 10, 15)
		else disp.print('System ON', 20, 10, 0) disp.print('System OFF', 20, 10, 15)
		end
	end
end

function send_status(m, n, s)
	print('Status')
end

function debug_on_off(m, n, s)
	debugdef = not debugdef
end

function terminate(m, n, s)
	disp.clear()
	terminate_flag = true
end

callbacks = {}
callbacks.system = system_on_off
callbacks.status = send_status
callbacks.debug = debug_on_off
callbacks.terminate = terminate

----------------------------------------------------------------------------------------------------------------------------------------
--	Main Program
---------------------------------------

if(not init({uart_id = 1, rts_pio = pio.PC_5, rst_pio = pio.PC_7})) 
then 
	print('GSM init not completed') 
else
	print('GSM initialized')
	print('system on/off (s) - Turn system on/off\nstatus (t) - System status\ndebug (d) - Debug mode on/off\nterminate (e) - terminate program')

	-- Main loop
	while(true) do
	
		-- Read messages
		local success, error_msg, error_code, messages = try_get_sms()
		if(success) then
			if(#messages > 0) then
				for i, v in ipairs(messages) do
					sts = v[1]
					num = v[2]
					msg = v[3]
					
					print('Received: '..msg..' from '..num)
					cmd = string.match(msg, '(%w+) ')
					if(callbacks[cmd] ~= nil) then callbacks[cmd](m, n, s) end
				end
				try_send_cmd('AT+CMGD=1,4', 0)
			end
		else
			if(not(error_code == 4	 and get_cms_error_code(error_msg) == '314')) then
				print('Unkown error: '..error_msg)
				break
			end
		end

		if (system_on) then 
			
			-- Take samples
			adc.sample({left_sensor_id, center_sensor_id, right_sensor_id}, 1)
			tmr.delay(0, 1000)
			l_sample = math.floor(adc.getsample(left_sensor_id)/left_maxval * 10000)/100
			c_sample = math.floor(adc.getsample(center_sensor_id)/center_maxval * 10000)/100
			r_sample = math.floor(adc.getsample(right_sensor_id)/right_maxval * 10000)/100
			
			-- If debugdef print sensor values on display
			if(debugdef) then
				disp.print('Esq: '..tostring(l_p_sample or 0), 10, 30, 0)
				disp.print('Ctr: '..tostring(c_p_sample or 0), 10, 40, 0)
				disp.print('Dir: '..tostring(r_p_sample or 0), 10, 50, 0)
				disp.print('Esq: '..tostring(l_sample or 0), 10, 30, 15)
				disp.print('Ctr: '..tostring(c_sample or 0), 10, 40, 15)
				disp.print('Dir: '..tostring(r_sample or 0), 10, 50, 15)
			end
			
			
			l_p_sample = l_sample
			c_p_sample = c_sample
			r_p_sample = r_sample
			
			tmr.delay(0, 200000)
		end
		
		local test = uart.getchar(0,0)
		if(test  == 's' ) then
			system_on_off()
		elseif(test == 'd') then
			debug_on_off()
		elseif(test == 't') then
			send_status()
		elseif(test == 'e') then
			terminate()
		end
		
		if(terminate_flag) then break end
		
		tmr.delay(0,1000)
	end
end