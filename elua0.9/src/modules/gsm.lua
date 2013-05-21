
--[[ 
	GSM library for Mikroeletronika GSM Click Board
		
	init(id, [baudrate], [at_wait])
		- uart_id			Serial/Uart channel
		- rts_pio			Board PIO connected to GSM Click RTS pin (default=pio.PC_5)
		- rst_pio			Board PIO connected to GSM Click RST pin (default=pio.PC_7)		
		- baud_rate 		Comm speed (default=9600)
		- at_wait  			AT Command Timeout in Seconds (default=45)
		- buffer_size		UART Buffer Size (default=1024)
]]--

local uart = uart

-- GSM configuration
config = nil

-- Set of basic AT commands
local at_comm = {
		at_0 = 'AT',					-- Every AT command starts with "AT"
		at_1 = 'ATE0',          		-- Disable command echo
		at_2 = "AT+CMGF=1",     		-- TXT messages
		at_3 = 'AT+CMGS="',         	-- sends SMS to desired number
		at_4 = 'AT+CMGR=1',         	-- Command for reading message from location 1 from inbox
		at_5 = 'AT+CMGD=1,4',       	-- Erasing all messages from inbox
		at_6 = 'AT+CMGL="REC READ"',   		-- Check status of received SMS
		at_7 = 'AT+CPIN?';				-- Check Sim Card status
	}

-- Responses to parse
local responses = {
		GSM_OK                       = 0,
		GSM_Ready_To_Receive_Message = 1,
		GSM_ERROR                    = 2,
		GSM_UNREAD                   = 3,
		CMS_ERROR					 = 10;
	}

-- Initialize gsm connection 
function init(c)
	
	config = c
	
	if not config.baud_rate then 
		config.baud_rate = 9600
	end
	
	if not config.rts_pio then
		config.rts_pio = pio.PC_5
	end
	
	if not config.rst_pio then
		config.rst_pio = pio.PC_7
	end
	
	if not config.at_wait then
		config.at_wait = 10000000
	else
		config.at_wait = config.at_wait * 1000000
	end
	
	if not config.buffer_size then
		config.buffer_size = 1024
	end
	
	-- Set RTS pin to zero
	pio.pin.setdir(pio.OUTPUT, config.rts_pio)
	pio.pin.setlow(config.rts_pio)
	
	-- Turn on the GL865 (Hardware reset)
	pio.pin.setdir(pio.OUTPUT, config.rst_pio)
	pio.pin.setlow(config.rst_pio)
	pio.pin.sethigh(config.rst_pio)
	tmr.delay(0, 2500000)							-- Hold it for at least two seconds
	pio.pin.setlow(config.rst_pio)
	
	-- Initialize uart
	uart.setup(config.uart_id, config.baud_rate, 8, uart.PAR_NONE, uart.STOP_1)
	uart.set_buffer(config.uart_id, config.buffer_size)
	
	-- Wait a while till the GSM network is configured
	tmr.delay(0, 3000000)
	
	negotiate_baudrate()
	
	-- Disable ECHO
	try_send_cmd(at_comm.at_1)
	
	-- Set message type as TXT
	try_send_cmd(at_comm.at_2)
	
	print("GSM initialized!")
end

-- Print GSM configuration
function print_config()
	print("Config: \n")
	for i, v in pairs(config) do print(i, v) end
end

-- Negotiate the baudrate
function negotiate_baudrate()
	while(true) do
		send_at_command(at_comm.at_0)
		tmr.delay(0, 100)
		line = get_response()
		if line ~= nil then
			if (parse_response(line) == 0) then break end
		end
		tmr.delay( 0, 500 )
	end
end

-- Receive line from uart
function uart_recv_line()
	local line = uart.read(config.uart_id,'*l',config.at_wait)
	return parse_line(line)
end

-- Wait for desired response
function wait_response(rspn)
	while (true) do
		local line = get_response()
		local r = parse_response(line)
		if(r == rspn ) then 
			return true
		elseif (r == responses.GSM_ERROR or r == responses.CMS_ERROR) then
			return false
		else
			tmr.delay(0, 5000)
		end
	end
end

function get_response()
	while(true) do
		local line = uart_recv_line()
		if(line ~= '') then 
			print('Recv: '..line)
			return line
		else tmr.delay(0,5000)
		end
	end
end

function parse_response(rspn)
	local ret = -1
	
	if (rspn == 'OK') then ret = 0 end
	if (rspn == '> ') then ret = 1 end
	if (rspn == 'ERROR') then ret = 2 end
	if (rspn:find('+CMS ERROR') ~= nil) then ret = 10 end
	
	return ret
end

-- Try send command until desired response is received
function try_send_cmd(cmd, expected_rspn)
	if(expected_rspn == nil) then expected_rspn = responses.GSM_OK end
	while(true) do
		-- Send command
		send_at_command(cmd)
		-- Wait for expected response
		if(wait_response(expected_rspn)) then break end
	end
end

-- Send AT command
function send_at_command(cmd)
	print('Sending: '.. parse_line(cmd))
	uart.write(config.uart_id,cmd..'\r')
end

-- Send text message to specified phone number
function send_sms(phone_number, message)
	
	-- Send phone number and wait for ACK
	local at_string = at_comm.at_3..phone_number
	try_send_cmd(at_string, responses.GSM_Ready_To_Receive_Message)
	
	-- Send text message itself
	at_string = message..'\026'
	try_send_cmd(at_string)
	
end

-- Check unread text messages
function try_get_sms()
	local messages = {}, m, n, s			-- m = message, n = number, s = status
	send_at_command(at_comm.at_6)
	local response = get_response()
	if((parse_response(response) ~= responses.GSM_OK) and (parse_response(response) ~= responses.GSM_ERROR) and (parse_response(response) ~= responses.CMS_ERROR)) then
		s = string.match(response, '(REC%s%w+)') 	-- First line of response
		n = string.match(response, '(+%d+)')
		m = get_response()							-- Second line of response
		print(n..' '..m..' '..s)
		if(parse_response(get_response()) == responses.GSM_OK) then 
			table.insert(messages, {s, n, m})
		end
	end
	return messages
end

--------------------------------------------------------------------
-- Aux functions
-------------------

-- Eliminates all control characters from 
function parse_line(line)
	return string.gsub(line,'(%c)','')
end

-- Finds a pattern within a text
function find_pattern(text, pattern, start)
	return string.sub(text, string.find(text, pattern, start))
end

-- Main
init({uart_id = 1})
tmr.delay(0, 1000000)
try_send_cmd(at_comm.at_7)
try_get_sms()
--try_send_cmd(at_comm.at_6)
--send_sms('+552193923011', 'teste')

