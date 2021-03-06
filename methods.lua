

local BASE_URL = 'https://api.telegram.org/bot' .. config.bot_api_key

if not config.bot_api_key then
	error('You did not set your bot token in config.lua!')
end

local function sendRequest(url, user_id)

	local dat, code = HTTPS.request(url)
	
	if not dat then 
		return false, code 
	end
	
	local tab = JSON.decode(dat)

	if code ~= 200 then
		client:hincrby('bot:errors', code, 1)
		print(code)
		--403: bot blocked, 429: spam limit ...send a message to the admin, return the code
		if code ~= 403 and code ~= 429 then
			print(tab.description)
			api.sendMessage(config.admin, vtext(dat)..'\n'..code..'\n(text in the log)')
			return false, code
		end
		return false, false --if the message is not sent because the bot is blocked, then don't return the code
	end
	
	--actually, this rarely happens
	if not tab.ok then
		return false, tab.description
	end

	return tab

end

local function getMe()

	local url = BASE_URL .. '/getMe'

	return sendRequest(url)

end

local function getUpdates(offset)

	local url = BASE_URL .. '/getUpdates?timeout=20'

	if offset then
		url = url .. '&offset=' .. offset
	end

	return sendRequest(url)

end

local function getKickError(error)
	error = error:gsub('%[Error%]: Bad Request: ', '')
	local known_errors = {
		[101] = 'Not enough rights to kick participant', --SUPERGROUP: bot is not admin
		[102] = 'USER_ADMIN_INVALID', --SUPERGROUP: trying to kick an admin
		[103] = 'method is available for supergroup chats only', --NORMAL: trying to unban
		[104] = 'Only creator of the group can kick admins from the group', --NORMAL: trying to kick an admin
		[105] = 'Need to be inviter of the user to kick it from the group' --NORMAL: bot is not an admin or everyone is an admin
	}
	for k,v in pairs(known_errors) do
		if error == v then
			return k
		end
	end
	return 106 --if unknown
end

local function unbanChatMember(chat_id, user_id)
	
	local url = BASE_URL .. '/unbanChatMember?chat_id=' .. chat_id .. '&user_id=' .. user_id

	--return sendRequest(url)
	
	local dat, res = HTTPS.request(url)
	
	local tab = JSON.decode(dat)

	if res ~= 200 then
		return false, res
	end

	if not tab.ok then
		return false, tab.description
	end

	return tab
	
end

local function kickChatMember(chat_id, user_id)

	local url = BASE_URL .. '/kickChatMember?chat_id=' .. chat_id .. '&user_id=' .. user_id

	--return sendRequest(url)
	
	local dat, res = HTTPS.request(url)

	local tab = JSON.decode(dat)

	if res ~= 200 then
		return false, api.getKickError(tab.description)
	end

	if not tab.ok then
		return false, tab.description
	end

	return tab

end

local function code2text(code, ln, chat_id)
	if code == 101 then
		return lang[ln].kick_errors[code]
	elseif code == 102 then
		return lang[ln].kick_errors[code]
	elseif code == 103 then
		return lang[ln].kick_errors[code]
	elseif code == 104 then
		return lang[ln].kick_errors[code]
	elseif code == 105 then
		return lang[ln].kick_errors[code]
	elseif code == 106 then
		return false
	end
end

local function banUser(chat_id, user_id, ln, arg1, no_msg)--arg1: should be the name, no_msg: kick without message if kick is failed
	local name = arg1
	if not name then name = 'User' end
	res, code = api.kickChatMember(chat_id, user_id) --kick
	if res then
		no_msg = false
		text = make_text(lang[ln].banhammer.banned, name)
		client:hincrby('bot:general', 'ban', 1)
	else
		text = api.code2text(code, ln, chat_id)
	end
	if no_msg then
		return res
	else
		api.sendMessage(chat_id, text, true)
		return res
	end
end

local function kickUser(chat_id, user_id, ln, arg1, no_msg)--arg1: should be the name, no_msg: don't send the error message if kick is failed. If no_msg is false, it will return the motivation of the fail
	local name = arg1
	if not name then name = 'User' end
	res, code = api.kickChatMember(chat_id, user_id)
	if res then
		local hash = 'kicked:'..chat_id
	    client:hset(hash, user_id, name) --save the id in the kicked list
	    client:hincrby('bot:general', 'kick', 1) --genreal: save how many kicks
		api.unbanChatMember(chat_id, user_id)
		text = make_text(lang[ln].banhammer.kicked, name)
		no_msg = false --if the bot kicked successfully, then send a message with the motivation
	else
		text = api.code2text(code, ln, chat_id)
	end
	--check if send a message after the kick
	if no_msg or code == 106 then --if no_msg (don't reply with the error) or the error is unknown then..
		return res
	else
		local sent, code_msg = api.sendMessage(chat_id, text, true)
		return res
	end
end

local function sendMessage(chat_id, text, use_markdown, disable_web_page_preview, reply_to_message_id, send_sound)

	local url = BASE_URL .. '/sendMessage?chat_id=' .. chat_id .. '&text=' .. URL.escape(text)

	url = url .. '&disable_web_page_preview=true'

	if reply_to_message_id then
		url = url .. '&reply_to_message_id=' .. reply_to_message_id
	end
	
	if use_markdown then
		url = url .. '&parse_mode=Markdown'
	end
	
	if not send_sound then
		url = url..'&disable_notification=true'--messages are silent by default
	end
	
	local res, code = sendRequest(url)
	
	if not res and code then --if the request failed and a code is returned (not 403 and 429)
		print('Delivery failed')
		save_log('send_msg', text)
	end
	
	return res, code --return false, and the code

end

local function sendReply(msg, text, markd, send_sound)

	return sendMessage(msg.chat.id, text, markd, true, msg.message_id, send_sound)

end

local function sendChatAction(chat_id, action)
 -- Support actions are typing, upload_photo, record_video, upload_video, record_audio, upload_audio, upload_document, find_location

	local url = BASE_URL .. '/sendChatAction?chat_id=' .. chat_id .. '&action=' .. action
	return sendRequest(url)

end

local function sendLocation(chat_id, latitude, longitude, reply_to_message_id)

	local url = BASE_URL .. '/sendLocation?chat_id=' .. chat_id .. '&latitude=' .. latitude .. '&longitude=' .. longitude

	if reply_to_message_id then
		url = url .. '&reply_to_message_id=' .. reply_to_message_id
	end

	return sendRequest(url)

end

local function forwardMessage(chat_id, from_chat_id, message_id)

	local url = BASE_URL .. '/forwardMessage?chat_id=' .. chat_id .. '&from_chat_id=' .. from_chat_id .. '&message_id=' .. message_id

	return sendRequest(url)
	
end

local function curlRequest(curl_command)
 -- Use at your own risk. Will not check for success.

	io.popen(curl_command)

end

local function sendPhoto(chat_id, photo, caption, reply_to_message_id)

	local url = BASE_URL .. '/sendPhoto'

	local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "photo=@' .. photo .. '"'

	if reply_to_message_id then
		curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
	end

	if caption then
		curl_command = curl_command .. ' -F "caption=' .. caption .. '"'
	end

	return curlRequest(curl_command)

end

local function sendDocument(chat_id, document, reply_to_message_id)

	local url = BASE_URL .. '/sendDocument'

	local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "document=@' .. document .. '"'

	if reply_to_message_id then
		curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
	end

	return curlRequest(curl_command)

end

local function sendSticker(chat_id, sticker, reply_to_message_id)

	local url = BASE_URL .. '/sendSticker'

	local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "sticker=@' .. sticker .. '"'

	if reply_to_message_id then
		curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
	end

	return curlRequest(curl_command)

end

local function sendAudio(chat_id, audio, reply_to_message_id, duration, performer, title)

	local url = BASE_URL .. '/sendAudio'

	local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "audio=@' .. audio .. '"'

	if reply_to_message_id then
		curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
	end

	if duration then
		curl_command = curl_command .. ' -F "duration=' .. duration .. '"'
	end

	if performer then
		curl_command = curl_command .. ' -F "performer=' .. performer .. '"'
	end

	if title then
		curl_command = curl_command .. ' -F "title=' .. title .. '"'
	end

	return curlRequest(curl_command)

end

local function sendVideo(chat_id, video, reply_to_message_id, duration, performer, title)

	local url = BASE_URL .. '/sendVideo'

	local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "video=@' .. video .. '"'

	if reply_to_message_id then
		curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
	end

	if caption then
		curl_command = curl_command .. ' -F "caption=' .. caption .. '"'
	end

	if duration then
		curl_command = curl_command .. ' -F "duration=' .. duration .. '"'
	end

	return curlRequest(curl_command)

end

local function sendVoice(chat_id, voice, reply_to_message_id)

	local url = BASE_URL .. '/sendVoice'

	local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "voice=@' .. voice .. '"'

	if reply_to_message_id then
		curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
	end

	if duration then
		curl_command = curl_command .. ' -F "duration=' .. duration .. '"'
	end

	return curlRequest(curl_command)

end

return {
	sendMessage = sendMessage,
	sendRequest = sendRequest,
	getMe = getMe,
	getUpdates = getUpdates,
	sendVoice = sendVoice,
	sendVideo = sendVideo,
	sendAudio = sendAudio,
	sendSticker = sendSticker,
	sendDocument = sendDocument,
	sendPhoto = sendPhoto,
	curlRequest = curlRequest,
	forwardMessage = forwardMessage,
	sendLocation = sendLocation,
	sendChatAction = sendChatAction,
	unbanChatMember = unbanChatMember,
	kickChatMember = kickChatMember,
	banUser = banUser,
	kickUser = kickUser,
	sendReply = sendReply,
	getKickError = getKickError,
	code2text = code2text
}	