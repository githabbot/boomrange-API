local action = function(msg, blocks, ln)
    -- save stats
    if string.match(msg.text, '^/help') then
        mystat('/help')
    else
        local hash = 'bot:general'
        local num = client:hincrby(hash, 'users', 1)
        print('Stats saved', 'Users: '..num)
		hash = 'bot:users'
		local savename = msg.from.first_name
		if msg.from.username then
			savename = savename..' [@'..msg.from.username..']'
		end
		client:hset(hash, msg.from.id, savename)
    end
    
    local out = ''
    if msg.chat.type == 'group' or msg.chat.type == 'supergroup' then
        if is_owner(msg) then
            out = out..make_text(lang[ln].help.owner)
        end
        if is_mod(msg) then
            out = out..make_text(lang[ln].help.moderator)
            api.sendMessage(msg.from.id, out, true, true)
            out = nil
        end
        out = make_text(lang[ln].help.all)
        
        api.sendReply(msg, make_text(lang[ln].help.group), true)
    end
    
    if msg.chat.type == 'private' then
        out = make_text(lang[ln].help.private, msg.from.first_name)
    end
    
    api.sendMessage(msg.from.id, out, true, true)
end

return {
	action = action,
	triggers = {
    	'^/help[@'..bot.username..']*',
	    '^/start[@'..bot.username..']*'
    }
}