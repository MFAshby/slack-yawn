extends Node
# Slack client as a node

# Pull the token from the environment
# Should probably implement the v1 oauth flow for normal login
onready var _token = OS.get_environment("SLACK_TOKEN")

# Network clients
onready var _websocket_client: WebSocketClient =  WebSocketClient.new() 
onready var _boot_http_req = HTTPRequest.new()
onready var _stars_http_req = HTTPRequest.new()
onready var _conversation_http_req = HTTPRequest.new()

# Application state
var _state = {
	# UI state
	"selected_conversation": null,
	
	# Network state...
	"fetching_conversation": null,
	
	# Data state 
	# Keyed by conversation, then by ts
	"messages": {},
	
	# Keyed by conversation, 
	# special member "is_channel_starred" boolean value 
	# indicating if the entire channel was starred
	"stars": {},
	
	# Pending messages, keyed by our assigned id
	"pending_messages": {}
}

# Global broadcast when any state change
# Make sure to include both states
signal state_changed(old_state, new_state)

# All state updates should go through here, so changes get broacast
func _patch_state(patch): 
	var old_state = _state
	var new_state = {}
	md(new_state, old_state)
	md(new_state, patch)
	self._state= new_state
	self.emit_signal("state_changed", old_state, new_state)
	
# The only other function for modifying state, allow deleting state
func _del_state(path: Array):
	var old_state = _state
	var new_state = {}
	md(new_state, old_state)
	dp(new_state, path)
	self._state= new_state
	self.emit_signal("state_changed", old_state, new_state)

# Public functions to patch specific bits of the state that
# are modifiable from the UI!
func select_conversation(conversation_id: String):
	self._patch_state({"selected_conversation": conversation_id})
	
# As per slack docs,you need an incrementing message counter
# for each message you send via the RTM API
var _next_message_id = 1 
func send_message(text, cid = null):
	if cid == null:
		cid = self._state["selected_conversation"]
	if cid == null:
		push_error("Sending a message, but no conversation selected")
		return
	var i = self._next_message_id
	self._next_message_id = i+1
	var pm = {
		"id": i,
		"type": "message",
		"channel": cid, 
		"text": text,
		"user": fd(self._state, ["self", "id"])
	}
	var err = _websocket_client.get_peer(1).put_packet(to_json(pm).to_utf8())
	if err != OK:
		push_error("Failed to send message!")
	# Bug,can't use integer keys :S
	self._patch_state({"pending_messages": {str(i): pm}})

# gogogo
func _ready():
	self.connect("state_changed", self, "_state_changed")

	# Fetch boot info	
	add_child(_boot_http_req)
	_boot_http_req.connect("request_completed", self, "_boot_complete")
	var error = _boot_http_req.request("https://slack.com/api/rtm.start?token=" + _token)
	if error != OK:
		push_error("An error occurred on boot")
		
	# Fetch stars
	add_child(_stars_http_req)
	_stars_http_req.connect("request_completed", self, "_stars_completed")
	var err = _stars_http_req.request("https://slack.com/api/stars.list?token=" + _token)
	if err != OK:
		push_error("Failed to fetch stars")

func _boot_complete(result, response_code, headers, body):
	_boot_http_req.disconnect("request_completed", self, "_boot_complete")
	self.remove_child(_boot_http_req)
	var response_json = parse_json(body.get_string_from_utf8())
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Error authenticating with slack!")
		return

	var err = response_json.get("error")
	if err != null:
		push_error(err)
		return

	# Transform the boot response a bit, key users and channels by their ID
	# So we can patch them effectively later from RTMs received
	response_json.channels = ki(response_json.channels)
	response_json.users = ki(response_json.users)
	response_json.groups = ki(response_json.groups)
	response_json.ims = ki(response_json.ims)
	
	# Just bung the entire boot response into the state
	self._patch_state(response_json)
	
	# RTM Websocket setup
	_websocket_client.connect("connection_closed", self, "_ws_closed")
	_websocket_client.connect("connection_error", self, "_ws_error")
	_websocket_client.connect("data_received", self, "_ws_data")
	print("Connecting to websocket at " + response_json.url)
	err = _websocket_client.connect_to_url(response_json.url)
	if err != OK:
		push_error("Failed to connect to websocket " + response_json.url)
	
func _stars_completed(result, response_code,  headers, body):
	_stars_http_req.disconnect("request_completed", self, "_stars_completed")
	self.remove_child(_stars_http_req)
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Error fetching stars!")
		return

	var response_json = parse_json(body.get_string_from_utf8())
	var err = response_json.get("error")
	if err != null:
		push_error(err)
		return
		
	# Turn the heterogenoous list to a useful lookup
	var stars = {}
	for i in response_json.items:
		match i.type:
			"im": continue
			"channel": 
				var cid: String = i.channel
				md(stars, {cid: {"is_channel_starred": true}})
			"group":
				var cid: String = i.group
				md(stars, {cid: {"is_channel_starred": true}})
			_: 
				pass
	self._patch_state({"stars": stars})
func _ws_closed():
	push_error("_ws_closed")
	
func _ws_error():
	push_error("_ws_error")
	
func _ws_data():
	var payload = parse_json(_websocket_client.get_peer(1).get_packet().get_string_from_utf8())

	if payload.has("reply_to") and payload.has("ok"):
		if payload.ok:
			# Upgrade pending message to a real one
			var pm = self.fd(self._state, ["pending_messages", str(payload.reply_to)])
			var nm = {}
			md(nm, pm)
			md(nm, payload)
			self._del_state(["pending_messages", str(payload.reply_to)])
			self._patch_state({
				"messages": {nm.channel: {nm.ts: nm}}
			})
		else:
			push_error("Message failed for some reason?!?")
		return
	match payload.type:
		"hello":
			print("hello to you too, slack")
		# take the data, patch the state...
		"message":
			print("Received message", payload)
			self._patch_state({"messages": {payload.channel: {payload.ts: payload}}})
		_: 
			print("message received but not handled ", payload)

func _process(delta):
	_websocket_client.poll()

func _state_changed(old_state, new_state):
	var old_team_name = fd(old_state, ["team", "name"])
	var new_team_name = fd(new_state, ["team", "name"])
	if old_team_name != new_team_name:
		OS.set_window_title("Slack: " + new_state.team.name)
		
	# Fetch conversation history if we need to
	var c = new_state.get("selected_conversation")
	if c != null:
		if new_state.messages.get(c) == null:
			if self._state.get("fetching_conversation") == null:
				self._patch_state({"fetching_conversation": c})
			else:
				self.add_child(_conversation_http_req)
				self._conversation_http_req.connect("request_completed",self, "_conversation_history_completed")
				var err = self._conversation_http_req.request("https://slack.com/api/conversations.history?token=" + _token + "&channel=" + c)
				if err != OK:
					push_error("An error occurred fetching conversation history! ")

func _conversation_history_completed(result, response_code, headers, body):
	self._conversation_http_req.disconnect("request_completed",self, "_conversation_history_completed")
	self.remove_child(_conversation_http_req)
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Failed to fetch conversation!")
		return
	var response_json = parse_json(body.get_string_from_utf8())
	var c = self._state.fetching_conversation
	self._patch_state({
		"fetching_conversation": null,
		"messages": {
			# ts is basically the key for a message
			# and also the sort order
			c: k(response_json.messages, "ts")
		}
	})	

# Merge dictionaries
static func md(target: Dictionary, patch):
	for key in patch:
		if target.has(key):
			var tv = target[key]
			if typeof(tv) == TYPE_DICTIONARY:
				md(tv, patch[key])
			else:
				target[key] = patch[key]
		else:
			target[key] = patch[key]

# Deletes an object at the specified path in the nested dictionary
# Returns true if it deleted something, false otherwise.
static func dp(target: Dictionary, path: Array):
	while true:
		if target == null:
			return null
		elif len(path) == 1:
			return target.erase(path[0])
		else:
			var key = path.pop_front()
			target = target.get(key)

# Transform a list to a dict with a key
static func k(lst, key):
	var r = {}
	for i in lst:
		r[i[key]] = i
	return r

# Transform a list to a dict, using id as a key
static func ki(lst):
	return k(lst, "id")
	
# Finds an object at a path in a nested dict
# Can return null
static func fd(obj, path: Array):
	while true:
		if len(path) == 0:
			return obj
		if obj == null:
			return null
		var key = path.pop_front()
		obj = obj.get(key)
