--[[ 
	PUC-Rio, 2013
	
	* Author: 
		Carlo Caratori (carlocaratori@gmail.com)
		
	* Description: 
		GSM library for Mikroeletronika GSM Click Board. Only basic SMS communication implemented
		
	* Related:
		MikroEletronika GSM Click
		http://www.mikroe.com/click/gsm/
	
		Telit GL865 Quad related documents (Hardware, Software and AT Commands)
		http://www.telit.com/en/products.php?p_ac=show&p=110
		
	* Usage:
		For SMS communication, only 3 simple functions are needed
	
		1) Initialize gsm module
		init({uart_id, rts_pio, rst_pio, baud_rate, at_wait, buffer_size})
			- uart_id			Serial/Uart channel
			- rts_pio			Board PIO connected to GSM Click RTS pin
			- rst_pio			Board PIO connected to GSM Click RST pin
			- baud_rate 		Comm speed (default=9600)
			- at_wait  			AT Command Timeout in Seconds (default=45)
			- buffer_size		UART Buffer Size (default=1024)
			
		eg.: gsm.init({uart_id = 1, rts_pio = pio.PC_5, rst_pio = pio.PC_7, baud_rate 9600, at_wait = 45, buffer_size = 1024})
		IMPORTANT: uart_id, rts_pio and rst_pio MUST be specified in init
		
		2) Send sms
		send_sms(phone_number, message)
			- phone_number		Phone number to send sms to
			- message			Message to be sent
			
		eg.: gsm.send_sms('99999999', 'Hello from eLua')
			
		3) Check for received text messages
		try_get_sms(status)
			- status			Filters messages to be retreived (check sms_status for more detail)
			RETURNS				Table with messages inside. Each message is a table itself {sts, num, msg) where:
									sts - Message status (READ or UNREAD)
									num - phone number that sent message
									msg - message itself
									
		eg.: gsm.try_get_sms(sms_status.READ)	
]]--

local uart = uart

-- GSM configuration
config = nil

-- Max tries for sending AT commands
MAX_TRIES = 3

-- Set of basic AT commands
local at_comm = {
		at_0 = 'AT',					-- Every AT command starts with "AT"
		at_1 = 'ATE0',          		-- Disable command echo
		at_2 = "AT+CMGF=1",     		-- TXT messages
		at_3 = 'AT+CMGS="',         	-- sends SMS to desired number
		at_4 = 'AT+CMGR=1',         	-- Command for reading message from location 1 from inbox
		at_5 = 'AT+CMGD=1,4',       	-- Erasing all messages from inbox
		at_6 = 'AT+CMGL=',   			-- Check status of received SMS
		at_7 = 'AT+CPIN?';				-- Check Sim Card status
	}

-- Responses codes
responses = {
		GSM_OK                       = 0,
		GSM_Ready_To_Receive_Message = 1,
		GSM_ERROR                    = 2,
		GSM_UNREAD                   = 3,
		CMS_ERROR					 = 4;
	}
	
-- Possible message status to be retreived
sms_status = {
		ALL		= 'ALL',			-- All messages	
		READ	= 'REC READ',		-- Only read messages
		UNREAD	= 'REC UNREAD';		-- Only unread messages
	}

-- Initialize gsm board and communication
function init(c)
	
	config = c
	
	if not config.uart_id then
		-- TODO - log missing uart_id
		return false
	end
	
	if not config.rts_pio then
		-- TODO - log missing rts_pio
		return false
	end
	
	if not config.rst_pio then
		-- TODO - log missing rst_pio
		return false
	end
	
	if not config.baud_rate then 
		config.baud_rate = 9600
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
	
	-- Negotiate baudrate
	if(not try_send_cmd(at_comm.at_0)) then
		print('Unable to communicate with GSM Click\nTry checking the wires and restarting the program')
		return false
	end
	
	-- Disable ECHO
	try_send_cmd(at_comm.at_1)
	
	-- Set message type as TXT
	try_send_cmd(at_comm.at_2)
	
	return true
end

-- Get response from GSM Click
function get_response()
	local rspn, rspn_code = -1
	for i=0,MAX_TRIES*3 do
		rspn = parse_line(uart.read(config.uart_id,'*l',config.at_wait))
		if(rspn ~= '') then 
			print('Recv: '..rspn)
			rspn_code = parse_response(rspn)
			break
		else tmr.delay(0,2000)
		end
	end
	return rspn, rspn_code
end

-- Wait for desired response
function wait_response(expected_rspn)
	local success = false, rspn, rspn_code
	for i=0,MAX_TRIES-1 do
		local rspn, rspn_code = get_response()
		if(rspn_code == expected_rspn ) then 
			success = true
			break
		elseif (rspn_code == responses.GSM_ERROR or rspn_code == responses.CMS_ERROR) then
			break
		else
			tmr.delay(0, 5000)
		end
	end
	return success, rspn, rspn_code
end

-- Parse received response
function parse_response(rspn)
	local ret = -1
	
	if (rspn == 'OK') then ret = responses.GSM_OK end
	if (rspn == '> ') then ret = responses.GSM_Ready_To_Receive_Message end
	if (rspn == 'ERROR') then ret = responses.GSM_ERROR end
	if (rspn:find('+CMS ERROR') ~= nil) then ret = responses.CMS_ERROR end
	
	return ret
end

-- Try send command until desired response is received
function try_send_cmd(cmd, expected_rspn)
	if(expected_rspn == nil) then expected_rspn = responses.GSM_OK end

	-- Send command
	send_at_command(cmd)
	-- Wait for expected response
	return wait_response(expected_rspn)
end

-- Send AT command
function send_at_command(cmd)
	print('Sending: '.. parse_line(cmd))
	uart.write(config.uart_id,cmd..'\r')
end

-- Send text message to specified phone number
function send_sms(phone_number, message)
	
	-- Send phone number and wait for ACK
	local at_string = at_comm.at_3..phone_number..'"\r'
	try_send_cmd(at_string, responses.GSM_Ready_To_Receive_Message)
	
	-- Send text message itself
	at_string = message..'\026'
	try_send_cmd(at_string)
	
end

-- TODO Check more than 1 sms
-- Check unread text messages
function try_get_sms(sms_status)
	local messages = {}, m, n, s			-- m = message, n = number, s = status
	local rspn, rspn_code
	if(sms_status == nil) then sms_status = '"ALL"' end
	
	send_at_command(at_comm.at_6..sms_status)
	rspn, rspn_code = get_response()
	
	if((rspn_code == responses.GSM_ERROR) or (rspn_code == responses.CMS_ERROR)) then
		return false, rspn, rspn_code, messages
	end
	
	while(rspn_code ~= responses.GSM_OK) do
		s, n = string.match(rspn, '+CMGL: %d+,"REC (%w+)","(+?%d+)"') 	-- First line of response
		m = get_response()												-- Second line of response
		rspn, rspn_code = get_response()								-- Third line of response
		if(s ~= nil or n ~= nil) then 
			table.insert(messages, {s, n, m})
		end
	end
	
	return true, rspn, rspn_code, messages
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

-- Returns CMS error code from error message
function get_cms_error_code(error_message)
	return string.match(error_message, '+CMS ERROR\: (%d+)')
end
