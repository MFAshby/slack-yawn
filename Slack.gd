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
	# Keyed by conversation
	"messages": {},
	
	# Keyed by conversation, 
	# special member "is_channel_starred" boolean value 
	# indicating if the entire channel was starred
	"stars": {}
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

# Public functions to patch specific bits of the state that
# are modifiable from the UI!
func select_conversation(conversation_id: String):
	self._patch_state({"selected_conversation": conversation_id})

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
	var err = _websocket_client.connect_to_url(response_json.url)
	if err != OK:
		push_error("Failed to connect to websocket " + response_json.url)
	
func _stars_completed(result, response_code,  headers, body):
	_stars_http_req.disconnect("request_completed", self, "_stars_completed")
	self.remove_child(_stars_http_req)
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Error fetching stars!")
		return

	# Turn the heterogenoous list to a useful lookup
	var stars = {}
	var response_json = parse_json(body.get_string_from_utf8())
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
	match payload.type:
		"hello":
			print("hello to you too, slack")
		# take the data, patch the state...
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
					push_error("An error occurred fetching conversation history! " + err)

func _conversation_history_completed(result, response_code, headers, body):
	self._conversation_http_req.disconnect("request_completed",self, "_conversation_history_completed")
	self.remove_child(_conversation_http_req)
	var response_json = parse_json(body.get_string_from_utf8())
	var c = self._state.fetching_conversation
	self._patch_state({
		"fetching_conversation": null,
		"messages": {
			c: response_json.messages
		}
	})	

# Merge dictionaries
static func md(target, patch):
	for key in patch:
		if target.has(key):
			var tv = target[key]
			if typeof(tv) == TYPE_DICTIONARY:
				md(tv, patch[key])
			else:
				target[key] = patch[key]
		else:
			target[key] = patch[key]

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
