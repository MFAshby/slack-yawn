extends Node
# Slack client as a node

# Network clients
onready var _http_request: HTTPRequest = HTTPRequest.new()
onready var _websocket_client: WebSocketClient =  WebSocketClient.new() 

onready var _token = OS.get_environment("SLACK_TOKEN")

# Application state
var _state = {
	# UI state
	"selected_conversation": null,
	
	# Network state...
	"fetching_conversation": null,
	
	# Data state 
	"messages": {} # Keyed by conversation
}

# Global broadcast when any state change
signal state_changed(new_state)

# Useful, not in the standard lib
static func merge_dict(target, patch):
	for key in patch:
		if target.has(key):
			var tv = target[key]
			if typeof(tv) == TYPE_DICTIONARY:
				merge_dict(tv, patch[key])
			else:
				target[key] = patch[key]
		else:
			target[key] = patch[key]

static func _key_by_id(some_list):
	var r = {}
	for i in some_list:
		r[i.id] = i
	return r
	
# All state updates should go through here, so changes get broacast
func _patch_state(patch): 
	merge_dict(self._state, patch)
	self.emit_signal("state_changed", self._state)

# Public functions to patch specific bits of the state that
# are modifiable from the UI!
func select_conversation(conversation_id: String):
	self._patch_state({"selected_conversation": conversation_id})

# gogogo
func _ready():
	OS
	self.connect("state_changed", self, "_state_changed")
	add_child(_http_request)
	_http_request.connect("request_completed", self, "_boot_complete")
	var error = _http_request.request("https://slack.com/api/rtm.start?token=" + _token)
	if error != OK:
		push_error("An error occurred on boot")

func _boot_complete(result, response_code, headers, body):
	_http_request.disconnect("request_completed", self, "_boot_complete")
	var response_json = parse_json(body.get_string_from_utf8())
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Error authenticating with slack!")
		return

	# Transform the boot response a bit, key users and channels by their ID
	# So we can patch them effectively later from RTMs received
	response_json.channels = _key_by_id(response_json.channels)
	response_json.users = _key_by_id(response_json.users)
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

var window_title_set = false

func _state_changed(new_state):
	if !window_title_set:
		OS.set_window_title("Slack: " + new_state.team.name)
		window_title_set = true
		
	# Fetch conversation history if we need to
	var c = new_state.get("selected_conversation")
	if c != null:
		if new_state.messages.get(c) == null:
			if self._state.get("fetching_conversation") == null:
				self._patch_state({"fetching_conversation": c})
			else:
				self._http_request.connect("request_completed",self, "_conversation_history_completed")
				var err = self._http_request.request("https://slack.com/api/conversations.history?token=" + _token + "&channel=" + c)
				if err != OK:
					push_error("An error occurred fetching conversation history! " + err)

func _conversation_history_completed(result, response_code, headers, body):
	self._http_request.disconnect("request_completed",self, "_conversation_history_completed")
	var response_json = parse_json(body.get_string_from_utf8())
	var c = self._state.fetching_conversation
	self._patch_state({
		"fetching_conversation": null,
		"messages": {
			c: response_json.messages
		}
	})	
