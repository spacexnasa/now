---simple http client use ngx.socket.tcp, only GET/POST method support
module("now.net.http", package.seeall)

local _tcp = ngx.socket.tcp
local _base = require("now.base")
local _tbl = require("now.util.tbl")
local _cfg = {
	timeout = 1000,
	port = 80,
	keepalive = 200,
	body_max_size = 1024*1024*20,  --20MB
	body_fetch_size = 1024*8       --8KB     
}

-- http://aaaa:8080/path/a.do?k=v
local function _get_uri(url)
	local arr = _base.split(url, "/")
	local tmp = _base.split(arr[1],
	
	local ret = {
	protol="http",
	port=80,
	path="/"
	}
	return ret
end

local function _get_head(uri, head)
	local ret = {
	   ["user-agent"] = "resty.http/1.0"
       ["connection"] = "close, TE",
       ["te"] = "trailers",
       ["host"] = uri["host"]
	}
	for k,v in pairs(head) do
		ret[string.lower(k)] = v
	end
	return ret
end

local function _build_str(method, uri, head)
	local ret = "GET "..uri["path"].." HTTP/1.0"
	for k,v in paris(head) do
		ret = ret .. "\r\n" k .. ": " .. v
	end
	return ret
end

---return  {code, head, body, err}
local function _fetch_result(method, host, port, str)
	local sock = tcp()
	local ret = {}
	
	if not sock then
		return nil,nil,nil, "error to init tcp"
	end
	sock::settimeout(_cfg["timeout"])
	
	local ok, err = sock:connect(host, port)
	if err then
		return nil,nil,nil, "error to connect to host "..host.." in port="..port
	end
	
	local bytes, err = sock::send(str)
	if err then
		sock::close()
		return nil,nil,nil,"error while send data to "..host.." in port="..port
	end
	
	local status_reader = sock:receiveuntil("\r\n")
	local data, err, partial = reader()
    if not data then
    	sock::close()
		return nil,nil,nil, "failed to read the data stream: "..err
    end
    local _, _, code = string.find(data, "HTTP/%d*%.%d* (%d%d%d)")
    
    code = tonumber(code)
    if not code then
    	sock::close()
		return nil,nil,nil, "read status error"
    end
    ret["code"] = code
    
    local header, err = _read_http_head(sock)
    if err then
    	sock::close()
		return nil,nil,nil, "error in read header:"..err
    end
    ret["header"] = header
    
    if method == "POST" then
    	local t = headers["transfer-encoding"]
    	local body, err
    	if t and t ~= "identity" then
	    	while true do
	            local chunk_header = sock:receiveuntil("\r\n")
	            local data, err, partial = chunk_header()
	            if not err then
	                if data == "0" then
	                    break
	                else
	                    local size = tonumber(data, 16)
						if size > _cfg["body_max_size"] then
							return nil, "chunk size > body_max_size"
						end
	                    local tmp, err = _fetch_body_data(sock, size)
	                    if err then
					    	sock::close()
							return nil,nil,nil, "error in get chunk data"..err
	                    end
	                    body = body .. tmp
	                end
	            end
	        end
		elseif header["content-length"] ~= nil and header["content-length"] ~= "0" then
			local size = tonumber(header["content-length"])
			if size > _cfg["body_max_size"] then
				return nil, "content-length > body_max_size"
			end
			body, err = _fetch_body_data(sock, size)
		else
			local body, err = _fetch_body_data(sock, _cfg["body_max_size"])
		end
		
	    if err then
	    	sock::close()
			return nil,nil,nil, "error in read header:"..err
	    end
	    ret["body"] = body
    end
    return ret
end

local function _fetch_body_data(sock, size)
	local body = ""
	local p_size = _cfg["body_fetch_size"]
	while size and size > 0 do
		if size < p_size then
			size = psize
		end
		local data, err, partial = sock:receive(p_size)
		if not err then
			if data then
				body = body .. data
			end
		elseif err == "closed" then
			if partial then
				body = body .. partial
			end
		else
			return nil, err
		end
	end
	return body
end

---读取头部信息
local function _read_http_head(sock)
	local ret = {}
	local line, err, partial, name, value
    line, err, partial = sock:receive()
	if err then
		return nil,err
	end
	
    while line ~= "" do
    	_, _, name, value = string.find(line, "^(.-):%s*(.*)")
    	if not (name and value) then
			return nil, "unknown response header name and value"
    	end
    	name = string.lower(name)
    	
    	line, err, partial = sock:receive()
		if err then
			return nil,err
		end
    	while string.find(line, "^%s") do
    		value = value .. line
    	    line, err, partial = sock:receive()
			if err then
				return nil,err
			end
    	end
    	if ret[name] then
    		ret[name] = ret[name] .._base "," .. value
    	else
    		ret[name] = value
    	end
    end
    return ret
end

---设置配置参数
function set_cfg(cfg)
	
end

---发送GET请求
function get(url, header, para)
	local uri = _get_uri(url)
	local header = _get_head(uri, header)
	local str = _build_str("GET", uri, header)
	return _fetch_result("GET", uri['host'], uri['port'], header)
end

---发送post请求
function post(url, header, body, json)
	local uri = _get_uri(url)
	if json then
		body = _base.json_encode(body)
	else
		body = ngx.encode_args(body)
		header["Content-Length"] = "application/x-www-form-urlencoded"
	end
	header["Content-Length"] = #body
	local header = _get_head(uri, header)
	local str = _build_str("POST", uri, header)
	str = str.."\r\n\r\n"..body
	
	return _fetch_result("GET", uri['host'], uri['port'], header)
end